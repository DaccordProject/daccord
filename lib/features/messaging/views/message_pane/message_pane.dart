/// The message pane shown for the selected channel on the home screen: channel
/// header, scrolling message history (with paging, grouping, bulk selection),
/// typing indicator, and composer — plus the voice/forum channel views it
/// delegates to. Extracted from the spaces feature's `accord_home.dart` part
/// cluster; [MessagePane] is the sole public entry point, everything else in
/// the `part` files stays private to this library.
library;

import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/member/views/accord_member_popout.dart';
import 'package:bonfire/features/messaging/controllers/accord_emojis.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/messaging/utils/attachment_limits.dart';
import 'package:bonfire/features/messaging/utils/attachment_types.dart';
import 'package:bonfire/features/messaging/utils/dropped_entity.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/messaging/views/box/accord_embed_box.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_content.dart';
import 'package:bonfire/features/messaging/views/emoji_picker.dart';
import 'package:bonfire/features/messaging/views/forum_view.dart';
import 'package:bonfire/features/messaging/utils/emoticons.dart';
import 'package:bonfire/features/messaging/views/image_lightbox.dart';
import 'package:bonfire/features/messaging/views/inline_audio_player.dart';
import 'package:bonfire/features/messaging/views/inline_video_player.dart';
import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:bonfire/features/messaging/views/message_author_header.dart';
import 'package:bonfire/features/messaging/views/pinned_messages.dart';
import 'package:bonfire/features/messaging/views/thread_view.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/notifications/utils/notification_gate.dart';
import 'package:bonfire/features/onboarding/models/onboarding_step.dart';
import 'package:bonfire/features/onboarding/views/onboarding_anchors.dart';
import 'package:bonfire/features/server/controllers/server_limits.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/restore_failed_send.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';

part 'attachments.dart';
part 'composer.dart';
part 'message_row.dart';
part 'message_row_actions.dart';
part 'mute_button.dart';
part 'reactions.dart';

class MessagePane extends ConsumerStatefulWidget {
  const MessagePane({
    super.key,
    required this.channel,
    required this.channelId,
    required this.spaceId,
    this.panel = false,
    this.panelTitle,
    this.onClosePanel,
  });

  final AccordChannel? channel;
  final String? channelId;
  final String? spaceId;

  /// Renders the channel's *text chat only*, in the slimmer presentation used
  /// by the voice channel view's side panel (see [VoiceTextPanel]): a compact
  /// header with a left divider instead of the full 48px channel header, and no
  /// delegation to [VoiceChannelView] — a voice channel shows its chat here
  /// rather than recursing back into the voice view that embedded this pane.
  ///
  /// Everything below the header is the same widget tree the regular pane
  /// builds, so a voice channel's chat keeps every text-channel affordance:
  /// context menus, reactions, replies, threads, edit/delete/pin/report,
  /// attachments and history paging (#210).
  final bool panel;

  /// Header title for [panel] mode, when the caller knows the channel name but
  /// not the [AccordChannel] itself. Falls back to the channel's own name.
  final String? panelTitle;

  /// Closes the panel. When null (or outside [panel] mode) no close button is
  /// shown.
  final VoidCallback? onClosePanel;

  @override
  ConsumerState<MessagePane> createState() => _MessagePaneState();
}

class _MessagePaneState extends ConsumerState<MessagePane> {
  AccordMessage? _replyTo;
  final ScrollController _scroll = ScrollController();

  /// Multi-select state for bulk message deletion (gated on `manage_messages`).
  /// Entered via long-press on a message; while active, tapping a row toggles
  /// its membership in [_selectedMessageIds] instead of running row actions.
  bool _selecting = false;
  final Set<String> _selectedMessageIds = {};
  bool _bulkDeleting = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(MessagePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear any pending reply or selection when switching channels.
    if (oldWidget.channelId != widget.channelId) {
      if (_replyTo != null) _replyTo = null;
      if (_selecting || _selectedMessageIds.isNotEmpty) {
        _selecting = false;
        _selectedMessageIds.clear();
      }
    }
  }

  void _enterSelection(String messageId) {
    setState(() {
      _selecting = true;
      _selectedMessageIds
        ..clear()
        ..add(messageId);
    });
  }

  void _toggleSelected(String messageId) {
    setState(() {
      if (!_selectedMessageIds.add(messageId)) {
        _selectedMessageIds.remove(messageId);
      }
      if (_selectedMessageIds.isEmpty) _selecting = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedMessageIds.clear();
    });
  }

  Future<void> _bulkDeleteSelected() async {
    final channelId = widget.channelId;
    if (channelId == null || _selectedMessageIds.isEmpty || _bulkDeleting) {
      return;
    }
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) return;
    final count = _selectedMessageIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete messages',
      message: 'Delete $count message(s)? This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _bulkDeleting = true);
    final ids = _selectedMessageIds.toList();
    final ok = await ref
        .read(accordMessagesControllerProvider(ref.readActiveServerKey() ?? '', channelId).notifier)
        .bulkDelete(client, ids);
    if (!mounted) return;
    setState(() {
      _bulkDeleting = false;
      if (ok) {
        _selecting = false;
        _selectedMessageIds.clear();
      }
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Watches for the user scrolling near the top of the history (with
  /// `reverse: true`, that means approaching [maxScrollExtent]) and pages in
  /// older messages. The controller dedupes concurrent calls so we can fire
  /// this aggressively on every scroll tick.
  void _onScroll() {
    final channelId = widget.channelId;
    if (channelId == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels > 240) return;
    final notifier = ref.read(
      accordMessagesControllerProvider(ref.readActiveServerKey() ?? '', channelId).notifier,
    );
    if (notifier.isLoadingOlder || !notifier.hasMoreOlder) return;
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) return;
    notifier.loadOlder(client);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final channel = widget.channel;
    final channelId = widget.channelId;
    final spaceId = widget.spaceId;

    if (channelId == null) {
      return Container(
        color: colors.background,
        alignment: Alignment.center,
        child: Text(
          'Select a channel',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    // In panel mode this pane *is* the voice view's chat panel — delegating
    // back to the voice view would recurse.
    if (!widget.panel && channel?.type == 'voice') {
      return VoiceChannelView(
        channelId: channelId,
        spaceId: spaceId,
        channelName: channel?.name,
      );
    }

    final messages = ref.watch(accordMessagesControllerProvider(ref.readActiveServerKey() ?? '', channelId));
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(ref.readActiveServerKey() ?? '', spaceId));
    final userCache = ref.watch(accordUsersControllerProvider(ref.readActiveServerKey() ?? ''));
    final space = spaceId == null
        ? null
        : ref.watch(
            spacesControllerProvider.select(
              (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId),
            ),
          );
    final roles = space?.roles ?? const <AccordRole>[];
    final currentUserId = ref.watchUserId();
    // Our home domain — recognises our own author/mention id when a remote home
    // echoes it back qualified (`me@a.example`) on a federated message.
    final homeDomain = ref.watchHomeDomain();
    final myRoles =
        (currentUserId == null ? null : members?[currentUserId])?.roles ??
        const <String>[];

    final spacePerms = spaceId == null
        ? const <String>{}
        : ref.watchAccordPermissions(space, spaceId);
    final everyoneRoleId = roles
        .where((role) => role.position == 0)
        .map((role) => role.id)
        .firstOrNull;
    final perms = accordEffectiveChannelPermissions(
      permissions: spacePerms,
      channel: channel,
      everyoneRoleId: everyoneRoleId ?? '',
      memberRoleIds: myRoles.toSet(),
      currentUserId: currentUserId ?? '',
    );
    final canManageMessages = accordHasPermission(
      perms,
      AccordPermission.manageMessages,
    );
    final canSend = accordHasPermission(perms, AccordPermission.sendMessages);
    final canMentionEveryone = accordHasPermission(
      perms,
      AccordPermission.mentionEveryone,
    );
    final suppressEveryone = ref.watch(
      settingsControllerProvider.select((s) => s.suppressEveryone),
    );

    if (channel?.type == 'forum') {
      return Container(
        color: colors.background,
        child: Column(
          children: [
            Container(
              height: 48,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 16, right: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.foreground, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.forum, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      channel?.name ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ForumChannelView(
                channelId: channelId,
                spaceId: spaceId,
                canPost: canSend || canManageMessages,
                canManageMessages: canManageMessages,
                currentUserId: currentUserId,
              ),
            ),
          ],
        ),
      );
    }

    final panel = widget.panel;
    final childIndexByMessageId = messages == null
        ? const <String, int>{}
        : {
            for (var i = 0; i < messages.length; i++)
              // `reverse: true`: source index 0 is the last rendered row.
              messages[i].id: messages.length - 1 - i,
          };

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        // In panel mode the pane sits beside the video grid, so it needs a
        // divider on its leading edge too.
        border: panel
            ? Border(left: BorderSide(color: colors.foreground, width: 1))
            : null,
      ),
      child: Column(
        children: [
          Container(
            height: panel ? 44 : 48,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.only(
              left: panel ? 12 : 16,
              right: panel ? 4 : 8,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.foreground, width: 1),
              ),
            ),
            child: _selecting
                ? Row(
                    children: [
                      IconButton(
                        tooltip: 'Cancel',
                        onPressed: _bulkDeleting ? null : _exitSelection,
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: colors.dirtyWhite,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${_selectedMessageIds.length} selected',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _bulkDeleting || _selectedMessageIds.isEmpty
                            ? null
                            : _bulkDeleteSelected,
                        icon: _bulkDeleting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                        label: Text(
                          'Delete',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        panel
                            ? Icons.chat_bubble_outline
                            : channel?.type == 'announcement'
                            ? Icons.campaign
                            : Icons.tag,
                        size: panel ? 16 : 18,
                        color: colors.dirtyWhite,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          panel
                              ? (widget.panelTitle ?? channel?.name ?? 'Chat')
                              : channel?.name ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Pinned messages',
                        onPressed: () => showPinnedMessages(
                          context,
                          channelId: channelId,
                          spaceId: spaceId,
                          canManage: canManageMessages,
                        ),
                        icon: Icon(
                          Icons.push_pin_outlined,
                          size: 18,
                          color: colors.dirtyWhite,
                        ),
                      ),
                      _MuteButton(channelId: channelId),
                      if (panel && widget.onClosePanel != null)
                        IconButton(
                          tooltip: 'Close chat',
                          onPressed: widget.onClosePanel,
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: colors.dirtyWhite,
                          ),
                        ),
                    ],
                  ),
          ),
          Expanded(
            child: messages == null
                ? const LoadingView()
                : messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: EdgeInsets.symmetric(
                      horizontal: panel ? 10 : 16,
                      vertical: panel ? 8 : 12,
                    ),
                    // One extra slot at the top of history (rendered last
                    // under `reverse: true`) shows a spinner while older
                    // pages load and a "Beginning of channel" hint once we
                    // hit the start of history.
                    itemCount: messages.length + 1,
                    // Lets the sliver *move* a keyed row to its new index
                    // rather than tearing its element down and rebuilding
                    // it there. Without this the ValueKeys below only stop
                    // rows adopting each other's state — every row would
                    // still be recreated (losing an open editor, and
                    // unmounting a row mid-dialog) each time the list
                    // shifted. See #198.
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<String>) return null;
                      return childIndexByMessageId[key.value];
                    },
                    itemBuilder: (context, index) {
                      if (index == messages.length) {
                        return _OlderHistoryHeader(channelId: channelId);
                      }
                      final messageIndex = messages.length - 1 - index;
                      final message = messages[messageIndex];
                      // Group with the previous (older) message when it's
                      // from the same author, this message isn't a reply,
                      // and the two are close together in time. Grouped
                      // rows drop the repeated avatar/name/timestamp header.
                      final prev = messageIndex > 0
                          ? messages[messageIndex - 1]
                          : null;
                      final grouped = _isGrouped(
                        previous: prev,
                        current: message,
                      );
                      final author = members?[message.authorId];
                      // Members only loads the first page; backfill authors
                      // outside it from the on-demand user cache.
                      AccordUser? authorUser;
                      if (author == null && members != null) {
                        authorUser = userCache[message.authorId];
                        if (authorUser == null) {
                          ref
                              .read(accordUsersControllerProvider(ref.readActiveServerKey() ?? '').notifier)
                              .ensure(message.authorId);
                        }
                      }
                      final colorRole = author == null
                          ? null
                          : memberColorRole(author, roles);
                      final uid = currentUserId;
                      final isOwn =
                          uid != null &&
                          isSameUser(
                            message.authorId,
                            uid,
                            localDomain: homeDomain,
                          );
                      final mentionsMe =
                          !isOwn &&
                          uid != null &&
                          MessageNotificationGate.countsAsMention(
                            mentionsMe: _mentionsSelf(
                              message,
                              uid,
                              homeDomain,
                              myRoles,
                            ),
                            mentionEveryone: message.mentionEveryone,
                            suppressEveryone: suppressEveryone,
                          );
                      return _MessageRow(
                        // Keyed by message id, not list position. Under
                        // `reverse: true` every index shifts when a message
                        // arrives, so without a key Flutter re-binds a live
                        // _MessageRowState to a *different* message — and
                        // any dialog it had open (delete confirm, emoji
                        // picker) would then act on the wrong one. See #198.
                        key: ValueKey(message.id),
                        message: message,
                        grouped: grouped,
                        narrow: panel,
                        author: author,
                        authorUser: authorUser,
                        nameColor: colorRole == null
                            ? null
                            : accordRoleColor(colorRole.color),
                        channelId: channelId,
                        spaceId: spaceId,
                        isOwn: isOwn,
                        mentionsMe: mentionsMe,
                        canManageMessages: canManageMessages,
                        selecting: _selecting,
                        selected: _selectedMessageIds.contains(message.id),
                        onLongPressSelect: canManageMessages
                            ? () => _enterSelection(message.id)
                            : null,
                        onToggleSelected: () => _toggleSelected(message.id),
                        onReply: () => setState(() => _replyTo = message),
                      );
                    },
                  ),
          ),
          _TypingIndicator(channelId: channelId, spaceId: spaceId),
          OnboardingAnchor(
            anchor: OnboardingAnchorId.messageComposer,
            child: _Composer(
              channelId: channelId,
              channelName: panel
                  ? (widget.panelTitle ?? channel?.name)
                  : channel?.name,
              spaceId: spaceId,
              canMentionEveryone: canMentionEveryone,
              replyingTo: _replyTo,
              replyName: _replyTo == null
                  ? null
                  : accordAuthorName(
                      _replyTo!.authorId,
                      members: members,
                      users: userCache,
                      ensure: ref
                          .read(accordUsersControllerProvider(ref.readActiveServerKey() ?? '').notifier)
                          .ensure,
                    ),
              onCancelReply: () => setState(() => _replyTo = null),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether [message] mentions the local user [uid] (directly or via one of
/// their [myRoles]). A federated mention of us is qualified to our [homeDomain]
/// (`uid@homeDomain`), so direct mentions match through [isSameUser] rather than
/// a bare equality. `@everyone` is handled by the caller.
bool _mentionsSelf(
  AccordMessage message,
  String uid,
  String? homeDomain,
  List<String> myRoles,
) =>
    message.mentions.any((m) => isSameUser(m, uid, localDomain: homeDomain)) ||
    message.mentionRoles.any(myRoles.contains);

/// How close in time two consecutive same-author messages must be to collapse
/// into a single group (matching the reference client's denser layout).
const Duration _messageGroupWindow = Duration(minutes: 7);

/// Whether [current] should render as a continuation of [previous] — same
/// author, not a reply, and within [_messageGroupWindow]. Grouped rows hide the
/// repeated avatar/name/timestamp header.
bool _isGrouped({
  required AccordMessage? previous,
  required AccordMessage current,
}) {
  if (previous == null) return false;
  if (previous.authorId != current.authorId) return false;
  if (current.replyTo != null) return false;
  final t0 = DateTime.tryParse(previous.timestamp);
  final t1 = DateTime.tryParse(current.timestamp);
  if (t0 == null || t1 == null) return false;
  return t1.difference(t0).abs() < _messageGroupWindow;
}

/// A thin "X is typing…" line above the composer, resolving typing user IDs to
/// names via the space's member cache.
class _TypingIndicator extends ConsumerWidget {
  const _TypingIndicator({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final typing = ref.watch(typingControllerProvider(ref.readActiveServerKey() ?? '', channelId));
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(ref.readActiveServerKey() ?? '', spaceId!));
    final userCache = ref.watch(accordUsersControllerProvider(ref.readActiveServerKey() ?? ''));

    String nameFor(String userId) {
      final member = members?[userId];
      if (member != null) return accordMemberName(member, fallback: 'Someone');
      final user = userCache[userId];
      if (user != null) return accordUserName(user, fallback: 'Someone');
      if (members != null) {
        ref.read(accordUsersControllerProvider(ref.readActiveServerKey() ?? '').notifier).ensure(userId);
      }
      return 'Someone';
    }

    String? label;
    if (typing.length == 1) {
      label = '${nameFor(typing.first)} is typing…';
    } else if (typing.length == 2) {
      label = '${nameFor(typing[0])} and ${nameFor(typing[1])} are typing…';
    } else if (typing.length > 2) {
      label = 'Several people are typing…';
    }

    return SizedBox(
      height: 20,
      child: label == null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium!.copyWith(color: colors.gray),
                ),
              ),
            ),
    );
  }
}
