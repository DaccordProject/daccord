import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/utils/space_cache.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Seeds the voice-state cache from the gateway READY payload's `voice_states`
/// array (matches the reference client's `_apply_voice_states`). The payload is
/// flat — entries carry their own `channel_id` — so we bucket by channel.
void seedVoiceStatesFromReady(
  Ref ref,
  Map<String, dynamic> ready, {
  required String serverKey,
}) {
  final raw = ready['voice_states'];
  if (raw is! List) return;
  final byChannel = <String, List<AccordVoiceState>>{};
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;
    final vs = AccordVoiceState.fromJson(entry);
    final channelId = vs.channelId;
    if (channelId == null || channelId.isEmpty) continue;
    (byChannel[channelId] ??= []).add(vs);
  }
  final notifier = ref.read(voiceStatesControllerProvider(serverKey).notifier);
  for (final entry in byChannel.entries) {
    notifier.seedChannel(entry.key, entry.value);
  }
}

/// Seeds a server's read state from the gateway READY payload's `unread`
/// array. Each entry carries `channel_id`, `mention_count` and (so the rail can
/// roll a server-level badge up) `space_id`; when the server omits `space_id`
/// we recover it from the READY `channels` array. This is the durable source of
/// truth that survives restarts — the live message handler only adds deltas.
/// Unfiltered by mutes for the same reason [markUnread] is: the indicators
/// apply [UnreadIndicatorGate] at render time, so a reconnect can't resurrect a
/// muted space's dot and unmuting doesn't need one.
void hydrateReadStateFromReady(
  Ref ref,
  Map<String, dynamic> ready, {
  required String serverKey,
}) {
  final raw = ready['unread'];
  if (raw is! List) return;

  // channel_id → space_id fallback, in case `unread` entries omit space_id.
  final channelSpace = <String, String>{};
  final channels = ready['channels'];
  if (channels is List) {
    for (final c in channels) {
      if (c is! Map) continue;
      final id = (c['id'] ?? c['channel_id'])?.toString();
      final space = (c['space_id'] ?? c['guild_id'])?.toString();
      if (id != null && id.isNotEmpty && space != null && space.isNotEmpty) {
        channelSpace[id] = space;
      }
    }
  }

  final entries = <ReadEntry>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final channelId = e['channel_id']?.toString();
    if (channelId == null || channelId.isEmpty) continue;
    final spaceId = (e['space_id'] ?? channelSpace[channelId])?.toString();
    final mentions = (e['mention_count'] as num?)?.toInt() ?? 0;
    entries.add(
      ReadEntry(
        channelId: channelId,
        spaceId: (spaceId != null && spaceId.isNotEmpty) ? spaceId : null,
        mentions: mentions,
      ),
    );
  }
  ref.read(readStateControllerProvider(serverKey).notifier).hydrate(entries);
}

/// Seeds a connection's presence cache from the gateway READY payload's
/// `presences` array (matches the reference client's `_apply_presences`).
///
/// Runs for every connection, keyed by [serverKey], so two servers READYing in
/// sequence no longer overwrite each other. An *empty* `presences` array is a
/// real answer ("nobody visible is online") and clears the server's map; a
/// missing/malformed field leaves the previous seed alone.
void seedPresencesFromReady(
  Ref ref,
  Map<String, dynamic> ready, {
  required String serverKey,
  String homeDomain = '',
}) {
  final raw = ready['presences'];
  if (raw is! List) return;
  final presences = [
    for (final entry in raw)
      if (entry is Map<String, dynamic>) AccordPresence.fromJson(entry),
  ];
  ref
      .read(presenceControllerProvider(serverKey).notifier)
      .seed(presences, homeDomain: homeDomain);
}

/// Fetches the connection's spaces over REST and seeds its rail cache. The
/// active connection also seeds the shared rail + per-space controllers.
///
/// A failure sets [spacesLoadFailedProvider] for this connection: without it
/// the space list stays `null`, which every pane downstream reads as "still
/// loading" and renders as a spinner that never resolves.
Future<void> loadSpaces(
  Ref ref,
  AccordClient client, {
  required String serverKey,
  required bool Function() isActive,
}) async {
  final result = await client.users.listSpaces();
  final spaces = result.listOrLog<AccordSpace>('spaces');
  if (spaces == null) {
    ref.read(spacesLoadFailedProvider(serverKey).notifier).set(true);
    return;
  }

  // `GET /users/@me/spaces` returns summary spaces without their role list, so
  // hydrate roles via the dedicated endpoint before seeding any cache — the
  // reference client does the same on every (re)connect (`_refetch_data` →
  // `fetch_roles`). Without this `AccordSpace.roles` stays empty and the roster
  // grouping, name colors, role chips, and role-based permission grants all
  // silently no-op. Done for background connections too so their snapshot is
  // complete the moment they become active.
  await _hydrateRoles(client, spaces);
  ref
      .read(connectionsControllerProvider.notifier)
      .setSpaces(serverKey, spaces, authoritative: true);
  // Persist the freshly-loaded list so the rail can show this server's spaces
  // (dimmed) on the next launch even if the server is then unreachable.
  unawaited(SpaceCache.save(serverKey, spaces));
  ref.read(spacesLoadFailedProvider(serverKey).notifier).set(false);
  if (!isActive()) return;
  ref.read(spacesControllerProvider.notifier).setSpaces(spaces);
}

/// Fetches each space's roles over REST (`GET /spaces/{id}/roles`) and populates
/// the space's `roles` list in place. Role lists are small, so fetching all
/// spaces concurrently on (re)connect is cheap. A failed fetch for one space
/// leaves it with no roles rather than aborting the others — the gateway
/// `role.*` events still keep it current once something changes.
Future<void> _hydrateRoles(
  AccordClient client,
  List<AccordSpace> spaces,
) async {
  const maxConcurrentFetches = 8;
  final pending = List<AccordSpace>.of(spaces);

  Future<void> worker() async {
    while (pending.isNotEmpty) {
      final space = pending.removeLast();
      final result = await client.roles.list(space.id);
      final roles = result.listOrLog<AccordRole>('roles for ${space.id}');
      if (roles == null) continue;
      space.roles
        ..clear()
        ..addAll(roles);
    }
  }

  final workerCount = spaces.length < maxConcurrentFetches
      ? spaces.length
      : maxConcurrentFetches;
  await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
}
