import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'presence.g.dart';

/// One connection's presence cache, keyed by **qualified** user ID.
///
/// `presence.update` carries a bare `user_id` while federated members are
/// qualified, so both are keyed through [qualify] with the connection's
/// [homeDomain] ([isSameUser] semantics as a map key). A bare [localPart] key
/// would let a remote `123@b.example` collide with a local `123`.
@immutable
class PresenceMap {
  const PresenceMap({
    this.byUser = const {},
    this.homeDomain = '',
    this.revisions = const {},
  });

  /// Per-user write revisions include offline updates held behind grace.
  final Map<String, int> revisions;

  /// Presences by qualified user ID (or by raw ID while [homeDomain] is still
  /// unknown — [withDomain] re-keys them as soon as it is).
  final Map<String, AccordPresence> byUser;

  /// The connection's home domain (`a.example`), empty until the first write
  /// supplies it.
  final String homeDomain;

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
      revisions: {
        for (final e in revisions.entries) qualify(e.key, domain): e.value,
      },
    );
  }
}

class _PendingOffline {
  _PendingOffline(this.key);
  String key;
  late Timer timer;
}

/// Per-connection presence cache seeded from READY and `presence.update` for
/// every connection; offline transitions wait [offlineGrace] so reconnect blips
/// don't reshuffle the roster, and an absent entry means offline. Read the
/// active connection's map through [activePresencesProvider].
@Riverpod(keepAlive: true)
class PresenceController extends _$PresenceController {
  /// How long an offline transition is held before it is rendered. Long enough
  /// to swallow a reconnect blip, short enough that a real sign-off still feels
  /// immediate.
  @visibleForTesting
  static Duration offlineGrace = const Duration(seconds: 8);

  /// Offline transitions waiting out [offlineGrace], by cache key.
  final _pendingOffline = <String, _PendingOffline>{};

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
    var map = _rekeyed(homeDomain);
    final key = map.keyFor(presence.userId);
    map = PresenceMap(
      byUser: map.byUser,
      homeDomain: map.homeDomain,
      revisions: {...map.revisions, key: (map.revisions[key] ?? 0) + 1},
    );

    // Coming online is never delayed, and it cancels a pending offline — a
    // drop-and-reconnect inside the window renders as no change at all.
    if (presence.status == 'invisible' ||
        accordIsVisibleStatus(presence.status)) {
      _pendingOffline.remove(key)?.timer.cancel();
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

  /// Merges a scoped REST snapshot, preserving gateway writes made since the
  /// request started and entries belonging to other spaces on this connection.
  void mergeSnapshot(
    Iterable<AccordPresence> presences, {
    required PresenceMap baseline,
    String? homeDomain,
  }) {
    final domain = homeDomain ?? state.homeDomain;
    final before = baseline.withDomain(domain);
    state = _rekeyed(domain);
    for (final presence in presences) {
      if (presence.userId.isEmpty) continue;
      if (state.revisions[state.keyFor(presence.userId)] !=
          before.revisions[before.keyFor(presence.userId)]) {
        continue;
      }
      upsert(presence);
    }
  }

  /// Replaces this server's presences with READY's [presences]: READY carries
  /// every online user we can see, so anyone absent has gone offline. Those
  /// implied transitions wait out [offlineGrace] too, since a re-seed is almost
  /// always our own reconnect.
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
      _pendingOffline.remove(key)?.timer.cancel();
    }
    next.addAll(seeded);
    state = PresenceMap(
      byUser: next,
      homeDomain: map.homeDomain,
      revisions: {
        for (final key in {...map.byUser.keys, ...seeded.keys})
          key: (map.revisions[key] ?? 0) + 1,
      },
    );
  }

  /// Renders the offline transition for [key] once [offlineGrace] elapses:
  /// [offline] is the presence to store, or null to drop the entry entirely
  /// (how a seed says "absent from READY"). An already-pending hold wins, so a
  /// repeated offline can't keep pushing the transition further out.
  void _holdOffline(String key, AccordPresence? offline) {
    if (_pendingOffline.containsKey(key)) return;
    final hold = _PendingOffline(key);
    _pendingOffline[key] = hold;
    hold.timer = Timer(offlineGrace, () {
      final key = hold.key;
      _pendingOffline.remove(key);
      final next = {...state.byUser};
      if (offline == null) {
        next.remove(key);
      } else {
        next[key] = offline;
      }
      state = PresenceMap(
        byUser: next,
        homeDomain: state.homeDomain,
        revisions: {...state.revisions, key: (state.revisions[key] ?? 0) + 1},
      );
    });
  }

  /// The current map re-keyed for [homeDomain] when it differs. A null or empty
  /// domain means the caller doesn't know ours (the self status picker, the AFK
  /// monitor) and leaves the keys alone. Pending transitions move to the new
  /// keys without restarting their grace deadline.
  PresenceMap _rekeyed(String? homeDomain) {
    final map = state;
    if (homeDomain == null ||
        homeDomain.isEmpty ||
        homeDomain == map.homeDomain) {
      return map;
    }
    final next = map.withDomain(homeDomain);
    final holds = _pendingOffline.values.toList();
    _pendingOffline.clear();
    for (final hold in holds) {
      hold.key = next.keyFor(hold.key);
      _pendingOffline[hold.key] = hold;
    }
    return next;
  }

  PresenceMap _with(PresenceMap map, String key, AccordPresence presence) =>
      PresenceMap(
        byUser: {...map.byUser, key: presence},
        homeDomain: map.homeDomain,
        revisions: map.revisions,
      );

  void _cancelPending() {
    for (final hold in _pendingOffline.values) {
      hold.timer.cancel();
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

/// Visibility shared by roster grouping, dimming, and live counts.
bool accordIsVisibleStatus(String status) =>
    status == 'online' || status == 'idle' || status == 'dnd';
