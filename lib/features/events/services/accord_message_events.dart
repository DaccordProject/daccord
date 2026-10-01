import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/forum_posts.dart';
import 'package:bonfire/features/messaging/controllers/pending_uploads.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/messaging/controllers/withdrawn_attachments.dart';
import 'package:bonfire/features/messaging/utils/attachment_withdrawal.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/notifications/services/notification.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/notifications/utils/notification_gate.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:collection/collection.dart';
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
  // Federation echoes our own actions back qualified to our home domain
  // (`<id>@<selfDomain>`), so self checks accept both forms (see [isSameUser]).
  bool isSelf(String? id) =>
      id != null && isSameUser(id, currentUserId, localDomain: selfDomain);
  bool mentionsSelf(Iterable<String> mentions) => mentions.any(isSelf);

  // ── Incoming messages ────────────────────────────────────────────────────
  // One `message.create` fans out to the caches, read state, the mention
  // notification and SFX, in that order. Each keeps its own skip conditions, so
  // a guard that silences the chime never suppresses the badge, and vice versa.
  subs.add(
    client.onMessageCreate.listen((message) {
      final active = isActive();
      final isOwn = isSelf(message.authorId);
      final mentionsMe = mentionsSelf(message.mentions);
      final isVisibleChannel =
          active && isAccordChannelVisible(serverKey, message.channelId);
      final settings = ref.read(settingsControllerProvider);
      final countsAsMention = MessageNotificationGate.countsAsMention(
        mentionsMe: mentionsMe,
        mentionEveryone: message.mentionEveryone,
        suppressEveryone: settings.suppressEveryone,
      );
      final isDirectMessage = message.spaceId == null;
      final spaceMuted =
          !isDirectMessage &&
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
      if (isDirectMessage) {
        ref
            .read(dmChannelsControllerProvider(serverKey).notifier)
            .applyMessage(message);
      }

      // A message carrying `thread_id` is a reply: route it into that thread
      // if open (`addReply` dedupes the composer's optimistic append).
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

      // A top-level message in an open forum is a new root post. Only forum
      // channels build that controller, so membership is the "is a forum" test.
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

      // Read state is tracked for every connection and ignores mutes
      // (indicators apply them at render); our own message is acked so the
      // server's READY `unread` list can't re-light the channel.
      final tracker = ref.read(readStateControllerProvider(serverKey).notifier);
      final fresh = tracker.receiveMessage(message.channelId, message.id);
      if (isOwn || isVisibleChannel) {
        tracker.acknowledge(client, message.channelId, message.id);
      } else if (fresh) {
        tracker.markUnread(
          message.channelId,
          spaceId: message.spaceId,
          isMention: countsAsMention,
          messageId: message.id,
        );
      }
      // Keep cache updates for replays, but suppress duplicate alerts.
      if (!fresh) return;

      // Notifications fire on every connection, opened channel or not; DMs
      // notify without a mention. Only the visible-channel skip is scoped to the
      // active connection, which owns that pointer.
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
        isDirectMessage: isDirectMessage,
      );
      if (notify) {
        final author = ref
            .read(accordUsersControllerProvider(serverKey).notifier)
            .cached(message.authorId);
        final name = accordUserName(
          author,
          fallback: isDirectMessage ? 'New message' : 'New mention',
        );
        final body = message.content.trim();
        showMentionNotification(
          serverKey: serverKey,
          channelId: message.channelId,
          messageId: message.id,
          title: name,
          body: body.isEmpty
              ? (isDirectMessage ? 'Sent you a message' : 'mentioned you')
              : body,
        );
      }

      // Message SFX (the reference `play_for_message`) on every connection,
      // never for our own messages, a muted space or a silenced channel. A DM
      // chimes like a mention.
      if (settings.soundsEnabled &&
          !spaceMuted &&
          !isOwn &&
          settings.channelNotificationLevel(serverKey, message.channelId) !=
              'nothing') {
        soundManager.playForMessage(
          isMention: countsAsMention || isDirectMessage,
          isVisibleChannel: isVisibleChannel,
          isMemberJoin: message.type == 'member_join',
        );
      }
    }),
  );

  // ── Withdrawn attachments ────────────────────────────────────────────────
  // A withdrawn file arrives as a `message.update` with a shorter attachment
  // list (and, for our own uploads, an `automod.upload_status`). Besides the
  // cached message, the image cache and any open lightbox must drop the bytes.
  final withdrawn = ref.read(
    withdrawnAttachmentsControllerProvider(serverKey).notifier,
  );
  final pendingUploads = ref.read(
    pendingUploadsControllerProvider(serverKey).notifier,
  );
  final cdnUrl = client.config.cdnUrl;

  /// The cached copy of a message, from whichever open cache holds it.
  AccordMessage? cachedMessage(
    String channelId,
    String messageId, {
    String? threadId,
  }) {
    final key = (serverKey: serverKey, channelId: channelId);
    if (activeMessageChannels.contains(key)) {
      final hit = ref
          .read(accordMessagesControllerProvider(serverKey, channelId))
          ?.firstWhereOrNull((m) => m.id == messageId);
      if (hit != null) return hit;
    }
    for (final t in activeThreadReplies) {
      if (t.serverKey != serverKey || t.channelId != channelId) continue;
      if (threadId != null && t.rootId != threadId) continue;
      final hit = ref
          .read(threadRepliesControllerProvider(serverKey, channelId, t.rootId))
          ?.firstWhereOrNull((m) => m.id == messageId);
      if (hit != null) return hit;
    }
    if (activeForumChannels.contains(key)) {
      return ref
          .read(forumPostsControllerProvider(serverKey, channelId))
          ?.firstWhereOrNull((m) => m.id == messageId);
    }
    return null;
  }

  /// Pushes an edited [message] into the DM preview and, on the active
  /// connection, every open cache for its channel. Each cache ignores IDs it
  /// doesn't hold, so no thread/forum routing is needed.
  void reapplyToCaches(AccordMessage message) {
    if (message.spaceId == null) {
      ref
          .read(dmChannelsControllerProvider(serverKey).notifier)
          .updateMessagePreview(message);
    }
    if (!isActive()) return;
    final key = (serverKey: serverKey, channelId: message.channelId);
    if (activeMessageChannels.contains(key)) {
      ref
          .read(
            accordMessagesControllerProvider(
              serverKey,
              message.channelId,
            ).notifier,
          )
          .updateMessage(message);
    }
    for (final t in [...activeThreadReplies]) {
      if (t.serverKey != serverKey || t.channelId != message.channelId) {
        continue;
      }
      ref
          .read(
            threadRepliesControllerProvider(
              serverKey,
              message.channelId,
              t.rootId,
            ).notifier,
          )
          .updateReply(message);
    }
    if (activeForumChannels.contains(key)) {
      ref
          .read(
            forumPostsControllerProvider(serverKey, message.channelId).notifier,
          )
          .updatePost(message);
    }
  }

  // ── Message cache (per channel) ──────────────────────────────────────────
  // Edits and deletes follow the same opened-channels rule as the cache block
  // above.
  subs.add(
    client.onMessageUpdate.listen((message) {
      // A tracked upload turning up as a real attachment is its publication,
      // whether or not the `published` status event has arrived yet.
      pendingUploads.applyPublishedAttachments(message);
      if (isActive()) {
        // Compare against the copy we hold *before* the caches replace it.
        final previous = cachedMessage(
          message.channelId,
          message.id,
          threadId: message.threadId,
        );
        final gone = withdrawnAttachments(previous, message);
        if (gone.isNotEmpty) withdrawn.withdraw(gone, cdnUrl: cdnUrl);
      }
      reapplyToCaches(message);
    }),
  );
  subs.add(
    client.onMessageDelete.listen((data) {
      final channelId = data['channel_id']?.toString();
      final messageId =
          data['id']?.toString() ?? data['message_id']?.toString();
      if (channelId == null || messageId == null) return;
      // A deleted message can't show a placeholder; drop its held uploads.
      pendingUploads.clearForMessage(messageId);
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

  // ── AutoMod upload status ────────────────────────────────────────────────
  // `automod.upload_status` (uploader only) names our own uploads, so an
  // unknown ID is buffered until the composer's 202 lands.
  // `automod.upload_update` (`moderation` intent, not requested by default)
  // only touches already-tracked IDs: a stranger's upload is never a
  // placeholder here. A refusal shrinks the cached message either way.
  void applyUploadStatus(
    AccordAutomodUploadStatus status, {
    required bool own,
  }) {
    pendingUploads.applyStatus(status, client: client, bufferUnknown: own);
    if (!AutomodUploadStatus.isRefused(status.status)) return;
    if (!isActive()) return;
    // A published-then-withdrawn attachment carries the upload's ID; strip it
    // now in case the `message.update` is delayed.
    final cached = cachedMessage(status.channelId, status.messageId);
    if (cached == null) return;
    final removed = removeAttachmentInPlace(cached, status.id);
    if (removed == null) return;
    withdrawn.withdraw([removed], cdnUrl: cdnUrl);
    reapplyToCaches(cached);
  }

  subs.add(
    client.onAutomodUploadStatus.listen(
      (status) => applyUploadStatus(status, own: true),
    ),
  );
  subs.add(
    client.onAutomodUploadUpdate.listen(
      (status) => applyUploadStatus(status, own: false),
    ),
  );

  // ── Read-state sync (multi-device) ───────────────────────────────────────
  // The server echoes our acks to our other sessions; acks only ever clear.
  subs.add(
    client.onReadStateUpdate.listen((data) {
      final channelId = data['channel_id']?.toString();
      if (channelId == null || channelId.isEmpty) return;
      final messageId = data['last_read_message_id']?.toString();
      if (messageId == null || messageId.isEmpty) return;
      ref
          .read(readStateControllerProvider(serverKey).notifier)
          .applyRemoteRead(channelId, messageId);
    }),
  );

  // ── Reactions (per channel) ──────────────────────────────────────────────
  // Only opened channels are mutated. The gateway sends a reaction's emoji as
  // a map (`{name, id}`) or a bare token (`name:id` for custom emoji); the token
  // is split so the echo keeps its id and matches the optimistic pill.
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
    // Our own reaction may echo back qualified; matching both forms keeps the
    // optimistic pill and its echo from double-counting.
    final isOwn = isSelf(data['user_id']?.toString());
    ref
        .read(accordMessagesControllerProvider(serverKey, channelId).notifier)
        .applyReaction(
          messageId,
          emoji.name,
          added: added,
          isOwn: isOwn,
          emojiId: emoji.id,
          userId: data['user_id']?.toString(),
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
  // Remote ids are stored verbatim (the UI resolves them); skip-self matches
  // our own qualified echo too.
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
