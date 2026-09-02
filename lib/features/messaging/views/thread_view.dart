import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/utils/emoticons.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_content.dart';
import 'package:bonfire/features/messaging/views/message_author_header.dart';
import 'package:bonfire/features/messaging/views/post_composer_dialog.dart';
import 'package:bonfire/features/messaging/utils/message_visibility.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/restore_failed_send.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a thread/forum-post view as a modal dialog: the [root] message at the
/// top, its replies below, and a composer that posts replies into the thread
/// (`thread_id`). Used for ad-hoc threads off regular messages; forum channels
/// embed [AccordThreadPane] inline in the message area instead.
///
/// [canManageMessages] gates moderator actions (delete others' replies). When
/// the root post is edited or deleted from inside the view the returned future
/// completes with a [ThreadResult] so the caller (the forum index) can refresh
/// its row; `null` means nothing changed.
Future<ThreadResult?> showAccordThread(
  BuildContext context, {
  required String channelId,
  String? spaceId,
  required AccordMessage root,
  bool canManageMessages = false,
  ValueChanged<AccordUser>? onUserTap,
  void Function(AccordUser user, Offset? globalPosition)? onUserContextMenu,
}) {
  return showDialog<ThreadResult>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: AccordThreadPane(
          channelId: channelId,
          spaceId: spaceId,
          root: root,
          canManageMessages: canManageMessages,
          onUserTap: onUserTap,
          onUserContextMenu: onUserContextMenu,
          dialog: true,
          onClose: (result) => Navigator.of(dialogContext).pop(result),
        ),
      ),
    ),
  );
}

/// The outcome of a thread view, reported back to the forum index so it can
/// reflect a root-post edit or removal without a full reload.
class ThreadResult {
  const ThreadResult.edited(this.root) : deleted = false;
  const ThreadResult.deleted() : root = null, deleted = true;

  /// The updated root post (when edited), else null.
  final AccordMessage? root;

  /// Whether the root post was deleted.
  final bool deleted;
}

/// The thread/forum-post view body: the [root] message, its replies, and a
/// reply composer. Renders inline (filling the message area, with a back arrow)
/// by default, or as dialog chrome (a close icon, shrink-wrapped) when [dialog]
/// is set. [onClose] is invoked with a [ThreadResult] when the root is edited or
/// deleted (else `null`) so the caller can refresh its row and dismiss the view.
///
/// The reply list itself lives in [ThreadRepliesController] (keyed by channel +
/// root), which self-loads and is kept live by the gateway dispatcher; this
/// widget only holds UI state (composer text, in-flight flags, the locally
/// edited root).
class AccordThreadPane extends ConsumerStatefulWidget {
  const AccordThreadPane({
    super.key,
    required this.channelId,
    required this.spaceId,
    required this.root,
    required this.canManageMessages,
    required this.onClose,
    this.onUserTap,
    this.onUserContextMenu,
    this.dialog = false,
  });

  final String channelId;
  final String? spaceId;
  final AccordMessage root;
  final bool canManageMessages;
  final void Function(ThreadResult? result) onClose;
  final ValueChanged<AccordUser>? onUserTap;
  final void Function(AccordUser user, Offset? globalPosition)?
  onUserContextMenu;

  /// When true, renders with dialog chrome (close icon, shrink-wrapped); when
  /// false, fills the available area with a back arrow.
  final bool dialog;

  @override
  ConsumerState<AccordThreadPane> createState() => _AccordThreadPaneState();
}

class _AccordThreadPaneState extends ConsumerState<AccordThreadPane> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  late AccordMessage _root = widget.root;
  bool _sending = false;
  bool _closedForHiddenRoot = false;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  String? get _currentUserId => ref.readUserId();

  Future<void> _send() async {
    final raw = _input.text.trim();
    // Same conversion as the main composer — emoticons resolve on send so every
    // client stores and renders the identical glyph.
    final text =
        ref.read(settingsControllerProvider.select((s) => s.convertEmoticons))
        ? applyEmoticons(raw)
        : raw;
    if (text.isEmpty || _sending) return;
    final client = _client;
    if (client == null) return;
    // Clear up front rather than after the round-trip. The field is never
    // disabled (that would drop focus and the mobile keyboard for the whole
    // send), so it has to be free for the next reply straight away; the text
    // comes back if the send fails.
    _input.clear();
    setState(() => _sending = true);
    final ok = await ref
        .read(
          threadRepliesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
            widget.root.id,
          ).notifier,
        )
        .send(client, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      // Hand the reply back so it can be retried instead of retyped.
      restoreFailedSend(_input, text);
      showInfoSnack(context, 'Failed to send reply');
    }
  }

  void _close() {
    widget.onClose(
      identical(_root, widget.root) ? null : ThreadResult.edited(_root),
    );
  }

  Future<void> _editRoot() async {
    final updated = await showPostEditor(
      context,
      channelId: widget.channelId,
      post: _root,
      withTitle: true,
    );
    if (updated != null && mounted) setState(() => _root = updated);
  }

  Future<void> _deleteRoot() async {
    final client = _client;
    if (client == null) return;
    final confirmed = await confirmDeletePost(context, isPost: true);
    if (confirmed != true) return;
    final result = await client.messages.delete(widget.channelId, _root.id);
    if (!mounted) return;
    // A rejected delete used to close nothing and say nothing, so the post
    // looked like it had simply refused to go (#306).
    if (!result.ok) {
      showErrorSnack(context, result, prefix: 'Failed to delete post');
      return;
    }
    widget.onClose(const ThreadResult.deleted());
  }

  String _title() {
    final title = _root.title;
    if (title is String && title.isNotEmpty) return title;
    return 'Thread';
  }

  /// Offers two share links for this post: a `daccord://` deep link that opens
  /// directly in a daccord client, and the public `/s/...` web URL that anyone
  /// (and search-engine crawlers) can open.
  void _showShareMenu([Offset? position]) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;

    final entries = <AccordMenuEntry>[
      AccordMenuEntry(
        label: 'Share with those who have the app',
        icon: Icons.rocket_launch_outlined,
        onSelected: () => _copyShareLink(
          'daccord://navigate/$spaceId/${widget.channelId}?msg=${_root.id}',
          'App link copied to clipboard',
        ),
      ),
    ];

    AccordSpace? space;
    for (final s
        in ref.read(spacesControllerProvider) ?? const <AccordSpace>[]) {
      if (s.id == spaceId) {
        space = s;
        break;
      }
    }
    final channels = ref.read(
      accordChannelsControllerProvider(
        ref.readActiveServerKey() ?? '',
        spaceId,
      ),
    );
    AccordChannel? channel;
    for (final c in channels ?? const <AccordChannel>[]) {
      if (c.id == widget.channelId) {
        channel = c;
        break;
      }
    }
    final baseUrl = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.server.baseUrl : null,
      ),
    );
    final slug = space?.slug;
    final channelName = channel?.name;
    if (baseUrl != null &&
        slug != null &&
        slug.isNotEmpty &&
        channelName != null &&
        channelName.isNotEmpty) {
      final webLink =
          '$baseUrl/s/${Uri.encodeComponent(slug)}'
          '/${Uri.encodeComponent(channelName)}'
          '/${Uri.encodeComponent(_root.id)}';
      entries.add(
        AccordMenuEntry(
          label: 'Share with the internet',
          icon: Icons.public,
          onSelected: () =>
              _copyShareLink(webLink, 'Public link copied to clipboard'),
        ),
      );
    }

    showAccordContextMenu(
      context,
      entries: entries,
      globalPosition: position,
      title: 'Share post',
    );
  }

  void _copyShareLink(String link, String message) {
    Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final loadedReplies = ref.watch(
      threadRepliesControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.channelId,
        widget.root.id,
      ),
    );
    // Reported replies and blocked authors are filtered here as they are in the
    // message pane — a hide made in one surface applies in all of them (#290).
    final visibility = ref.watchMessageVisibility();
    final replies = loadedReplies == null
        ? null
        : visibility.filter(loadedReplies);
    // The root isn't in [replies] to filter, but the same promise applies to
    // it: if reporting it (or blocking its author) just hid it, follow the
    // pane's behavior and close rather than leave it the one message the
    // filter didn't reach (#290).
    if (!visibility.shows(_root) && !_closedForHiddenRoot) {
      _closedForHiddenRoot = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onClose(null);
      });
    }
    final currentUserId = _currentUserId;
    final dialog = widget.dialog;
    // Index 0 is the root post, 1 the divider, 2 the loading/empty placeholder
    // or the first reply — lazily built so a long thread only materializes the
    // rows on screen.
    final replyCount = (replies == null || replies.isEmpty)
        ? 1
        : replies.length;
    final childIndexByMessageId = <String, int>{
      _root.id: 0,
      if (replies != null)
        for (var i = 0; i < replies.length; i++) replies[i].id: i + 2,
    };
    final list = ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 2 + replyCount,
      // Moves a keyed row to its new index instead of rebuilding it there, so
      // a row's State (and any dialog it has open) survives replies being
      // inserted or removed above it. See #198.
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        return childIndexByMessageId[key.value];
      },
      itemBuilder: (context, index) {
        if (index == 0) {
          return _MessageLine(
            // Keyed by message id so a row's State (and any dialog it has
            // open) follows its message rather than its list slot as replies
            // arrive or are deleted. See #198.
            key: ValueKey(_root.id),
            message: _root,
            isRoot: true,
            spaceId: widget.spaceId,
            channelId: widget.channelId,
            rootId: widget.root.id,
            isOwn: currentUserId != null && _root.authorId == currentUserId,
            canManageMessages: widget.canManageMessages,
            onUserTap: widget.onUserTap,
            onUserContextMenu: widget.onUserContextMenu,
            onEdit: _editRoot,
            onDelete: _deleteRoot,
          );
        }
        if (index == 1) return const Divider(height: 16);
        if (replies == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: LoadingView(),
          );
        }
        if (replies.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text('No replies yet', style: theme.textTheme.bodySmall),
            ),
          );
        }
        final reply = replies[index - 2];
        return _MessageLine(
          key: ValueKey(reply.id),
          message: reply,
          isRoot: false,
          spaceId: widget.spaceId,
          channelId: widget.channelId,
          rootId: widget.root.id,
          isOwn: currentUserId != null && reply.authorId == currentUserId,
          canManageMessages: widget.canManageMessages,
          onUserTap: widget.onUserTap,
          onUserContextMenu: widget.onUserContextMenu,
        );
      },
    );

    final content = Column(
      mainAxisSize: dialog ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: dialog
              ? const EdgeInsets.fromLTRB(16, 16, 8, 8)
              : const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: dialog ? 'Close' : 'Back',
                onPressed: _close,
                icon: Icon(dialog ? Icons.close : Icons.arrow_back, size: 18),
              ),
              const SizedBox(width: 4),
              Icon(Icons.forum, size: 18, color: colors.dirtyWhite),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title(),
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.spaceId != null)
                IconButton(
                  tooltip: 'Share',
                  onPressed: _showShareMenu,
                  icon: Icon(
                    Icons.ios_share,
                    size: 18,
                    color: colors.dirtyWhite,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        dialog ? Flexible(child: list) : Expanded(child: list),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  // Never disabled while sending: a disabled TextField gives up
                  // focus (and the mobile keyboard) for the whole round-trip.
                  // The send button and the guard in _send() stop double-sends.
                  minLines: 1,
                  maxLines: 4,
                  // Without an explicit action a multiline field defaults to
                  // TextInputAction.newline, so Enter only inserts a line break
                  // and never reaches onSubmitted. Matches the main composer.
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Reply to thread',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    // EditableText unfocuses on a `send` action just before
                    // onSubmitted runs; the field is enabled, so asking for
                    // focus straight back lands in the same frame.
                    _inputFocus.requestFocus();
                    _send();
                  },
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: Icon(Icons.send, size: 20, color: colors.dirtyWhite),
              ),
            ],
          ),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      // Intercept back-nav and (in dialog mode) scrim taps so any root edit is
      // surfaced to the caller, matching the close/back button path.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _close();
      },
      child: content,
    );
  }
}

/// An author + content row used inside the thread view, with an actions menu
/// (edit/delete/copy) mirroring the main message view. The root post and
/// replies share this; [isRoot] only changes the edit affordance (title-aware)
/// and routes edit/delete to the [onEdit]/[onDelete] callbacks instead of the
/// replies controller. Reply mutations go straight to
/// [ThreadRepliesController] (addressed by [channelId] + [rootId]).
class _MessageLine extends ConsumerStatefulWidget {
  const _MessageLine({
    super.key,
    required this.message,
    required this.isRoot,
    required this.spaceId,
    required this.channelId,
    required this.rootId,
    required this.isOwn,
    required this.canManageMessages,
    this.onUserTap,
    this.onUserContextMenu,
    this.onEdit,
    this.onDelete,
  });

  final AccordMessage message;
  final bool isRoot;
  final String? spaceId;
  final String channelId;

  /// The thread's root message id — the replies-controller family key.
  final String rootId;
  final bool isOwn;
  final bool canManageMessages;
  final ValueChanged<AccordUser>? onUserTap;
  final void Function(AccordUser user, Offset? globalPosition)?
  onUserContextMenu;

  /// Root-only handlers (the root edits its title and pops on delete).
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  ConsumerState<_MessageLine> createState() => _MessageLineState();
}

class _MessageLineState extends ConsumerState<_MessageLine> {
  bool _hovered = false;
  bool _busy = false;

  /// The message this row is currently bound to. Only safe to read
  /// synchronously — never after an `await`, since the State can be re-bound to
  /// a different reply while a dialog is open (see #198). Async handlers take
  /// the message they captured up front instead.
  AccordMessage get _message => widget.message;

  AccordClient? get _client => ref.accordClient;

  ThreadRepliesController get _replies => ref.read(
    threadRepliesControllerProvider(
      ref.readActiveServerKey() ?? '',
      widget.channelId,
      widget.rootId,
    ).notifier,
  );

  bool get _canDelete => widget.isOwn || widget.canManageMessages;

  String get _time {
    final dt = DateTime.tryParse(_message.timestamp);
    if (dt == null) return '';
    return messageTimeString(dt.toLocal());
  }

  Future<void> _edit(AccordMessage message) async {
    if (widget.isRoot) {
      widget.onEdit?.call();
      return;
    }
    final updated = await showPostEditor(
      context,
      channelId: widget.channelId,
      post: message,
      withTitle: false,
    );
    if (updated != null && mounted) _replies.updateReply(updated);
  }

  Future<void> _delete(String messageId) async {
    if (widget.isRoot) {
      widget.onDelete?.call();
      return;
    }
    final client = _client;
    if (client == null || _busy) return;
    final confirmed = await confirmDeletePost(context, isPost: false);
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await _replies.delete(client, messageId);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// [message] is captured when the menu opens: its entries only run once the
  /// menu has closed, by which point this row may be bound to another reply.
  void _showMenu(AccordMessage message, [Offset? position]) {
    final authorId = message.authorId;
    final member = widget.spaceId == null
        ? null
        : ref.read(
            accordMembersControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.spaceId!,
            ),
          )?[authorId];
    final user = ref.read(
      accordUsersControllerProvider(ref.readActiveServerKey() ?? ''),
    )[authorId];
    final name = accordAuthorNameOf(authorId, member: member, user: user);
    final entries = [
      ...buildMessageActionEntries(
        content: message.content,
        canEdit: widget.isOwn,
        canDelete: _canDelete,
        onEdit: () => _edit(message),
        onDelete: () => _delete(message.id),
      ),
      // A reply is a message like any other: it can be flagged here too, so no
      // message surface is left without the action (#290).
      if (!widget.isOwn)
        AccordMenuEntry(
          label: 'Report',
          icon: Icons.flag_outlined,
          onSelected: () => showReportDialog(
            context,
            spaceId: widget.spaceId,
            targetType: 'message',
            targetId: message.id,
            channelId: widget.channelId,
            reportedUserId: authorId.isEmpty ? null : authorId,
            reportedName: name,
          ),
        ),
    ];
    if (entries.isEmpty) return;
    showAccordContextMenu(
      context,
      entries: entries,
      globalPosition: position,
      title: name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Captured once so the callbacks handed out by this build target the
    // message that was rendered.
    final message = _message;
    // Per-row identity lookups, scoped to this author: watching just the one
    // cache entry means a change to an unrelated member/user doesn't rebuild
    // every row in the thread.
    final authorId = message.authorId;
    final member = widget.spaceId == null
        ? null
        : ref.watch(
            accordMembersControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.spaceId!,
            ).select((m) => m?[authorId]),
          );
    final user = ref.watch(
      accordUsersControllerProvider(
        ref.readActiveServerKey() ?? '',
      ).select((m) => m[authorId]),
    );
    final ensure = ref
        .read(
          accordUsersControllerProvider(
            ref.readActiveServerKey() ?? '',
          ).notifier,
        )
        .ensure;
    final cdnUrl = ref.watchCdnUrl();
    final name = accordAuthorNameOf(
      authorId,
      member: member,
      user: user,
      ensure: ensure,
    );
    final avatarUrl = accordAuthorAvatarUrlOf(
      member: member,
      user: user,
      cdnUrl: cdnUrl,
    );
    final avatarBg = accordAvatarColor(member?.user ?? user, authorId);
    final initial = accordInitial(name);
    final author = member?.user ?? user;
    final userActionsEnabled =
        author != null &&
        (widget.onUserTap != null || widget.onUserContextMenu != null);
    void openUser() {
      if (author != null) widget.onUserTap?.call(author);
    }

    void openUserMenu(Offset? position) {
      if (author != null) widget.onUserContextMenu?.call(author, position);
    }

    Widget avatar = AccordMemberAvatar(
      avatarUrl: avatarUrl,
      initial: initial,
      backgroundColor: avatarBg,
      radius: 16,
    );
    if (userActionsEnabled) {
      avatar = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onUserTap == null ? null : openUser,
          onLongPressStart: widget.onUserContextMenu == null
              ? null
              : (details) => openUserMenu(details.globalPosition),
          onSecondaryTapUp: widget.onUserContextMenu == null
              ? null
              : (details) => openUserMenu(details.globalPosition),
          child: avatar,
        ),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // Opaque so a long-press anywhere on the row (not just the avatar)
        // opens the menu; plain-text content is a transparent RichText that
        // wouldn't register a hit under the default `deferToChild`.
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => _showMenu(message, d.globalPosition),
        onSecondaryTapUp: (d) => _showMenu(message, d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MessageAuthorHeader(
                      name: name,
                      ellipsizeName: true,
                      onNameTap: userActionsEnabled && widget.onUserTap != null
                          ? openUser
                          : null,
                      onNameLongPressStart:
                          userActionsEnabled && widget.onUserContextMenu != null
                          ? (details) => openUserMenu(details.globalPosition)
                          : null,
                      onNameSecondaryTapUp:
                          userActionsEnabled && widget.onUserContextMenu != null
                          ? (details) => openUserMenu(details.globalPosition)
                          : null,
                      time: _time,
                      smallTime: true,
                      edited: message.editedAt != null,
                    ),
                    const SizedBox(height: 2),
                    if (message.content.isNotEmpty)
                      AccordMessageContent(
                        content: message.content,
                        spaceId: widget.spaceId,
                      ),
                  ],
                ),
              ),
              // Shown for someone else's reply too — that menu now carries the
              // Report action, which must not be long-press-only (#290).
              if (_canDelete || !widget.isOwn)
                Opacity(
                  opacity: _hovered ? 1 : 0,
                  child: IconButton(
                    tooltip: 'Actions',
                    onPressed: _busy ? null : () => _showMenu(message),
                    icon: Icon(Icons.more_horiz, size: 18, color: colors.gray),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirms deletion of a post or reply. Shared by the forum index and the
/// thread view so the wording stays consistent.
Future<bool?> confirmDeletePost(BuildContext context, {required bool isPost}) {
  final what = isPost ? 'post' : 'reply';
  return showConfirmDialog(
    context,
    title: 'Delete $what',
    message: 'This $what will be permanently deleted.',
    confirmLabel: 'Delete',
    danger: true,
  );
}

/// Opens an editor for an existing post/reply and PATCHes it. With [withTitle]
/// the title field is shown (forum root posts); without, only the body (replies
/// and plain messages). Returns the updated [AccordMessage], or null if
/// cancelled or the request failed.
Future<AccordMessage?> showPostEditor(
  BuildContext context, {
  required String channelId,
  required AccordMessage post,
  required bool withTitle,
}) {
  return showDialog<AccordMessage>(
    context: context,
    builder: (dialogContext) => PostComposerDialog(
      title: withTitle ? 'Edit post' : 'Edit reply',
      submitLabel: 'Save',
      bodyLabel: withTitle ? 'Body' : 'Message',
      initialTitle: withTitle
          ? (post.title is String ? post.title as String : '')
          : null,
      initialBody: post.content,
      onSubmit: (client, title, body) async {
        final result = await client.messages.edit(channelId, post.id, {
          if (withTitle) 'title': title,
          'content': body,
        });
        if (!dialogContext.mounted) return null;
        final message = result.data;
        if (result.ok && message is AccordMessage) {
          Navigator.of(dialogContext).pop(message);
          return null;
        }
        return 'Failed to save changes';
      },
    ),
  );
}
