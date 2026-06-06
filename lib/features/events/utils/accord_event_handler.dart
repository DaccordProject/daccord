import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/notifications/controllers/notification.dart';
import 'package:bonfire/features/notifications/controllers/sound.dart';
import 'package:bonfire/features/notifications/utils/notification_gate.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/space.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
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
  required bool Function() isActive,
}) {
  final subs = <StreamSubscription<dynamic>>[];

  // Gateway lifecycle is mirrored per-connection (for the rail's status dots);
  // the global connection banner only follows the active connection.
  void setConnection(ConnectionStatus status) {
    ref
        .read(connectionsControllerProvider.notifier)
        .setStatus(serverKey, status);
    if (isActive()) {
      ref.read(connectionControllerProvider.notifier).set(status);
    }
  }

  // ── Connection lifecycle ─────────────────────────────────────────────────
  subs.add(client.onConnected.listen((_) {
    setConnection(ConnectionStatus.connected);
  }));
  subs.add(client.onReconnecting.listen((_) {
    setConnection(ConnectionStatus.reconnecting);
  }));
  subs.add(client.onDisconnected.listen((info) {
    debugPrint('Accord gateway disconnected: ${info.code} ${info.reason}');
    setConnection(ConnectionStatus.disconnected);
  }));

  // ── Initial sync ─────────────────────────────────────────────────────────
  subs.add(client.onReady.listen((data) async {
    setConnection(ConnectionStatus.ready);
    if (isActive()) {
      _seedPresences(ref, data);
      _seedVoiceStates(ref, data);
    }
    await _loadSpaces(ref, client, serverKey: serverKey, isActive: isActive);
  }));

  // ── Presence (active server only) ────────────────────────────────────────
  subs.add(client.onPresenceUpdate.listen((presence) {
    if (!isActive()) return;
    ref.read(presenceControllerProvider.notifier).upsert(presence);
  }));

  // ── Voice state cache (active server only) ───────────────────────────────
  // Tracks who is in each voice channel. A peer entering/leaving also chimes
  // (mirrors the reference `play_for_voice_state`), and our own state vanishing
  // signals a force-disconnect that the VoiceController must react to.
  subs.add(client.onVoiceStateUpdate.listen((vs) {
    if (!isActive()) return;
    final cache = ref.read(voiceStatesControllerProvider);
    final me = currentUserId;
    final myVoiceChannel = ref.read(voiceControllerProvider).channelId;
    final previousChannel = _channelOf(cache, vs.userId);
    ref.read(voiceStatesControllerProvider.notifier).upsert(vs);
    soundManager.playForVoiceState(
      isSelf: vs.userId == me,
      joinedChannel: vs.channelId,
      leftChannel: previousChannel,
      myVoiceChannel: myVoiceChannel,
    );
    // Our own channel becoming null while we believed we were connected means
    // the server kicked us out of voice — tear the session down locally.
    if (vs.userId == me && vs.channelId == null && myVoiceChannel != null) {
      ref.read(voiceControllerProvider.notifier).handleForcedDisconnect();
    }
  }));

  // ── Voice server update (active server only) ─────────────────────────────
  // Fresh LiveKit credentials for the channel we're (re)connecting to.
  subs.add(client.onVoiceServerUpdate.listen((info) {
    if (!isActive()) return;
    ref.read(voiceControllerProvider.notifier).handleServerUpdate(info);
  }));

  // ── Space cache ──────────────────────────────────────────────────────────
  // Always feed this connection's rail cache; only the active connection drives
  // the shared space controllers the panes read.
  void cacheSpace(AccordSpace space) {
    ref
        .read(connectionsControllerProvider.notifier)
        .upsertSpace(serverKey, space);
    if (!isActive()) return;
    ref.read(spacesControllerProvider.notifier).upsertSpace(space);
    ref.read(spaceControllerProvider(space.id).notifier).setSpace(space);
  }

  subs.add(client.onSpaceCreate.listen(cacheSpace));
  subs.add(client.onSpaceUpdate.listen(cacheSpace));
  subs.add(client.onSpaceDelete.listen((data) {
    final id = data['id']?.toString() ?? data['space_id']?.toString();
    if (id == null) return;
    ref.read(connectionsControllerProvider.notifier).removeSpace(serverKey, id);
    if (isActive()) {
      ref.read(spacesControllerProvider.notifier).removeSpace(id);
    }
  }));

  // ── Channel cache (per space, plus DM/group-DM channels) ─────────────────
  // Space channels feed the per-space channel controller; channels with no
  // space are DMs/group DMs and feed the global DM-channel cache so the
  // direct-messages dialog stays in sync (recipient add/remove arrive here as
  // channel.update).
  void cacheChannel(AccordChannel channel) {
    if (!isActive()) return;
    final spaceId = channel.spaceId;
    if (spaceId == null) {
      ref.read(dmChannelsControllerProvider.notifier).upsert(channel);
      return;
    }
    ref
        .read(accordChannelsControllerProvider(spaceId).notifier)
        .upsertChannel(channel);
  }

  subs.add(client.onChannelCreate.listen(cacheChannel));
  subs.add(client.onChannelUpdate.listen(cacheChannel));
  subs.add(client.onChannelDelete.listen((channel) {
    if (!isActive()) return;
    final spaceId = channel.spaceId;
    if (spaceId == null) {
      ref.read(dmChannelsControllerProvider.notifier).remove(channel.id);
      return;
    }
    ref
        .read(accordChannelsControllerProvider(spaceId).notifier)
        .removeChannel(channel.id);
  }));

  // ── Message cache (per channel) ──────────────────────────────────────────
  // Only touch channels the UI has actually opened (see [activeMessageChannels])
  // so we don't history-load every channel that receives a message.
  subs.add(client.onMessageCreate.listen((message) {
    if (!isActive()) return;
    if (!activeMessageChannels.contains(message.channelId)) return;
    ref
        .read(accordMessagesControllerProvider(message.channelId).notifier)
        .addMessage(message);
  }));
  subs.add(client.onMessageUpdate.listen((message) {
    if (!isActive()) return;
    if (!activeMessageChannels.contains(message.channelId)) return;
    ref
        .read(accordMessagesControllerProvider(message.channelId).notifier)
        .updateMessage(message);
  }));
  subs.add(client.onMessageDelete.listen((data) {
    if (!isActive()) return;
    final channelId = data['channel_id']?.toString();
    final messageId =
        data['id']?.toString() ?? data['message_id']?.toString();
    if (channelId == null || messageId == null) return;
    if (!activeMessageChannels.contains(channelId)) return;
    ref
        .read(accordMessagesControllerProvider(channelId).notifier)
        .removeMessage(messageId);
  }));

  // ── Read state (unread + mention badges) ─────────────────────────────────
  // Independent of the channel cache: every message that arrives in a channel
  // other than the visible one marks that channel unread (with a bumped
  // mention count when the user is mentioned). Mirrors the reference client's
  // `client_unread.gd`.
  subs.add(client.onMessageCreate.listen((message) {
    if (!isActive()) return;
    final me = currentUserId;
    if (message.authorId == me) return;
    if (message.channelId == accordVisibleChannelId) return;
    final mentionsMe = message.mentionEveryone ||
        message.mentions.contains(me);
    ref
        .read(readStateControllerProvider.notifier)
        .markUnread(message.channelId, isMention: mentionsMe);
  }));

  // ── Mention notifications ────────────────────────────────────────────────
  // Independent of the channel cache: fire for *any* mentioning message, even
  // in channels the UI hasn't opened. Skips our own messages, the channel
  // that's currently on screen, and respects the user's notification prefs.
  // Gated to the active connection: author/visible-channel matching relies on
  // the active session's IDs, which collide with background servers'.
  subs.add(client.onMessageCreate.listen((message) {
    if (!isActive()) return;
    final settings = ref.read(settingsControllerProvider);

    final me = currentUserId;

    final notify = MessageNotificationGate.shouldNotify(
      notificationsEnabled: settings.notificationsEnabled,
      suppressEveryone: settings.suppressEveryone,
      isOwnMessage: message.authorId == me,
      isVisibleChannel: message.channelId == accordVisibleChannelId,
      mentionsMe: message.mentions.contains(me),
      mentionEveryone: message.mentionEveryone,
      channelLevel: settings.channelNotificationLevel(message.channelId),
    );
    if (!notify) return;

    final author = ref.read(accordUsersControllerProvider)[message.authorId];
    final name = accordUserName(author, fallback: 'New mention');
    final body = message.content.trim();
    showMentionNotification(
      title: name,
      body: body.isEmpty ? 'mentioned you' : body,
    );
  }));

  // ── Message SFX ──────────────────────────────────────────────────────────
  // Independent of the channel cache (mirrors the reference `play_for_message`).
  // Plays for *any* incoming message, gated by sound prefs + window focus, and
  // never chimes for our own messages or the channel that's on screen.
  subs.add(client.onMessageCreate.listen((message) {
    if (!isActive()) return;
    final settings = ref.read(settingsControllerProvider);
    if (!settings.soundsEnabled) return;

    final me = currentUserId;
    if (message.authorId == me) return;

    final everyone = message.mentionEveryone && !settings.suppressEveryone;
    final isMention = message.mentions.contains(me) || everyone;
    soundManager.playForMessage(
      isMention: isMention,
      isVisibleChannel: message.channelId == accordVisibleChannelId,
      isMemberJoin: message.type == 'member_join',
    );
  }));

  // ── Reactions (per channel) ──────────────────────────────────────────────
  // Like messages, only mutate channels the UI has opened.
  String emojiName(Map<String, dynamic> data) {
    final raw = data['emoji'];
    if (raw is Map) return raw['name']?.toString() ?? '';
    if (raw is String) return raw;
    return '';
  }

  String? emojiId(Map<String, dynamic> data) {
    final raw = data['emoji'];
    if (raw is Map) return raw['id']?.toString();
    return null;
  }

  void applyReactionEvent(Map<String, dynamic> data, {required bool added}) {
    if (!isActive()) return;
    final channelId = data['channel_id']?.toString();
    final messageId = data['message_id']?.toString();
    final name = emojiName(data);
    if (channelId == null || messageId == null || name.isEmpty) return;
    if (!activeMessageChannels.contains(channelId)) return;
    final isOwn = data['user_id']?.toString() == currentUserId;
    ref
        .read(accordMessagesControllerProvider(channelId).notifier)
        .applyReaction(messageId, name,
            added: added, isOwn: isOwn, emojiId: emojiId(data));
  }

  subs.add(client.onReactionAdd.listen((d) => applyReactionEvent(d, added: true)));
  subs.add(
      client.onReactionRemove.listen((d) => applyReactionEvent(d, added: false)));
  subs.add(client.onReactionClear.listen((data) {
    if (!isActive()) return;
    final channelId = data['channel_id']?.toString();
    final messageId = data['message_id']?.toString();
    if (channelId == null || messageId == null) return;
    if (!activeMessageChannels.contains(channelId)) return;
    ref
        .read(accordMessagesControllerProvider(channelId).notifier)
        .clearReactions(messageId);
  }));
  subs.add(client.onReactionClearEmoji.listen((data) {
    if (!isActive()) return;
    final channelId = data['channel_id']?.toString();
    final messageId = data['message_id']?.toString();
    final name = emojiName(data);
    if (channelId == null || messageId == null || name.isEmpty) return;
    if (!activeMessageChannels.contains(channelId)) return;
    ref
        .read(accordMessagesControllerProvider(channelId).notifier)
        .clearReactionEmoji(messageId, name);
  }));

  // ── Typing indicators (per channel) ──────────────────────────────────────
  subs.add(client.onTypingStart.listen((data) {
    if (!isActive()) return;
    final channelId = data['channel_id']?.toString();
    final userId = data['user_id']?.toString();
    if (channelId == null || userId == null) return;
    if (!activeMessageChannels.contains(channelId)) return;
    if (userId == currentUserId) return; // don't show our own typing
    ref.read(typingControllerProvider(channelId).notifier).userTyping(userId);
  }));

  // ── Member cache (per space) ─────────────────────────────────────────────
  // Only touch spaces the UI has actually opened (see [activeMemberSpaces]) so
  // a single join event doesn't history-load every space's full member list.
  void cacheMember(AccordMember member) {
    if (!isActive()) return;
    if (!activeMemberSpaces.contains(member.spaceId)) return;
    ref
        .read(accordMembersControllerProvider(member.spaceId).notifier)
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
  subs.add(client.onRoleDelete.listen((data) {
    if (!isActive()) return;
    final spaceId = roleSpaceId(data);
    final roleId = data['role_id']?.toString() ??
        (data['role'] is Map ? (data['role'] as Map)['id']?.toString() : null);
    if (spaceId == null || roleId == null) return;
    ref.read(spacesControllerProvider.notifier).removeRole(spaceId, roleId);
  }));

  subs.add(client.onMemberJoin.listen(cacheMember));
  subs.add(client.onMemberUpdate.listen(cacheMember));
  subs.add(client.onMemberLeave.listen((data) {
    if (!isActive()) return;
    final spaceId = data['space_id']?.toString() ?? data['guild_id']?.toString();
    final userId =
        data['user_id']?.toString() ?? (data['user'] is Map
            ? (data['user'] as Map)['id']?.toString()
            : null);
    if (spaceId == null || userId == null) return;
    if (!activeMemberSpaces.contains(spaceId)) return;
    ref
        .read(accordMembersControllerProvider(spaceId).notifier)
        .removeMember(userId);
  }));

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
void _seedVoiceStates(Ref ref, Map<String, dynamic> ready) {
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
  final notifier = ref.read(voiceStatesControllerProvider.notifier);
  for (final entry in byChannel.entries) {
    notifier.seedChannel(entry.key, entry.value);
  }
}

/// Seeds the global presence cache from the gateway READY payload's
/// `presences` array (matches the reference client's `_apply_presences`).
void _seedPresences(Ref ref, Map<String, dynamic> ready) {
  final raw = ready['presences'];
  if (raw is! List) return;
  final presences = [
    for (final entry in raw)
      if (entry is Map<String, dynamic>) AccordPresence.fromJson(entry),
  ];
  if (presences.isEmpty) return;
  ref.read(presenceControllerProvider.notifier).seed(presences);
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
  ref.read(connectionsControllerProvider.notifier).setSpaces(serverKey, spaces);
  if (!isActive()) return;
  ref.read(spacesControllerProvider.notifier).setSpaces(spaces);
  for (final space in spaces) {
    ref.read(spaceControllerProvider(space.id).notifier).setSpace(space);
  }
}
