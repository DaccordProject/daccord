import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';

// Pure send-cooldown logic for the message composer (#330): channel slowmode
// (`rate_limit`), the per-user upload budgets, and the server's 429 replies to
// either. Kept free of widgets so it can be unit-tested directly.
//
// The server is authoritative. Everything here only predicts what it will say
// (so Send isn't left busy for a round-trip that is bound to fail) and mirrors
// what it did say (a `retry_after`) as a countdown the user can act on.
// Nothing auto-resends.

/// Why the composer is holding a send back.
enum SendCooldownKind {
  /// The channel's slowmode: one message per `rate_limit` seconds, so text
  /// and attachments alike wait it out.
  slowmode,

  /// A 429 outside slowmode — in practice one of the upload budgets. Only
  /// uploads are held back; text is still free to go.
  rateLimited,
}

/// A deadline before which the composer won't offer another send.
class SendCooldown {
  const SendCooldown({required this.until, required this.kind});

  final DateTime until;
  final SendCooldownKind kind;

  bool isActive(DateTime now) => until.isAfter(now);

  Duration remaining(DateTime now) {
    final left = until.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  @override
  String toString() => 'SendCooldown($kind until $until)';
}

/// Why a send didn't go through, with the server's cooldown when it gave one.
///
/// Replaces the bare failure string the controllers used to return: a 429's
/// `retry_after` has to travel with the message, or the composer can only show
/// "rate limited" and guess when Send may be offered again.
class SendFailure {
  const SendFailure(this.message, {this.retryAfter, this.rateLimited = false});

  /// Reads a failed [RestResult]: the server's own message (or [fallback]),
  /// and — for a 429 — its `retry_after`.
  factory SendFailure.fromResult(RestResult result, String fallback) {
    final error = result.error;
    final rateLimited =
        result.statusCode == 429 || (error?.isRateLimited ?? false);
    return SendFailure(
      result.errorMessageOr(fallback),
      retryAfter: rateLimited ? error?.retryAfter : null,
      rateLimited: rateLimited,
    );
  }

  /// The reason to show the user.
  final String message;

  /// How long the server asked us to wait, when this was a rate limit.
  final Duration? retryAfter;

  /// Whether the server rejected the send as rate-limited (slowmode or an
  /// upload budget — it doesn't say which).
  final bool rateLimited;

  @override
  String toString() =>
      'SendFailure($message, rateLimited: $rateLimited, retryAfter: $retryAfter)';
}

/// Whether the current user is exempt from slowmode in a channel: effective
/// `manage_messages` or `manage_channels` (after channel overrides), space
/// ownership, or instance admin — the same set the server exempts.
bool isSlowmodeExempt({
  required Set<String> channelPermissions,
  required bool isSpaceOwner,
  required bool isInstanceAdmin,
}) {
  if (isInstanceAdmin || isSpaceOwner) return true;
  return accordHasPermission(
        channelPermissions,
        AccordPermission.manageMessages,
      ) ||
      accordHasPermission(channelPermissions, AccordPermission.manageChannels);
}

/// The slowmode the composer should enforce locally: the channel's
/// `rate_limit` in seconds, or 0 when it's off, unknown, or the user is
/// [exempt].
int effectiveSlowmodeSeconds({
  required AccordChannel? channel,
  required bool exempt,
}) {
  if (exempt) return 0;
  return channel?.rateLimitSeconds ?? 0;
}

/// The local cooldown to start after a send the server accepted, or null when
/// the channel has no slowmode (or the user is exempt).
SendCooldown? cooldownAfterSend({
  required int slowmodeSeconds,
  required DateTime now,
}) {
  if (slowmodeSeconds <= 0) return null;
  return SendCooldown(
    until: now.add(Duration(seconds: slowmodeSeconds)),
    kind: SendCooldownKind.slowmode,
  );
}

/// The cooldown a failed send dictates, or null when it wasn't a rate limit
/// (or the server said to retry straight away). Replaces any local guess — the
/// server's `retry_after` is the truth.
///
/// A 429 in a slowmode channel is shown as slowmode; anywhere else it's the
/// generic rate limit (an upload budget), which only holds uploads back.
SendCooldown? cooldownFromFailure({
  required SendFailure failure,
  required int slowmodeSeconds,
  required DateTime now,
}) {
  if (!failure.rateLimited) return null;
  final wait = failure.retryAfter ?? AccordRest.defaultRetryAfter;
  if (wait <= Duration.zero) return null;
  return SendCooldown(
    until: now.add(wait),
    kind: slowmodeSeconds > 0
        ? SendCooldownKind.slowmode
        : SendCooldownKind.rateLimited,
  );
}

/// Whether Send should be withheld right now. Slowmode blocks everything; a
/// plain rate limit (an upload budget) only blocks a send that still carries
/// attachments, so text keeps flowing in a channel without slowmode.
bool sendBlockedByCooldown({
  required SendCooldown? cooldown,
  required DateTime now,
  required bool hasAttachments,
}) {
  if (cooldown == null || !cooldown.isActive(now)) return false;
  return cooldown.kind == SendCooldownKind.slowmode || hasAttachments;
}

/// Renders a wait for the countdown, rounding up so it never reads "0s" while
/// still blocked: "12s", "1m 5s", "2h 0m".
String formatCooldown(Duration wait) {
  final total = (wait.inMilliseconds / 1000).ceil();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

/// The countdown line shown above the composer while [cooldown] is active.
String sendCooldownLabel(SendCooldown cooldown, DateTime now) {
  final left = formatCooldown(cooldown.remaining(now));
  return switch (cooldown.kind) {
    SendCooldownKind.slowmode => 'Slow mode: you can send again in $left',
    SendCooldownKind.rateLimited => 'Rate limited — try again in $left',
  };
}

/// The passive hint for a slowmode channel when no cooldown is running.
String slowmodeHint(int slowmodeSeconds) =>
    'Slow mode is on: one message every '
    '${formatCooldown(Duration(seconds: slowmodeSeconds))}';
