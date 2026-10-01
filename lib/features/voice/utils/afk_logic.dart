/// Pure AFK (away-from-keyboard) decision logic for the voice stack, extracted
/// so the state machine can be unit-tested without timers or input hooks.
library;

/// Idle timeouts offered in Voice & Video settings, in minutes. `0` disables
/// AFK detection entirely.
///
/// `AccordSpace.afkTimeout` is ignored: the server defaults it to 300s on every
/// space and never enforces it, so honouring it would silently override the
/// user's choice everywhere.
const List<int> afkTimeoutOptionsMinutes = [0, 1, 5, 10, 15, 30];

/// Default idle timeout, in minutes.
const int defaultAfkTimeoutMinutes = 10;

/// Human label for an [afkTimeoutOptionsMinutes] entry.
String afkTimeoutLabel(int minutes) {
  if (minutes <= 0) return 'Off';
  if (minutes == 1) return '1 minute';
  return '$minutes minutes';
}

/// The idle timeout to apply, or null when AFK detection is off.
Duration? effectiveAfkTimeout(int userMinutes) =>
    userMinutes <= 0 ? null : Duration(minutes: userMinutes);

/// How often the monitor should re-evaluate for a given [timeout]: a quarter of
/// the timeout, clamped to 1–15s. Short enough that the AFK flip is prompt,
/// long enough that a 30-minute timeout isn't polling the mic every second.
Duration afkPollInterval(Duration timeout) => Duration(
  milliseconds: (timeout.inMilliseconds ~/ 4).clamp(1000, 15000),
);

/// The AFK state machine: a "last activity" timestamp plus the derived AFK
/// flag. Every method takes `now` so tests can step time directly.
///
/// AFK only accrues while connected to voice with a timeout configured — [tick]
/// resets the idle clock otherwise, so a user idle for an hour before joining a
/// call is *not* instantly AFK on join.
class AfkTracker {
  AfkTracker({required DateTime now}) : _lastActivityAt = now;

  DateTime _lastActivityAt;
  bool _afk = false;

  /// Whether the user is currently considered away.
  bool get isAfk => _afk;

  /// Records user activity at [now]. Returns true when this *cleared* an
  /// existing AFK state, i.e. the caller should publish "back".
  bool markActivity(DateTime now) {
    if (!now.isBefore(_lastActivityAt)) _lastActivityAt = now;
    if (!_afk) return false;
    _afk = false;
    return true;
  }

  /// Re-evaluates AFK at [now]. Returns true when [isAfk] changed.
  ///
  /// [connected] is whether we're in a voice channel; [timeout] is null when
  /// the user has AFK detection switched off.
  bool tick({
    required DateTime now,
    required bool connected,
    required Duration? timeout,
  }) {
    if (!connected || timeout == null || timeout <= Duration.zero) {
      // Not eligible: hold the idle clock at "now" so eligibility starting
      // later begins a fresh countdown, and drop any stale AFK flag.
      _lastActivityAt = now;
      if (!_afk) return false;
      _afk = false;
      return true;
    }
    final next = now.difference(_lastActivityAt) >= timeout;
    if (next == _afk) return false;
    _afk = next;
    return true;
  }
}
