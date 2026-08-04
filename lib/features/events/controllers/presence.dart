import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'presence.g.dart';

/// One connection's per-user presence cache, keyed by user ID and scoped to
/// [serverKey] (`userId@baseUrl`) — the same scoping [ReadStateController]
/// uses, and for the same reason: snowflake IDs are minted per server, so a
/// single global map lets two servers' users collide.
///
/// Every connection (active *or* background) seeds this from its gateway READY
/// payload's `presences` array and keeps it current from `presence.update`
/// events — both wired in `accord_event_handler.dart`. Nothing is gated on the
/// connection being the active one: with the cache keyed per server there is
/// nothing for a background connection to clobber, and gating was what left a
/// backgrounded server permanently showing everyone as offline (#191).
///
/// Consumers resolve a member's status by user ID via [accordPresenceStatus];
/// an absent entry means "offline" (the gateway only pushes presence for
/// non-offline users). Read the active connection's map through
/// [activePresencesProvider] rather than picking a key by hand.
@Riverpod(keepAlive: true)
class PresenceController extends _$PresenceController {
  @override
  Map<String, AccordPresence> build(String serverKey) => const {};

  /// Inserts or replaces the presence for [presence.userId].
  void upsert(AccordPresence presence) {
    if (presence.userId.isEmpty) return;
    state = {...state, presence.userId: presence};
  }

  /// Replaces *this server's* presences with [presences] (used to seed from
  /// READY). Replacing rather than merging is deliberate: READY carries every
  /// online user we can see, so anyone absent from it has since gone offline
  /// and their stale entry must not survive a reconnect. Other servers'
  /// caches are separate provider instances and are untouched — a second
  /// connection READYing can no longer wipe the first's presences.
  void seed(Iterable<AccordPresence> presences) {
    state = {
      for (final p in presences)
        if (p.userId.isNotEmpty) p.userId: p,
    };
  }

  /// Merges [presences] into the existing map, leaving untouched users alone.
  /// For partial payloads (a backfill for one space's roster), where absence
  /// carries no "went offline" meaning.
  void merge(Iterable<AccordPresence> presences) {
    if (presences.isEmpty) return;
    state = {
      ...state,
      for (final p in presences)
        if (p.userId.isNotEmpty) p.userId: p,
    };
  }

  void clear() => state = const {};
}

/// The presence map of the connection currently driving the panes, or an empty
/// map when no server is active. Switching servers re-reads the new
/// connection's own (already-seeded, already-live) cache, so presence is
/// correct immediately on a switch with no reconnect.
@Riverpod(keepAlive: true)
Map<String, AccordPresence> activePresences(Ref ref) {
  final key = ref.watch(
    connectionsControllerProvider.select((s) => s.activeKey),
  );
  if (key == null) return const {};
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
/// defaulting to 'offline' when no presence has been received.
String accordPresenceStatus(
  Map<String, AccordPresence> presences,
  String userId,
) => presences[userId]?.status ?? 'offline';

/// The user's custom status text (the first activity's name), or null when
/// none is set. Custom statuses are sent as a presence `activity` whose `name`
/// carries the (optionally emoji-prefixed) text.
String? accordCustomStatus(
  Map<String, AccordPresence> presences,
  String userId,
) {
  final activities = presences[userId]?.activities ?? const [];
  for (final a in activities) {
    if (a.name.trim().isNotEmpty) return a.name.trim();
  }
  return null;
}
