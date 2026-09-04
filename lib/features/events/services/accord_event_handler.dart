import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/events/services/accord_message_events.dart';
import 'package:bonfire/features/events/services/accord_ready_sync.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/forum_posts.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Subscribes a freshly-built [AccordClient]'s gateway streams to Riverpod
/// state. The Accord analogue of `handleEvents` in `event_handler.dart`.
///
/// In the multi-server model every connected server has its own live client and
/// its own [handleAccordEvents] subscription. [serverKey] identifies which
/// connection these events belong to (`userId@baseUrl`), and [isActive] reports
/// whether this connection is the one currently driving the panes.
///
/// Space-list events feed the per-connection cache in `ConnectionsController`
/// for *every* server so the rail can render everyone's spaces at once. The
/// active connection additionally writes the shared `spaces`/`space` controllers
/// and the per-channel/-space pane caches; background connections skip those to
/// avoid clobbering the visible panes (snowflake IDs are per-server and can
/// collide). Returns a disposer that cancels every subscription.
VoidCallback handleAccordEvents(
  Ref ref,
  AccordClient client, {
  required String serverKey,
  required String currentUserId,
  required String selfDomain,
  required bool Function() isActive,
}) {
  final subs = <StreamSubscription<dynamic>>[];

  // ConnectionsController is the authoritative lifecycle store for every
  // server; active consumers select their connection from it.
  void setConnection(ConnectionStatus status) => ref
      .read(connectionsControllerProvider.notifier)
      .setStatus(serverKey, status);

  // ── Connection lifecycle ─────────────────────────────────────────────────
  subs.add(
    client.onConnected.listen((_) {
      setConnection(ConnectionStatus.connected);
    }),
  );
  subs.add(
    client.onReconnecting.listen((_) {
      setConnection(ConnectionStatus.reconnecting);
    }),
  );
  subs.add(
    client.onDisconnected.listen((info) {
      debugPrint('Accord gateway disconnected: ${info.code} ${info.reason}');
      setConnection(ConnectionStatus.disconnected);
    }),
  );

  // ── Initial sync ─────────────────────────────────────────────────────────
  var hadReady = false;
  subs.add(
    client.onReady.listen((data) async {
      setConnection(ConnectionStatus.ready);
      // Hydrate this server's read state from the authoritative unread list the
      // gateway sends in READY. Runs for every connection (active or background)
      // and on every reconnect — this is what persists badges across a cold
      // start and what lights up servers the user hasn't opened yet.
      hydrateReadStateFromReady(ref, data, serverKey: serverKey);
      // Presence is keyed by [serverKey] like read state, so seed it for every
      // connection too — a background server that READYs while you're looking at
      // another one used to be left permanently showing its whole roster as
      // offline, with no re-seed on switch (#191).
      seedPresencesFromReady(
        ref,
        data,
        serverKey: serverKey,
        homeDomain: selfDomain,
      );
      // Blocked accounts drive the message filter that makes "their messages
      // are hidden" true (#290), and READY doesn't carry relationships — so
      // this connection's set is fetched here, for background connections too.
      unawaited(
        ref
            .read(blockedUsersControllerProvider(serverKey).notifier)
            .refresh(client),
      );
      if (isActive()) {
        seedVoiceStatesFromReady(ref, data, serverKey: serverKey);
      }
      await loadSpaces(ref, client, serverKey: serverKey, isActive: isActive);
      // A READY after the first means the gateway re-identified on a fresh
      // session (a resumed session replays missed events instead, and emits
      // `resumed`, not `ready`). Nothing replays what was missed while
      // disconnected, so re-fetch the history of every open message pane.
      // Active server only: the open panes are its channels.
      if (hadReady && isActive()) {
        for (final key in [...activeMessageChannels]) {
          if (key.serverKey != serverKey) continue;
          unawaited(
            ref
                .read(
                  accordMessagesControllerProvider(
                    key.serverKey,
                    key.channelId,
                  ).notifier,
                )
                .reload(client),
          );
        }
        // Open thread views and forum boards are caches of the same kind — they
        // also missed events while disconnected, so refetch them too.
        for (final key in [...activeThreadReplies]) {
          if (key.serverKey != serverKey) continue;
          unawaited(
            ref
                .read(
                  threadRepliesControllerProvider(
                    key.serverKey,
                    key.channelId,
                    key.rootId,
                  ).notifier,
                )
                .reload(client),
          );
        }
        for (final key in [...activeForumChannels]) {
          if (key.serverKey != serverKey) continue;
          unawaited(
            ref
                .read(
                  forumPostsControllerProvider(
                    key.serverKey,
                    key.channelId,
                  ).notifier,
                )
                .reload(client),
          );
        }
      }
      hadReady = true;
    }),
  );

  // ── Presence (every connection) ──────────────────────────────────────────
  // Unlike the caches below, presence is keyed by [serverKey], so a background
  // connection has its own map and can't clobber the visible one. Dropping
  // these while inactive is what made a user who was demonstrably online read
  // as offline after a server switch (#191) — there is no re-request path, the
  // gateway only re-sends presence in READY.
  // The `user_id` on the wire is bare; a member seen through a federated space
  // is qualified. [selfDomain] is what lets the cache key both the same way
  // (#209).
  subs.add(
    client.onPresenceUpdate.listen((presence) {
      ref
          .read(presenceControllerProvider(serverKey).notifier)
          .upsert(presence, homeDomain: selfDomain);
    }),
  );

  // ── Blocked accounts (message filter) ────────────────────────────────────
  // A block made on another device has to reach this one, or the account it
  // silenced keeps appearing here. The relationship events carry no reliable
  // "which user" for a removal, so each one re-reads the authoritative list —
  // they are rare enough that the extra request doesn't matter.
  void refreshBlocked() {
    unawaited(
      ref
          .read(blockedUsersControllerProvider(serverKey).notifier)
          .refresh(client),
    );
  }

  subs.add(client.onRelationshipAdd.listen((_) => refreshBlocked()));
  subs.add(client.onRelationshipUpdate.listen((_) => refreshBlocked()));
  subs.add(client.onRelationshipRemove.listen((_) => refreshBlocked()));

  // ── User cache (profile changes) ─────────────────────────────────────────
  // `user.update` carries a user's new avatar / display name / username, for
  // themselves or anyone we can see. Two caches hold an `AccordUser` and both
  // need it: the per-server user cache (message authors, popouts, and self
  // surfaces) and
  // each open space's member records, which embed their own copy. Mirrors what
  // the profile editor already does after `users.updateMe`.
  //
  // Only `AccordMember.user` is replaced — the per-space `nickname`/`avatar`
  // overrides live on the member itself and keep winning in
  // `accordMemberName`/`accordMemberAvatarUrl`.
  //
  // NOTE: accordserver does not emit `user.update` today, so this is inert
  // until the server broadcasts on `PATCH /users/@me` (#193).
  subs.add(
    client.onUserUpdate.listen((user) {
      if (user.id.isEmpty) return;
      ref
          .read(accordUsersControllerProvider(serverKey).notifier)
          .upsert(user, client: client);
      for (final key in [...activeMemberSpaces]) {
        if (key.serverKey != serverKey) continue;
        ref
            .read(
              accordMembersControllerProvider(
                key.serverKey,
                key.spaceId,
              ).notifier,
            )
            .applyUserUpdate(user);
      }
    }),
  );

  // ── Voice state cache ────────────────────────────────────────────────────
  // Voice-state caches are server scoped because snowflake IDs can collide. A
  // *forced disconnect* on the server our call is pinned to must still be
  // honored while we're browsing another server — voice is one global session,
  // not bound to the active pane.
  subs.add(
    client.onVoiceStateUpdate.listen((vs) {
      final me = currentUserId;
      final voice = ref.read(voiceControllerProvider);
      final isVoiceServer = serverKey == voice.serverKey;

      // A peer joining the DM channel we're ringing means our call connected;
      // drop the "Calling…" state. No-ops unless this matches our outgoing call,
      // so it's safe to run regardless of which server is active.
      if (vs.userId != me && vs.channelId != null) {
        ref.read(callControllerProvider.notifier).markAnswered(vs.channelId!);
      }

      if (isActive()) {
        final cache = ref.read(voiceStatesControllerProvider(serverKey));
        final previousChannel = _channelOf(cache, vs.userId);
        ref.read(voiceStatesControllerProvider(serverKey).notifier).upsert(vs);
        soundManager.playForVoiceState(
          isSelf: vs.userId == me,
          joinedChannel: vs.channelId,
          leftChannel: previousChannel,
          myVoiceChannel: voice.channelId,
        );
        // Our own channel becoming null means the server removed us from voice —
        // tear the session down locally. Only react when the channel we *left* is
        // the one we currently believe we're in; otherwise this is the stale
        // "left old channel" echo from a channel switch, and acting on it would
        // kill the channel we just joined.
        if (vs.userId == me &&
            vs.channelId == null &&
            voice.channelId != null &&
            previousChannel == voice.channelId) {
          ref
              .read(voiceControllerProvider.notifier)
              .handleForcedDisconnect(previousChannel);
        }
        return;
      }

      // Not the active server, so there's no cache to echo-guard against — but the
      // join echoes were already drained while this server was active, so a self
      // null-channel event here is a genuine kick from our pinned voice channel.
      if (isVoiceServer &&
          vs.userId == me &&
          vs.channelId == null &&
          voice.channelId != null) {
        ref
            .read(voiceControllerProvider.notifier)
            .handleForcedDisconnect(voice.channelId);
      }
    }),
  );

  // ── Voice server update ──────────────────────────────────────────────────
  // Fresh LiveKit credentials (token refresh / SFU migration) for the channel
  // we're (re)connecting to. Honored for the active server and for the server
  // our pinned voice session lives on, so a mid-call server switch doesn't drop
  // the reconnect signal.
  subs.add(
    client.onVoiceServerUpdate.listen((info) {
      final isVoiceServer =
          serverKey == ref.read(voiceControllerProvider).serverKey;
      if (!isActive() && !isVoiceServer) return;
      ref.read(voiceControllerProvider.notifier).handleServerUpdate(info);
    }),
  );

  // ── DM call signaling ────────────────────────────────────────────────────
  // The server targets `call.*` events at DM participants directly (not a
  // space), so they arrive on whichever connection owns the DM. Route them into
  // the call controller, which owns ring/accept/decline state for the whole app.
  subs.add(
    client.onCallRing.listen((sig) {
      ref
          .read(callControllerProvider.notifier)
          .handleRing(sig, serverKey, currentUserId);
    }),
  );
  subs.add(
    client.onCallDecline.listen((sig) {
      ref.read(callControllerProvider.notifier).handleDecline(sig);
    }),
  );
  subs.add(
    client.onCallCancel.listen((sig) {
      ref.read(callControllerProvider.notifier).handleCancelOrEnd(sig);
    }),
  );
  subs.add(
    client.onCallEnd.listen((sig) {
      ref.read(callControllerProvider.notifier).handleCancelOrEnd(sig);
    }),
  );

  // ── Space cache ──────────────────────────────────────────────────────────
  // Always feed this connection's rail cache; only the active connection drives
  // the shared space controllers the panes read.
  void cacheSpace(AccordSpace space) {
    ref
        .read(connectionsControllerProvider.notifier)
        .upsertSpace(serverKey, space);
    if (!isActive()) return;
    ref.read(spacesControllerProvider.notifier).upsertSpace(space);
  }

  subs.add(client.onSpaceCreate.listen(cacheSpace));
  subs.add(client.onSpaceUpdate.listen(cacheSpace));
  subs.add(
    client.onSpaceDelete.listen((data) {
      final id = data['id']?.toString() ?? data['space_id']?.toString();
      if (id == null) return;
      ref
          .read(connectionsControllerProvider.notifier)
          .removeSpace(serverKey, id);
      if (isActive()) {
        ref.read(spacesControllerProvider.notifier).removeSpace(id);
      }
    }),
  );

  // ── Channel cache (per space, plus DM/group-DM channels) ─────────────────
  // Space channels feed the per-space channel controller; channels with no
  // space are DMs/group DMs and feed the per-server DM-channel cache so the
  // direct-messages dialog stays in sync (recipient add/remove arrive here as
  // channel.update).
  void cacheChannel(AccordChannel channel) {
    if (!isActive()) return;
    final spaceId = channel.spaceId;
    if (spaceId == null) {
      ref
          .read(dmChannelsControllerProvider(serverKey).notifier)
          .upsert(channel);
    } else {
      ref
          .read(accordChannelsControllerProvider(serverKey, spaceId).notifier)
          .upsertChannel(channel);
    }
    // Keep the open-tab strip's captured label in sync on rename; it renders
    // OpenTab.name, which is otherwise only refreshed when the tab is reopened.
    final name = channel.name;
    if (name != null) {
      ref
          .read(openTabsControllerProvider.notifier)
          .updateName('$serverKey ${channel.id}', name);
    }
  }

  subs.add(client.onChannelCreate.listen(cacheChannel));
  subs.add(client.onChannelUpdate.listen(cacheChannel));
  subs.add(
    client.onChannelDelete.listen((channel) {
      if (!isActive()) return;
      final spaceId = channel.spaceId;
      if (spaceId == null) {
        ref
            .read(dmChannelsControllerProvider(serverKey).notifier)
            .remove(channel.id);
        return;
      }
      ref
          .read(accordChannelsControllerProvider(serverKey, spaceId).notifier)
          .removeChannel(channel.id);
    }),
  );

  // ── Messages, read state, reactions, typing ──────────────────────────────
  bindMessageEvents(
    ref,
    client,
    subs,
    serverKey: serverKey,
    currentUserId: currentUserId,
    selfDomain: selfDomain,
    isActive: isActive,
  );

  // ── Member cache (per space) ─────────────────────────────────────────────
  // Only touch spaces the UI has actually opened (see [activeMemberSpaces]) so
  // a single join event doesn't history-load every space's full member list.
  void cacheMember(AccordMember member) {
    if (!isActive()) return;
    if (!activeMemberSpaces.contains((
      serverKey: serverKey,
      spaceId: member.spaceId,
    ))) {
      return;
    }
    ref
        .read(
          accordMembersControllerProvider(serverKey, member.spaceId).notifier,
        )
        .upsertMember(member);
  }

  // ── Role cache (per space) ───────────────────────────────────────────────
  // Roles live on the AccordSpace; keep its `roles` list current so the roster,
  // name colors, and permission checks reflect server-side changes live.
  String? roleSpaceId(Map<String, dynamic> data) =>
      data['space_id']?.toString() ?? data['guild_id']?.toString();

  void cacheRole(Map<String, dynamic> data) {
    if (!isActive()) return;
    final spaceId = roleSpaceId(data);
    final raw = data['role'];
    if (spaceId == null || raw is! Map) return;
    final role = AccordRole.fromJson(Map<String, dynamic>.from(raw));
    ref.read(spacesControllerProvider.notifier).upsertRole(spaceId, role);
  }

  subs.add(client.onRoleCreate.listen(cacheRole));
  subs.add(client.onRoleUpdate.listen(cacheRole));
  subs.add(
    client.onRoleDelete.listen((data) {
      if (!isActive()) return;
      final spaceId = roleSpaceId(data);
      final roleId =
          data['role_id']?.toString() ??
          (data['role'] is Map
              ? (data['role'] as Map)['id']?.toString()
              : null);
      if (spaceId == null || roleId == null) return;
      ref.read(spacesControllerProvider.notifier).removeRole(spaceId, roleId);
    }),
  );

  subs.add(client.onMemberJoin.listen(cacheMember));
  subs.add(client.onMemberUpdate.listen(cacheMember));
  subs.add(
    client.onMemberLeave.listen((data) {
      if (!isActive()) return;
      final spaceId = roleSpaceId(data);
      final userId =
          data['user_id']?.toString() ??
          (data['user'] is Map
              ? (data['user'] as Map)['id']?.toString()
              : null);
      if (spaceId == null || userId == null) return;
      if (!activeMemberSpaces.contains((
        serverKey: serverKey,
        spaceId: spaceId,
      ))) {
        return;
      }
      ref
          .read(accordMembersControllerProvider(serverKey, spaceId).notifier)
          .removeMember(userId);
    }),
  );

  return () {
    for (final sub in subs) {
      sub.cancel();
    }
  };
}

/// The channel ID [userId] currently appears in within [cache], or null.
String? _channelOf(
  Map<String, Map<String, AccordVoiceState>> cache,
  String userId,
) {
  for (final entry in cache.entries) {
    if (entry.value.containsKey(userId)) return entry.key;
  }
  return null;
}

/// Re-runs the space fetch for a connection on demand — the Retry a pane offers
/// when [spacesLoadFailedProvider] is set. Clears the flag first so the pane
/// drops back to its loading state while the retry is in flight.
///
/// Exposed as a provider rather than a plain function because [loadSpaces]
/// needs a provider `Ref`, and the panes that offer the retry only hold a
/// `WidgetRef`.
final retryLoadSpacesProvider =
    Provider<Future<void> Function(AccordClient, String)>((ref) {
  return (client, serverKey) {
    ref.read(spacesLoadFailedProvider(serverKey).notifier).set(false);
    return loadSpaces(
      ref,
      client,
      serverKey: serverKey,
      isActive: () =>
          ref.read(connectionsControllerProvider).activeKey == serverKey,
    );
  };
});
