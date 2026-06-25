import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/components/box/accord_message_content.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Text chat for a voice channel, shown beside (or over) the video grid while in
/// a voice call. Ports the reference client's dedicated `voice_text_panel.gd`:
/// a header with the channel name + close button, the channel's message history,
/// a typing line, and a composer. It reuses the shared message providers and the
/// [AccordMessageContent] renderer rather than the full message pane, matching
/// the reference's separate, slimmer panel.
class VoiceTextPanel extends ConsumerStatefulWidget {
  const VoiceTextPanel({
    super.key,
    required this.channelId,
    required this.spaceId,
    required this.channelName,
    this.onClose,
  });

  final String channelId;
  final String? spaceId;
  final String? channelName;

  /// Called when the user taps the panel's close button. When null the close
  /// button is hidden (e.g. when the panel is the whole surface).
  final VoidCallback? onClose;

  @override
  ConsumerState<VoiceTextPanel> createState() => _VoiceTextPanelState();
}

class _VoiceTextPanelState extends ConsumerState<VoiceTextPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Opening the panel clears the voice channel's unread state, mirroring the
    // reference's `Client.clear_channel_unread`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // The panel's channel lives on whichever server the call is pinned to,
        // which may not be the active one.
        final serverKey = ref.read(voiceControllerProvider).serverKey ??
            ref.read(connectionsControllerProvider).activeKey;
        if (serverKey != null) {
          ref
              .read(readStateControllerProvider(serverKey).notifier)
              .markRead(widget.channelId);
        }
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty || _sending) return;
    final client = ref.accordClient;
    if (client == null) return;
    setState(() => _sending = true);
    final ok = await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .send(client, text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final channelId = widget.channelId;
    final messages = ref.watch(accordMessagesControllerProvider(channelId));
    final members = widget.spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(widget.spaceId!));
    final users = ref.watch(accordUsersControllerProvider);
    final cdnUrl = ref.watchCdnUrl();

    String nameOf(String userId) => members?[userId] != null
        ? accordMemberName(members![userId], fallback: userId)
        : accordUserName(users[userId], fallback: userId);
    String? avatarOf(String userId) => members?[userId] != null
        ? accordMemberAvatarUrl(members![userId], cdnUrl)
        : accordAvatarUrl(users[userId], cdnUrl);

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(left: BorderSide(color: colors.foreground, width: 1)),
      ),
      child: Column(
        children: [
          _header(context, colors),
          Expanded(
            child: messages == null
                ? const LoadingView()
                : messages.isEmpty
                    ? Center(
                        child: Text('No messages yet',
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(color: colors.gray)),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final i = messages.length - 1 - index;
                          final message = messages[i];
                          final prev = i > 0 ? messages[i - 1] : null;
                          final grouped = prev != null &&
                              prev.authorId == message.authorId &&
                              message.replyTo == null;
                          // Backfill authors outside the first member page.
                          if (members != null &&
                              members[message.authorId] == null &&
                              users[message.authorId] == null) {
                            ref
                                .read(accordUsersControllerProvider.notifier)
                                .ensure(message.authorId);
                          }
                          return _VoiceTextMessage(
                            authorName: nameOf(message.authorId),
                            avatarUrl: avatarOf(message.authorId),
                            avatarBg: accordAvatarColor(
                                members?[message.authorId]?.user ??
                                    users[message.authorId],
                                message.authorId),
                            content: message.content,
                            spaceId: widget.spaceId,
                            grouped: grouped,
                          );
                        },
                      ),
          ),
          _TypingLine(channelId: channelId, spaceId: widget.spaceId),
          _composer(context, colors),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, BonfireThemeExtension colors) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.foreground, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline, size: 16, color: colors.dirtyWhite),
          const SizedBox(width: 6),
          Expanded(
            child: Text(widget.channelName ?? 'Chat',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: 'Close chat',
              onPressed: widget.onClose,
              icon: Icon(Icons.close, size: 18, color: colors.dirtyWhite),
            ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context, BonfireThemeExtension colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colors.foreground,
                hintText: 'Message #${widget.channelName ?? ''}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.send, size: 20, color: colors.dirtyWhite),
          ),
        ],
      ),
    );
  }
}

/// A single message row in the voice text panel. Grouped rows (same consecutive
/// author) drop the avatar/name header, matching the reference's collapsed rows.
class _VoiceTextMessage extends StatelessWidget {
  const _VoiceTextMessage({
    required this.authorName,
    required this.avatarUrl,
    required this.avatarBg,
    required this.content,
    required this.spaceId,
    required this.grouped,
  });

  final String authorName;
  final String? avatarUrl;
  final Color avatarBg;
  final String content;
  final String? spaceId;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final initial = accordInitial(authorName);
    return Padding(
      padding: EdgeInsets.only(top: grouped ? 1 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: grouped
                ? null
                : CircleAvatar(
                    radius: 14,
                    backgroundColor: avatarBg,
                    foregroundImage: avatarUrl == null
                        ? null
                        : CachedNetworkImageProvider(avatarUrl!),
                    child: Text(initial,
                        style: TextStyle(
                            color: accordOnColor(avatarBg), fontSize: 12)),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!grouped)
                  Text(authorName,
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                          color: colors.dirtyWhite,
                          fontWeight: FontWeight.w600)),
                AccordMessageContent(content: content, spaceId: spaceId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "X is typing…" line for the voice text panel.
class _TypingLine extends ConsumerWidget {
  const _TypingLine({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final typing = ref.watch(typingControllerProvider(channelId));
    if (typing.isEmpty) return const SizedBox(height: 4);
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(spaceId!));
    final users = ref.watch(accordUsersControllerProvider);

    String nameFor(String userId) {
      final member = members?[userId];
      if (member != null) return accordMemberName(member, fallback: 'Someone');
      return accordUserName(users[userId], fallback: 'Someone');
    }

    final label = typing.length == 1
        ? '${nameFor(typing.first)} is typing…'
        : typing.length == 2
            ? '${nameFor(typing[0])} and ${nameFor(typing[1])} are typing…'
            : 'Several people are typing…';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall!
                .copyWith(color: colors.gray)),
      ),
    );
  }
}
