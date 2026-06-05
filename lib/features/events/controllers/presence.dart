import 'package:accordkit/accordkit.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'presence.g.dart';

/// Global per-user presence cache, keyed by user ID. Mirrors the reference
/// client's global `_user_cache[...]["status"]` rather than a per-space store:
/// a user has one presence regardless of how many spaces they share with us.
///
/// Seeded from the gateway READY payload's `presences` array and kept in sync
/// by `presence.update` events (both wired in `accord_event_handler.dart`).
/// Consumers resolve a member's status by user ID; an absent entry means
/// "offline" (the gateway only pushes presence for non-offline users).
@Riverpod(keepAlive: true)
class PresenceController extends _$PresenceController {
  @override
  Map<String, AccordPresence> build() => const {};

  /// Inserts or replaces the presence for [presence.userId].
  void upsert(AccordPresence presence) {
    if (presence.userId.isEmpty) return;
    state = {...state, presence.userId: presence};
  }

  /// Replaces the whole cache with [presences] (used to seed from READY).
  void seed(Iterable<AccordPresence> presences) {
    state = {
      for (final p in presences)
        if (p.userId.isNotEmpty) p.userId: p,
    };
  }
}

/// The status string ('online' / 'idle' / 'dnd' / 'offline') for [userId],
/// defaulting to 'offline' when no presence has been received.
String accordPresenceStatus(Map<String, AccordPresence> presences, String userId) =>
    presences[userId]?.status ?? 'offline';
