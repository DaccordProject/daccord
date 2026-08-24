import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/forum_posts.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/notifications/services/notification.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/notifications/utils/notification_gate.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/utils/space_cache.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
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

  // Federation echoes the local user's own actions back qualified to our home
  // domain (`<id>@<selfDomain>`), so a bare `== currentUserId` no longer
  // recognises them. These treat both forms as self — see [isSameUser] — and
  // are used wherever an event would otherwise self-notify, self-chime, or
  // double-count (message author, mentions, reaction ownership, typing).
  bool isSelf(String? id) =>
      id != null && isSameUser(id, currentUserId, localDomain: selfDomain);
  bool mentionsSelf(Iterable<String> mentions) => mentions.any(isSelf);

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
      _hydrateReadState(ref, data, serverKey: serverKey);
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
      if (isActive()) {
        _seedVoiceStates(ref, data, serverKey: serverKey);
      }
      await _loadSpaces(ref, client, serverKey: serverKey, isActive: isActive);
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

  // ── Incoming messages ────────────────────────────────────────────────────
  // One `message.create` subscription fans out to four independent concerns —
  // channel cache, read-state badge, mention notification, SFX — run in that
  // order (the order the standalone subscriptions used to fire in). Shared
  // reads (self-authorship, self-mention, settings, active/visible checks) are
  // computed once; each concern keeps its own skip conditions, so a guard that
  // silences the chime never suppresses the badge, and vice versa.
  subs.add(
    client.onMessageCreate.listen((message) {
      final active = isActive();
      final isOwn = isSelf(message.authorId);
      final mentionsMe = mentionsSelf(message.mentions);
      final isVisibleChannel =
          active &&
          accordVisibleChannel ==
              (serverKey: serverKey, channelId: message.channelId);
      final settings = ref.read(settingsControllerProvider);
      final countsAsMention = MessageNotificationGate.countsAsMention(
        mentionsMe: mentionsMe,
        mentionEveryone: message.mentionEveryone,
        suppressEveryone: settings.suppressEveryone,
      );
      final spaceMuted =
          message.spaceId != null &&
          settings.isSpaceMuted(serverKey, message.spaceId!);

      // Channel cache: only touch channels the UI has actually opened (see
      // [activeMessageChannels]) so we don't history-load every channel that
      // receives a message. Active connection only — its channels own the panes.
      if (active &&
          activeMessageChannels.contains((
            serverKey: serverKey,
            channelId: message.channelId,
          ))) {
        ref
            .read(
              accordMessagesControllerProvider(
                serverKey,
                message.channelId,
              ).notifier,
            )
            .addMessage(message);
      }
      if (message.spaceId == null) {
        ref
            .read(dmChannelsControllerProvider(serverKey).notifier)
            .applyMessage(message);
      }

      // Thread views: a message carrying `thread_id` is a reply — route it into
      // the matching open thread's replies cache (the composer's optimistic
      // append is deduped by `addReply`). Same opened-only rule as above, via
      // [activeThreadReplies].
      final threadId = message.threadId;
      if (active &&
          threadId != null &&
          activeThreadReplies.contains((
            serverKey: serverKey,
            channelId: message.channelId,
            rootId: threadId,
          ))) {
        ref
            .read(
              threadRepliesControllerProvider(
                serverKey,
                message.channelId,
                threadId,
              ).notifier,
            )
            .addReply(message);
      }

      // Forum boards: a top-level (no `thread_id`) message in a channel with a
      // live forum controller is a new root post — surface it on the board live.
      // Only forum channels ever build that controller, so membership in
      // [activeForumChannels] is also the cheap "is this a forum?" test.
      if (active &&
          threadId == null &&
          activeForumChannels.contains((
            serverKey: serverKey,
            channelId: message.channelId,
          ))) {
        ref
            .read(
              forumPostsControllerProvider(
                serverKey,
                message.channelId,
              ).notifier,
            )
            .addPost(message);
      }

      // Read state (unread + mention badges): independent of the channel cache —
      // every message that arrives in a channel other than the visible one marks
      // that channel unread (with a bumped mention count when the user is
      // mentioned). Runs for *every* connection so background servers light up
      // their rail icon too — state is keyed by [serverKey] so colliding
      // snowflakes don't cross-contaminate. Only the active connection
      // suppresses the on-screen channel (the visible-channel pointer belongs to
      // the active session). Mirrors `client_unread.gd`.
      //
      // Intentionally *not* filtered by mutes: the stored state stays truthful
      // and the rail/channel indicators apply [UnreadIndicatorGate] when they
      // render (see `ReadStateSnapshot.spaceShowsUnread`), so unmuting a space
      // reveals what arrived while it was muted without waiting for a reconnect.
      if (!isOwn && !isVisibleChannel) {
        ref
            .read(readStateControllerProvider(serverKey).notifier)
            .markUnread(
              message.channelId,
              spaceId: message.spaceId,
              isMention: countsAsMention,
            );
      }

      // Mention notifications: fire for *any* mentioning message, even in
      // channels the UI hasn't opened and on servers that aren't currently
      // active (so a message on server B still notifies while you're on server
      // A). [currentUserId] is per-connection, so author matching is correct on
      // every server; only the *visible-channel* skip is active-connection
      // -scoped, since that pointer belongs to the on-screen session.
      final notify = MessageNotificationGate.shouldNotify(
        notificationsEnabled: settings.notificationsEnabled,
        suppressEveryone: settings.suppressEveryone,
        isOwnMessage: isOwn,
        isVisibleChannel: isVisibleChannel,
        mentionsMe: mentionsMe,
        mentionEveryone: message.mentionEveryone,
        spaceMuted: spaceMuted,
        channelLevel: settings.channelNotificationLevel(
          serverKey,
          message.channelId,
        ),
      );
      if (notify) {
        final author = ref
            .read(accordUsersControllerProvider(serverKey).notifier)
            .cached(message.authorId, client: client);
        final name = accordUserName(author, fallback: 'New mention');
        final body = message.content.trim();
        showMentionNotification(
          title: name,
          body: body.isEmpty ? 'mentioned you' : body,
        );
      }

      // Message SFX (mirrors the reference `play_for_message`): plays for *any*
      // incoming message on *any* connection, gated by sound prefs + window
      // focus, and never chimes for our own messages, a muted space (which stays
      // silent like its suppressed banner), or the channel that's on screen
      // (only the active connection owns the visible-channel pointer).
      if (settings.soundsEnabled && !spaceMuted && !isOwn) {
        soundManager.playForMessage(
          isMention: countsAsMention,
          isVisibleChannel: isVisibleChannel,
          isMemberJoin: message.type == 'member_join',
        );
      }
    }),
  );

  // ── Message cache (per channel) ──────────────────────────────────────────
  // Edits and deletes follow the same opened-channels rule as the cache block
  // above.
  subs.add(
    client.onMessageUpdate.listen((message) {
      if (message.spaceId == null) {
        ref
            .read(dmChannelsControllerProvider(serverKey).notifier)
            .updateMessagePreview(message);
      }
      if (!isActive()) return;
      if (activeMessageChannels.contains((
        serverKey: serverKey,
        channelId: message.channelId,
      ))) {
        ref
            .read(
              accordMessagesControllerProvider(
                serverKey,
                message.channelId,
              ).notifier,
            )
            .updateMessage(message);
      }
      // Route edits into open thread views (replies) and forum boards (root
      // posts) the same way creates are routed; both mutators no-op on ids they
      // don't hold.
      final threadId = message.threadId;
      if (threadId != null &&
          activeThreadReplies.contains((
            serverKey: serverKey,
            channelId: message.channelId,
            rootId: threadId,
          ))) {
        ref
            .read(
              threadRepliesControllerProvider(
                serverKey,
                message.channelId,
                threadId,
              ).notifier,
            )
            .updateReply(message);
      }
      if (threadId == null &&
          activeForumChannels.contains((
            serverKey: serverKey,
            channelId: message.channelId,
          ))) {
        ref
            .read(
              forumPostsControllerProvider(
                serverKey,
                message.channelId,
              ).notifier,
            )
            .updatePost(message);
      }
    }),
  );
  subs.add(
    client.onMessageDelete.listen((data) {
      final channelId = data['channel_id']?.toString();
      final messageId =
          data['id']?.toString() ?? data['message_id']?.toString();
      if (channelId == null || messageId == null) return;
      final dmChannels = ref.read(
        dmChannelsControllerProvider(serverKey).notifier,
      );
      if (dmChannels.contains(channelId)) {
        dmChannels.removeMessagePreview(channelId, messageId);
      }
      if (!isActive()) return;
      if (activeMessageChannels.contains((
        serverKey: serverKey,
        channelId: channelId,
      ))) {
        ref
            .read(
              accordMessagesControllerProvider(serverKey, channelId).notifier,
            )
            .removeMessage(messageId);
      }
      // The delete payload carries no `thread_id`, so fan the removal out to
      // every open thread on this channel (usually at most one) and to an open
      // forum board; removeReply/removePost no-op when the id isn't theirs.
      for (final key in [...activeThreadReplies]) {
        if (key.serverKey != serverKey || key.channelId != channelId) continue;
        ref
            .read(
              threadRepliesControllerProvider(
                key.serverKey,
                key.channelId,
                key.rootId,
              ).notifier,
            )
            .removeReply(messageId);
      }
      if (activeForumChannels.contains((
        serverKey: serverKey,
        channelId: channelId,
      ))) {
        ref
            .read(forumPostsControllerProvider(serverKey, channelId).notifier)
            .removePost(messageId);
      }
    }),
  );

  // ── Read-state sync (multi-device) ───────────────────────────────────────
  // The server echoes our own acks to our *other* sessions, so reading a channel
  // on one device clears its badge here too. Keyed by [serverKey] like the rest
  // of read state; we only clear (acks never re-raise a badge).
  subs.add(
    client.onReadStateUpdate.listen((data) {
      final channelId = data['channel_id']?.toString();
      if (channelId == null || channelId.isEmpty) return;
      ref
          .read(readStateControllerProvider(serverKey).notifier)
          .markRead(channelId);
    }),
  );

  // ── Reactions (per channel) ──────────────────────────────────────────────
  // Like messages, only mutate channels the UI has opened.
  // The gateway echoes a reaction's emoji either as a map (`{name, id}`) or as
  // a bare token — `name:id` for custom emoji, a glyph/shortcode otherwise. We
  // split the token so the id survives; otherwise a custom reaction would be
  // stored with id=null and a name of `name:id`, rendering as literal text and
  // never matching the optimistic pill (leaving two pills for one reaction).
  EmojiRef reactionEmoji(Map<String, dynamic> data) {
    final raw = data['emoji'];
    if (raw is Map) {
      return (name: raw['name']?.toString() ?? '', id: raw['id']?.toString());
    }
    if (raw is String) return parseEmojiToken(raw);
    return (name: '', id: null);
  }

  void applyReactionEvent(Map<String, dynamic> data, {required bool added}) {
    if (!isActive()) return;
    final channelId = data['channel_id']?.toString();
    final messageId = data['message_id']?.toString();
    final emoji = reactionEmoji(data);
    if (channelId == null || messageId == null || emoji.name.isEmpty) return;
    if (!activeMessageChannels.contains((
      serverKey: serverKey,
      channelId: channelId,
    ))) {
      return;
    }
    // A federated reaction carries a qualified actor id; our own reaction on a
    // remote-homed message echoes back qualified to our domain, so match both
    // forms or the optimistic pill and its echo double-count.
    final isOwn = isSelf(data['user_id']?.toString());
    ref
        .read(accordMessagesControllerProvider(serverKey, channelId).notifier)
        .applyReaction(
          messageId,
          emoji.name,
          added: added,
          isOwn: isOwn,
          emojiId: emoji.id,
        );
  }

  subs.add(
    client.onReactionAdd.listen((d) => applyReactionEvent(d, added: true)),
  );
  subs.add(
    client.onReactionRemove.listen((d) => applyReactionEvent(d, added: false)),
  );
  subs.add(
    client.onReactionClear.listen((data) {
      if (!isActive()) return;
      final channelId = data['channel_id']?.toString();
      final messageId = data['message_id']?.toString();
      if (channelId == null || messageId == null) return;
      if (!activeMessageChannels.contains((
        serverKey: serverKey,
        channelId: channelId,
      ))) {
        return;
      }
      ref
          .read(accordMessagesControllerProvider(serverKey, channelId).notifier)
          .clearReactions(messageId);
    }),
  );
  subs.add(
    client.onReactionClearEmoji.listen((data) {
      if (!isActive()) return;
      final channelId = data['channel_id']?.toString();
      final messageId = data['message_id']?.toString();
      final name = reactionEmoji(data).name;
      if (channelId == null || messageId == null || name.isEmpty) return;
      if (!activeMessageChannels.contains((
        serverKey: serverKey,
        channelId: channelId,
      ))) {
        return;
      }
      ref
          .read(accordMessagesControllerProvider(serverKey, channelId).notifier)
          .clearReactionEmoji(messageId, name);
    }),
  );

  // ── Typing indicators (per channel) ──────────────────────────────────────
  // A remote user's typing arrives with a qualified id; the typing controller
  // holds it verbatim and the UI resolves identity via the member/user cache
  // (fetching the replica on demand). Our own typing echoes back qualified to
  // our domain on a remote-homed channel, so skip-self matches both forms.
  subs.add(
    client.onTypingStart.listen((data) {
      if (!isActive()) return;
      final channelId = data['channel_id']?.toString();
      final userId = data['user_id']?.toString();
      if (channelId == null || userId == null) return;
      if (!activeMessageChannels.contains((
        serverKey: serverKey,
        channelId: channelId,
      ))) {
        return;
      }
      if (isSelf(userId)) return; // don't show our own typing
      ref
          .read(typingControllerProvider(serverKey, channelId).notifier)
          .userTyping(userId);
    }),
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
      final spaceId =
          data['space_id']?.toString() ?? data['guild_id']?.toString();
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

/// Seeds the voice-state cache from the gateway READY payload's `voice_states`
/// array (matches the reference client's `_apply_voice_states`). The payload is
/// flat — entries carry their own `channel_id` — so we bucket by channel.
void _seedVoiceStates(
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
void _hydrateReadState(
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
@visibleForTesting
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
Future<void> _loadSpaces(
  Ref ref,
  AccordClient client, {
  required String serverKey,
  required bool Function() isActive,
}) async {
  final result = await client.users.listSpaces();
  if (!result.ok) {
    debugPrint('Failed to load spaces: ${result.error}');
    return;
  }
  final data = result.data;
  if (data is! List) return;

  final spaces = data.whereType<AccordSpace>().toList();
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
      if (!result.ok) {
        debugPrint('Failed to load roles for ${space.id}: ${result.error}');
        continue;
      }
      final roles = result.data;
      if (roles is! List) continue;
      space.roles
        ..clear()
        ..addAll(roles.whereType<AccordRole>());
    }
  }

  final workerCount = spaces.length < maxConcurrentFetches
      ? spaces.length
      : maxConcurrentFetches;
  await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
}
