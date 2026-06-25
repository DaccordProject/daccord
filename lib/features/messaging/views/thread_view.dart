import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/spaces/controllers/space.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_content.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/context_menu.dart';
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
  const ThreadResult.deleted()
      : root = null,
        deleted = true;

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
class AccordThreadPane extends ConsumerStatefulWidget {
  const AccordThreadPane({
    super.key,
    required this.channelId,
    required this.spaceId,
    required this.root,
    required this.canManageMessages,
    required this.onClose,
    this.dialog = false,
  });

  final String channelId;
  final String? spaceId;
  final AccordMessage root;
  final bool canManageMessages;
  final void Function(ThreadResult? result) onClose;

  /// When true, renders with dialog chrome (close icon, shrink-wrapped); when
  /// false, fills the available area with a back arrow.
  final bool dialog;

  @override
  ConsumerState<AccordThreadPane> createState() => _AccordThreadPaneState();
}

class _AccordThreadPaneState extends ConsumerState<AccordThreadPane> {
  final TextEditingController _input = TextEditingController();
  late AccordMessage _root = widget.root;
  List<AccordMessage>? _replies;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  String? get _currentUserId => ref.readUserId();

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result =
        await client.messages.listThread(widget.channelId, _root.id);
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _replies = result.ok && data is List
          ? data
              .whereType<AccordMessage>()
              .where((m) => m.id != _root.id)
              .toList()
          : const [];
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final client = _client;
    if (client == null) return;
    setState(() => _sending = true);
    final result = await client.messages.create(widget.channelId, {
      'content': text,
      'thread_id': _root.id,
    });
    if (!mounted) return;
    setState(() => _sending = false);
    final message = result.data;
    if (result.ok && message is AccordMessage) {
      _input.clear();
      setState(() => _replies = [...?_replies, message]);
    }
  }

  /// Removes a deleted reply from the list. The root is handled separately
  /// (it pops the view) since it can't disappear while its replies remain.
  void _onReplyChanged(AccordMessage updated, {required bool deleted}) {
    setState(() {
      final list = [...?_replies];
      final index = list.indexWhere((m) => m.id == updated.id);
      if (index < 0) return;
      if (deleted) {
        list.removeAt(index);
      } else {
        list[index] = updated;
      }
      _replies = list;
    });
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
    if (!mounted || !result.ok) return;
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

    final space = ref.read(spaceControllerProvider(spaceId));
    final channels = ref.read(accordChannelsControllerProvider(spaceId));
    AccordChannel? channel;
    for (final c in channels ?? const <AccordChannel>[]) {
      if (c.id == widget.channelId) {
        channel = c;
        break;
      }
    }
    final baseUrl = ref.read(accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.server.baseUrl : null));
    final slug = space?.slug;
    final channelName = channel?.name;
    if (baseUrl != null &&
        slug != null &&
        slug.isNotEmpty &&
        channelName != null &&
        channelName.isNotEmpty) {
      final webLink = '$baseUrl/s/${Uri.encodeComponent(slug)}'
          '/${Uri.encodeComponent(channelName)}'
          '/${Uri.encodeComponent(_root.id)}';
      entries.add(AccordMenuEntry(
        label: 'Share with the internet',
        icon: Icons.public,
        onSelected: () =>
            _copyShareLink(webLink, 'Public link copied to clipboard'),
      ));
    }

    showAccordContextMenu(context,
        entries: entries, globalPosition: position, title: 'Share post');
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
    final members = widget.spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(widget.spaceId!));
    final users = ref.watch(accordUsersControllerProvider);
    final ensureUser =
        ref.read(accordUsersControllerProvider.notifier).ensure;
    final cdnUrl = ref.watchCdnUrl();
    final replies = _replies;
    final currentUserId = _currentUserId;
    final dialog = widget.dialog;
    final list = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _MessageLine(
          message: _root,
          isRoot: true,
          members: members,
          users: users,
          ensure: ensureUser,
          cdnUrl: cdnUrl,
          spaceId: widget.spaceId,
          channelId: widget.channelId,
          isOwn: currentUserId != null && _root.authorId == currentUserId,
          canManageMessages: widget.canManageMessages,
          onEdit: _editRoot,
          onDelete: _deleteRoot,
          onChanged: (_, {required deleted}) {},
        ),
        const Divider(height: 16),
        if (replies == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: LoadingView(),
          )
        else if (replies.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
                child: Text('No replies yet',
                    style: theme.textTheme.bodySmall)),
          )
        else
          for (final reply in replies)
            _MessageLine(
              message: reply,
              isRoot: false,
              members: members,
              users: users,
              ensure: ensureUser,
              cdnUrl: cdnUrl,
              spaceId: widget.spaceId,
              channelId: widget.channelId,
              isOwn: currentUserId != null && reply.authorId == currentUserId,
              canManageMessages: widget.canManageMessages,
              onChanged: _onReplyChanged,
            ),
      ],
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
                child: Text(_title(),
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis),
              ),
              if (widget.spaceId != null)
                IconButton(
                  tooltip: 'Share',
                  onPressed: _showShareMenu,
                  icon: Icon(Icons.ios_share,
                      size: 18, color: colors.dirtyWhite),
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
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Reply to thread',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _send(),
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
/// and is reported to the parent via [onEdit]/[onDelete] callbacks.
class _MessageLine extends ConsumerStatefulWidget {
  const _MessageLine({
    required this.message,
    required this.isRoot,
    required this.members,
    required this.users,
    required this.ensure,
    required this.cdnUrl,
    required this.spaceId,
    required this.channelId,
    required this.isOwn,
    required this.canManageMessages,
    required this.onChanged,
    this.onEdit,
    this.onDelete,
  });

  final AccordMessage message;
  final bool isRoot;
  final Map<String, AccordMember>? members;
  final Map<String, AccordUser> users;
  final void Function(String userId) ensure;
  final String? cdnUrl;
  final String? spaceId;
  final String channelId;
  final bool isOwn;
  final bool canManageMessages;

  /// Reports a reply edit (deleted: false) or removal (deleted: true) to the
  /// thread so it can update its list. Unused for the root.
  final void Function(AccordMessage updated, {required bool deleted}) onChanged;

  /// Root-only handlers (the root edits its title and pops on delete).
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  ConsumerState<_MessageLine> createState() => _MessageLineState();
}

class _MessageLineState extends ConsumerState<_MessageLine> {
  bool _hovered = false;
  bool _busy = false;

  AccordMessage get _message => widget.message;

  AccordClient? get _client => ref.accordClient;

  bool get _canDelete => widget.isOwn || widget.canManageMessages;

  String get _time {
    final dt = DateTime.tryParse(_message.timestamp);
    if (dt == null) return '';
    return messageTimeString(dt.toLocal());
  }

  Future<void> _edit() async {
    if (widget.isRoot) {
      widget.onEdit?.call();
      return;
    }
    final updated = await showPostEditor(
      context,
      channelId: widget.channelId,
      post: _message,
      withTitle: false,
    );
    if (updated != null) widget.onChanged(updated, deleted: false);
  }

  Future<void> _delete() async {
    if (widget.isRoot) {
      widget.onDelete?.call();
      return;
    }
    final client = _client;
    if (client == null || _busy) return;
    final confirmed = await confirmDeletePost(context, isPost: false);
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await client.messages.delete(widget.channelId, _message.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) widget.onChanged(_message, deleted: true);
  }

  void _showMenu([Offset? position]) {
    final name = accordAuthorName(_message.authorId,
        members: widget.members, users: widget.users, ensure: widget.ensure);
    final entries = <AccordMenuEntry>[
      if (_message.content.isNotEmpty)
        AccordMenuEntry(
          label: 'Copy text',
          icon: Icons.copy_outlined,
          onSelected: () =>
              Clipboard.setData(ClipboardData(text: _message.content)),
        ),
      if (widget.isOwn)
        AccordMenuEntry(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onSelected: _edit,
        ),
      if (_canDelete)
        AccordMenuEntry(
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: _delete,
        ),
    ];
    if (entries.isEmpty) return;
    showAccordContextMenu(context,
        entries: entries, globalPosition: position, title: name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final name = accordAuthorName(_message.authorId,
        members: widget.members, users: widget.users, ensure: widget.ensure);
    final avatarUrl = accordAuthorAvatarUrl(_message.authorId,
        members: widget.members, users: widget.users, cdnUrl: widget.cdnUrl);
    final avatarBg = accordAvatarColor(
      widget.members?[_message.authorId]?.user ??
          widget.users[_message.authorId],
      _message.authorId,
    );
    final initial = accordInitial(name);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onLongPressStart: (d) => _showMenu(d.globalPosition),
        onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccordMemberAvatar(
                avatarUrl: avatarUrl,
                initial: initial,
                backgroundColor: avatarBg,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text(_time,
                            style: theme.textTheme.labelSmall!
                                .copyWith(color: colors.gray)),
                        if (_message.editedAt != null) ...[
                          const SizedBox(width: 6),
                          Text('(edited)',
                              style: theme.textTheme.labelSmall!
                                  .copyWith(color: colors.gray)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (_message.content.isNotEmpty)
                      AccordMessageContent(
                          content: _message.content, spaceId: widget.spaceId),
                  ],
                ),
              ),
              if (_canDelete)
                Opacity(
                  opacity: _hovered ? 1 : 0,
                  child: IconButton(
                    tooltip: 'Actions',
                    onPressed: _busy ? null : () => _showMenu(),
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
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $what'),
      content: Text('This $what will be permanently deleted.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
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
    builder: (_) =>
        _PostEditorDialog(channelId: channelId, post: post, withTitle: withTitle),
  );
}

class _PostEditorDialog extends ConsumerStatefulWidget {
  const _PostEditorDialog({
    required this.channelId,
    required this.post,
    required this.withTitle,
  });

  final String channelId;
  final AccordMessage post;
  final bool withTitle;

  @override
  ConsumerState<_PostEditorDialog> createState() => _PostEditorDialogState();
}

class _PostEditorDialogState extends ConsumerState<_PostEditorDialog> {
  late final TextEditingController _title = TextEditingController(
      text: widget.post.title is String ? widget.post.title as String : '');
  late final TextEditingController _body =
      TextEditingController(text: widget.post.content);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (widget.withTitle && title.isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result =
        await client.messages.edit(widget.channelId, widget.post.id, {
      if (widget.withTitle) 'title': title,
      'content': body,
    });
    if (!mounted) return;
    final message = result.data;
    if (result.ok && message is AccordMessage) {
      Navigator.of(context).pop(message);
    } else {
      setState(() {
        _busy = false;
        _error = 'Failed to save changes';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.withTitle ? 'Edit post' : 'Edit reply',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              if (widget.withTitle) ...[
                TextField(
                  controller: _title,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _body,
                autofocus: !widget.withTitle,
                enabled: !_busy,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: widget.withTitle ? 'Body' : 'Message',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
