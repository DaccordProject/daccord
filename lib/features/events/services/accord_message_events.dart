import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/forum_posts.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/notifications/services/notification.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/notifications/utils/notification_gate.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The message-domain half of `handleAccordEvents`: incoming messages, the
/// per-channel message/thread/forum caches, multi-device read-state sync,
/// reactions and typing indicators. Appends its subscriptions to [subs]; the
/// parameters mirror `handleAccordEvents` (see it for what [serverKey] and
/// [isActive] mean).
void bindMessageEvents(
  Ref ref,
  AccordClient client,
  List<StreamSubscription<dynamic>> subs, {
  required String serverKey,
  required String currentUserId,
  required String selfDomain,
  required bool Function() isActive,
}) {
  // Federation echoes the local user's own actions back qualified to our home
  // domain (`<id>@<selfDomain>`), so a bare `== currentUserId` no longer
  // recognises them. These treat both forms as self — see [isSameUser] — and
  // are used wherever an event would otherwise self-notify, self-chime, or
  // double-count (message author, mentions, reaction ownership, typing).
  bool isSelf(String? id) =>
      id != null && isSameUser(id, currentUserId, localDomain: selfDomain);
  bool mentionsSelf(Iterable<String> mentions) => mentions.any(isSelf);

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
}
