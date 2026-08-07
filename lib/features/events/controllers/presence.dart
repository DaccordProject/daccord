import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'presence.g.dart';

/// One connection's presence cache, keyed by **qualified** user ID.
///
/// The gateway broadcasts `presence.update` with a bare `user_id`, while a
/// member seen through a federated space carries a qualified `id@domain` — so
/// an exact-key lookup never matched and those members read permanently offline
/// (#209). Both sides are normalised through [qualify] here instead: bare IDs
/// are suffixed with the connection's [homeDomain], already-qualified IDs are
/// left alone. That is [isSameUser] semantics expressed as a map key, and it
/// keeps a remote `123@b.example` from colliding with a local `123` — which a
/// bare [localPart] fallback would not, since snowflakes are only unique per
/// home server.
@immutable
class PresenceMap {
  const PresenceMap({this.byUser = const {}, this.homeDomain = ''});

  /// Presences by qualified user ID (or by raw ID while [homeDomain] is still
  /// unknown — [withDomain] re-keys them as soon as it is).
  final Map<String, AccordPresence> byUser;

  /// The connection's home domain (`a.example`), empty until the first write
  /// supplies it.
  final String homeDomain;

  bool get isEmpty => byUser.isEmpty;
  bool get isNotEmpty => byUser.isNotEmpty;
  int get length => byUser.length;

  /// The cache key for [userId]. [qualify] is idempotent, so passing an
  /// already-qualified ID is a no-op.
  String keyFor(String userId) =>
      homeDomain.isEmpty ? userId : qualify(userId, homeDomain);

  /// The presence for [userId], given bare or qualified, or null when none has
  /// been received.
  AccordPresence? operator [](String userId) => byUser[keyFor(userId)];

  /// This map re-keyed for [domain]. Returns `this` when nothing changes; an
  /// empty [domain] means "not known yet" and never un-qualifies keys.
  PresenceMap withDomain(String domain) {
    if (domain.isEmpty || domain == homeDomain) return this;
    return PresenceMap(
      byUser: {
        for (final entry in byUser.entries)
          qualify(entry.key, domain): entry.value,
      },
      homeDomain: domain,
    );
  }
}

/// One connection's per-user presence cache, scoped to [serverKey]
/// (`userId@baseUrl`) — the same scoping [ReadStateController] uses, and for the
/// same reason: snowflake IDs are minted per server, so a single global map lets
/// two servers' users collide.
///
/// Every connection (active *or* background) seeds this from its gateway READY
/// payload's `presences` array and keeps it current from `presence.update`
/// events — both wired in `accord_event_handler.dart`. Nothing is gated on the
/// connection being the active one: with the cache keyed per server there is
/// nothing for a background connection to clobber, and gating was what left a
/// backgrounded server permanently showing everyone as offline (#191).
///
/// Offline transitions are held for [offlineGrace] before they reach the state
/// (#210). Presence is purely socket-lifetime driven server-side — one socket
/// drop on a peer's client is one visible offline/online flip for everyone — so
/// without smoothing a momentary blip re-buckets that member into the roster's
/// "Offline" section and back, and rows visibly jump. Going *non*-offline is
/// never delayed, and a pending offline is cancelled the moment the user comes
/// back, so a blip shorter than the window is never rendered at all.
///
/// Consumers resolve a member's status by user ID via [accordPresenceStatus];
/// an absent entry means "offline" (the gateway only pushes presence for
/// non-offline users). Read the active connection's map through
/// [activePresencesProvider] rather than picking a key by hand.
@Riverpod(keepAlive: true)
class PresenceController extends _$PresenceController {
  /// How long an offline transition is held before it is rendered. Long enough
  /// to swallow a reconnect blip, short enough that a real sign-off still feels
  /// immediate.
  @visibleForTesting
  static Duration offlineGrace = const Duration(seconds: 8);

  /// Offline transitions waiting out [offlineGrace], by cache key.
  final _pendingOffline = <String, Timer>{};

  @override
  PresenceMap build(String serverKey) {
    ref.onDispose(_cancelPending);
    return const PresenceMap();
  }

  /// Inserts or replaces the presence for `presence.userId`, holding an
  /// offline transition for [offlineGrace].
  ///
  /// [homeDomain] is the connection's own domain, used to qualify bare IDs; it
  /// defaults to the one the map already holds, so callers with no domain in
  /// hand (the self status picker, the AFK monitor) don't need one.
  void upsert(AccordPresence presence, {String? homeDomain}) {
    if (presence.userId.isEmpty) return;
    final map = _rekeyed(homeDomain);
    final key = map.keyFor(presence.userId);

    // Coming online is never delayed, and it cancels a pending offline — a
    // drop-and-reconnect inside the window renders as no change at all.
    if (presence.status != 'offline') {
      _pendingOffline.remove(key)?.cancel();
      state = _with(map, key, presence);
      return;
    }
    // Nothing visible changes when they already read as offline, so there is
    // nothing to smooth — apply it so activities stay current.
    final existing = map.byUser[key];
    if (existing == null || existing.status == 'offline') {
      state = _with(map, key, presence);
      return;
    }
    state = map;
    _holdOffline(key, presence);
  }

  /// Replaces *this server's* presences with [presences] (used to seed from
  /// READY). Replacing rather than merging is deliberate: READY carries every
  /// online user we can see, so anyone absent from it has since gone offline.
  /// Other servers' caches are separate provider instances and are untouched —
  /// a second connection READYing can no longer wipe the first's presences.
  ///
  /// Those implied offline transitions go through the same [offlineGrace] hold
  /// as an explicit one. A re-seed is almost always *our own* reconnect, and
  /// dropping every absent user on the spot blanked the whole roster for as
  /// long as the handshake took (#210).
  void seed(Iterable<AccordPresence> presences, {String? homeDomain}) {
    final map = _rekeyed(homeDomain);
    final seeded = <String, AccordPresence>{
      for (final p in presences)
        if (p.userId.isNotEmpty) map.keyFor(p.userId): p,
    };

    final next = <String, AccordPresence>{};
    for (final entry in map.byUser.entries) {
      if (seeded.containsKey(entry.key)) continue;
      if (entry.value.status == 'offline') continue;
      next[entry.key] = entry.value;
      _holdOffline(entry.key, null);
    }
    for (final key in seeded.keys) {
      _pendingOffline.remove(key)?.cancel();
    }
    next.addAll(seeded);
    state = PresenceMap(byUser: next, homeDomain: map.homeDomain);
  }

  void clear() {
    _cancelPending();
    state = PresenceMap(homeDomain: state.homeDomain);
  }

  /// Renders the offline transition for [key] once [offlineGrace] elapses:
  /// [offline] is the presence to store, or null to drop the entry entirely
  /// (how a seed says "absent from READY"). An already-pending hold wins, so a
  /// repeated offline can't keep pushing the transition further out.
  void _holdOffline(String key, AccordPresence? offline) {
    if (_pendingOffline.containsKey(key)) return;
    _pendingOffline[key] = Timer(offlineGrace, () {
      _pendingOffline.remove(key);
      final next = {...state.byUser};
      if (offline == null) {
        next.remove(key);
      } else {
        next[key] = offline;
      }
      state = PresenceMap(byUser: next, homeDomain: state.homeDomain);
    });
  }

  /// The current map re-keyed for [homeDomain] when it differs. A null or empty
  /// domain means the caller doesn't know ours (the self status picker, the AFK
  /// monitor) and leaves the keys alone. Pending holds are keyed by the old form
  /// and can't survive a re-key, so they're dropped — in practice this only
  /// fires on the first write, before any hold exists.
  PresenceMap _rekeyed(String? homeDomain) {
    final map = state;
    if (homeDomain == null ||
        homeDomain.isEmpty ||
        homeDomain == map.homeDomain) {
      return map;
    }
    _cancelPending();
    return map.withDomain(homeDomain);
  }

  PresenceMap _with(PresenceMap map, String key, AccordPresence presence) =>
      PresenceMap(
        byUser: {...map.byUser, key: presence},
        homeDomain: map.homeDomain,
      );

  void _cancelPending() {
    for (final timer in _pendingOffline.values) {
      timer.cancel();
    }
    _pendingOffline.clear();
  }
}

/// The presence map of the connection currently driving the panes, or an empty
/// map when no server is active. Switching servers re-reads the new
/// connection's own (already-seeded, already-live) cache, so presence is
/// correct immediately on a switch with no reconnect.
@Riverpod(keepAlive: true)
PresenceMap activePresences(Ref ref) {
  final key = ref.watch(
    connectionsControllerProvider.select((s) => s.activeKey),
  );
  if (key == null) return const PresenceMap();
  return ref.watch(presenceControllerProvider(key));
}

/// The active connection's presence notifier, or null when nothing is active.
/// For optimistic local writes (the self status picker); gateway writes go
/// through the per-connection provider directly.
PresenceController? activePresenceNotifier(WidgetRef ref) {
  final key = ref.read(connectionsControllerProvider).activeKey;
  if (key == null) return null;
  return ref.read(presenceControllerProvider(key).notifier);
}

/// The status string ('online' / 'idle' / 'dnd' / 'offline') for [userId],
/// defaulting to 'offline' when no presence has been received. [userId] may be
/// bare or qualified — see [PresenceMap].
String accordPresenceStatus(PresenceMap presences, String userId) =>
    presences[userId]?.status ?? 'offline';

/// The user's custom status text (the first activity's name), or null when
/// none is set. Custom statuses are sent as a presence `activity` whose `name`
/// carries the (optionally emoji-prefixed) text.
String? accordCustomStatus(PresenceMap presences, String userId) {
  final activities = presences[userId]?.activities ?? const [];
  for (final a in activities) {
    if (a.name.trim().isNotEmpty) return a.name.trim();
  }
  return null;
}
