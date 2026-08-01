import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/messaging/controllers/forum_posts.dart';
import 'package:bonfire/features/messaging/views/post_composer_dialog.dart';
import 'package:bonfire/features/messaging/views/thread_view.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the forum index orders its posts.
enum ForumSort { latestActivity, newest, mostReplies }

extension on ForumSort {
  String get label => switch (this) {
        ForumSort.latestActivity => 'Latest activity',
        ForumSort.newest => 'Newest',
        ForumSort.mostReplies => 'Most replies',
      };
}

/// A forum channel's body: a traditional forum board of top-level posts (each a
/// thread root) with a sort control and a "New post" action. Each row shows the
/// author, created/last-activity times, reply count, and pinned badge, and
/// exposes per-post actions (reply / edit / pin / delete). Replaces the message
/// stream for `forum`-type channels.
///
/// The post list itself lives in [ForumPostsController] (keyed by channel),
/// which self-loads and is kept live by the gateway dispatcher; this widget
/// only holds UI state (sort order, the inline-open post).
class ForumChannelView extends ConsumerStatefulWidget {
  const ForumChannelView({
    super.key,
    required this.channelId,
    required this.spaceId,
    required this.canPost,
    this.canManageMessages = false,
    this.currentUserId,
  });

  final String channelId;
  final String? spaceId;
  final bool canPost;

  /// Whether the current user can manage others' posts (pin, delete).
  final bool canManageMessages;

  /// The signed-in user's id, used to gate edit/delete of own posts.
  final String? currentUserId;

  @override
  ConsumerState<ForumChannelView> createState() => _ForumChannelViewState();
}

class _ForumChannelViewState extends ConsumerState<ForumChannelView> {
  ForumSort _sort = ForumSort.latestActivity;

  /// The post whose thread is open inline in the message area, or null when the
  /// board is showing. Opening a post swaps the board for [AccordThreadPane]
  /// rather than a modal dialog.
  AccordMessage? _openPostMessage;

  @override
  void didUpdateWidget(ForumChannelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) {
      // The post list follows the channel automatically (the controller is a
      // per-channel family); only the inline-open thread is local UI state.
      _openPostMessage = null;
    }
  }

  AccordClient? get _client => ref.accordClient;

  ForumPostsController get _postsNotifier =>
      ref.read(forumPostsControllerProvider(widget.channelId).notifier);

  Future<void> _reload() async {
    final client = _client;
    if (client == null) return;
    await _postsNotifier.reload(client);
  }

  /// Posts ordered by the active sort. Pinned posts always float to the top.
  List<AccordMessage> _sorted(List<AccordMessage> posts) {
    final sorted = [...posts];
    int byNewest(AccordMessage a, AccordMessage b) =>
        _instant(b.timestamp).compareTo(_instant(a.timestamp));
    int cmp(AccordMessage a, AccordMessage b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      switch (_sort) {
        case ForumSort.newest:
          return byNewest(a, b);
        case ForumSort.mostReplies:
          final c = b.replyCount.compareTo(a.replyCount);
          return c != 0 ? c : byNewest(a, b);
        case ForumSort.latestActivity:
          return _lastActivity(b).compareTo(_lastActivity(a));
      }
    }

    sorted.sort(cmp);
    return sorted;
  }

  Future<void> _newPost() async {
    final created = await showDialog<AccordMessage>(
      context: context,
      builder: (dialogContext) => PostComposerDialog(
        title: 'New post',
        submitLabel: 'Post',
        bodyLabel: 'Body (optional)',
        initialTitle: '',
        autofocusTitle: true,
        onSubmit: (client, title, body) async {
          final result = await client.messages.create(widget.channelId, {
            'title': title,
            if (body.isNotEmpty) 'content': body,
          });
          if (!dialogContext.mounted) return null;
          final message = result.data;
          if (result.ok && message is AccordMessage) {
            Navigator.of(dialogContext).pop(message);
            return null;
          }
          return 'Failed to create post';
        },
      ),
    );
    // Optimistic add; the gateway echo is deduped by [ForumPostsController.addPost].
    if (created != null && mounted) _postsNotifier.addPost(created);
  }

  void _openPost(AccordMessage post) {
    setState(() => _openPostMessage = post);
  }

  /// Returns from an inline thread to the board, applying any root edit/delete
  /// the thread surfaced so the row reflects it without a full reload.
  void _onThreadClosed(AccordMessage post, ThreadResult? result) {
    if (!mounted) return;
    setState(() => _openPostMessage = null);
    if (result == null) return;
    if (result.deleted) {
      _postsNotifier.removePost(post.id);
    } else if (result.root != null) {
      _postsNotifier.updatePost(result.root!);
    }
  }

  bool _isOwn(AccordMessage post) =>
      widget.currentUserId != null && post.authorId == widget.currentUserId;

  Future<void> _editPost(AccordMessage post) async {
    final updated = await showPostEditor(
      context,
      channelId: widget.channelId,
      post: post,
      withTitle: true,
    );
    if (updated != null && mounted) _postsNotifier.updatePost(updated);
  }

  Future<void> _deletePost(AccordMessage post) async {
    final client = _client;
    if (client == null) return;
    final confirmed = await confirmDeletePost(context, isPost: true);
    if (confirmed != true || !mounted) return;
    await _postsNotifier.delete(client, post.id);
  }

  Future<void> _togglePin(AccordMessage post) async {
    final client = _client;
    if (client == null) return;
    await _postsNotifier.togglePin(client, post);
  }

  void _showPostMenu(AccordMessage post, [Offset? position]) {
    final isOwn = _isOwn(post);
    final entries = <AccordMenuEntry>[
      AccordMenuEntry(
        label: 'Open',
        icon: Icons.open_in_new,
        onSelected: () => _openPost(post),
      ),
      if (isOwn)
        AccordMenuEntry(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onSelected: () => _editPost(post),
        ),
      if (widget.canManageMessages)
        AccordMenuEntry(
          label: post.pinned ? 'Unpin' : 'Pin',
          icon: post.pinned ? Icons.push_pin_outlined : Icons.push_pin,
          onSelected: () => _togglePin(post),
        ),
      if (isOwn || widget.canManageMessages)
        AccordMenuEntry(
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: () => _deletePost(post),
        ),
    ];
    showAccordContextMenu(context,
        entries: entries,
        globalPosition: position,
        title: resolveForumPostTitle(post));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final openPost = _openPostMessage;
    if (openPost != null) {
      return AccordThreadPane(
        key: ValueKey(openPost.id),
        channelId: widget.channelId,
        spaceId: widget.spaceId,
        root: openPost,
        canManageMessages: widget.canManageMessages,
        onClose: (result) => _onThreadClosed(openPost, result),
      );
    }
    final posts = ref.watch(forumPostsControllerProvider(widget.channelId));
    // Compute once and capture in the itemBuilder closure so the sort is not
    // re-run O(n) times as items scroll into view.
    final sorted = posts == null ? const <AccordMessage>[] : _sorted(posts);
    return Stack(
      children: [
        Column(
          children: [
            _SortBar(
              sort: _sort,
              onChanged: (s) => setState(() => _sort = s),
              count: posts?.length ?? 0,
            ),
            Expanded(
              child: posts == null
                  ? const LoadingView()
                  : posts.isEmpty
                      ? Center(
                          child: Text('No posts yet',
                              style: theme.textTheme.bodyMedium))
                      : RefreshIndicator(
                          onRefresh: _reload,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                            itemCount: sorted.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final post = sorted[index];
                              return _PostRow(
                                post: post,
                                colors: colors,
                                spaceId: widget.spaceId,
                                onTap: () => _openPost(post),
                                onMenu: (pos) => _showPostMenu(post, pos),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
        if (widget.canPost)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _newPost,
              icon: const Icon(Icons.add),
              label: const Text('New post'),
            ),
          ),
      ],
    );
  }
}

/// The sort selector + post count strip above the board.
class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.sort,
    required this.onChanged,
    required this.count,
  });

  final ForumSort sort;
  final ValueChanged<ForumSort> onChanged;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Text('$count ${count == 1 ? 'post' : 'posts'}',
              style: theme.textTheme.labelMedium!
                  .copyWith(color: colors.gray)),
          const Spacer(),
          Icon(Icons.sort, size: 16, color: colors.gray),
          const SizedBox(width: 6),
          PopupMenuButton<ForumSort>(
            initialValue: sort,
            tooltip: 'Sort posts',
            onSelected: onChanged,
            itemBuilder: (context) => [
              for (final s in ForumSort.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sort.label, style: theme.textTheme.labelMedium),
                Icon(Icons.arrow_drop_down, size: 18, color: colors.gray),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single forum post row: avatar, title (+ pinned badge), author and
/// created/last-activity metadata, reply count, and an overflow menu. Resolves
/// the author identity itself with per-author `select` watches so a change to
/// an unrelated member/user doesn't rebuild every row on the board.
class _PostRow extends ConsumerWidget {
  const _PostRow({
    required this.post,
    required this.colors,
    required this.spaceId,
    required this.onTap,
    required this.onMenu,
  });

  final AccordMessage post;
  final BonfireThemeExtension colors;
  final String? spaceId;
  final VoidCallback onTap;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authorId = post.authorId;
    final member = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(spaceId!)
            .select((m) => m?[authorId]));
    final user =
        ref.watch(accordUsersControllerProvider.select((m) => m[authorId]));
    final ensure = ref.read(accordUsersControllerProvider.notifier).ensure;
    final cdnUrl = ref.watchCdnUrl();
    final author =
        accordAuthorNameOf(authorId, member: member, user: user, ensure: ensure);
    final avatarUrl =
        accordAuthorAvatarUrlOf(member: member, user: user, cdnUrl: cdnUrl);
    final avatarBg = accordAvatarColor(member?.user ?? user, authorId);
    final initial = accordInitial(author);
    final replies = post.replyCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: GestureDetector(
        // Opaque so the whole card is hit-testable for long-press, matching
        // the message pane and thread rows.
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => onMenu(d.globalPosition),
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccordMemberAvatar(
                  avatarUrl: avatarUrl,
                  initial: initial,
                  radius: 20,
                  backgroundColor: avatarBg,
                  initialStyle: theme.textTheme.titleMedium,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (post.pinned) ...[
                            Icon(Icons.push_pin,
                                size: 14, color: colors.primary),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(resolveForumPostTitle(post),
                                style: theme.textTheme.titleSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(_metaLine(author),
                          style: theme.textTheme.labelMedium!
                              .copyWith(color: colors.gray),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (post.content.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(post.content,
                            style: theme.textTheme.bodySmall!
                                .copyWith(color: colors.gray),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Post actions',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final box = context.findRenderObject() as RenderBox?;
                        final pos = box == null
                            ? Offset.zero
                            : box.localToGlobal(box.size.center(Offset.zero));
                        onMenu(pos);
                      },
                      icon: Icon(Icons.more_horiz,
                          size: 18, color: colors.gray),
                    ),
                    if (replies > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_outlined,
                                size: 14, color: colors.gray),
                            const SizedBox(width: 4),
                            Text('$replies',
                                style: theme.textTheme.labelMedium!
                                    .copyWith(color: colors.gray)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _metaLine(String author) {
    final created = _relativeOrDate(post.timestamp);
    final parts = <String>['by $author'];
    if (created.isNotEmpty) parts.add(created);
    final last = _lastReplyText(post);
    if (last != null) parts.add(last);
    return parts.join(' · ');
  }
}

/// A post's display title: its title if set, else the first line of its body,
/// else a neutral fallback (never the raw "(untitled)" leak).
String resolveForumPostTitle(AccordMessage post) {
  final title = post.title;
  if (title is String && title.trim().isNotEmpty) return title.trim();
  final firstLine = post.content.split('\n').firstWhere(
        (l) => l.trim().isNotEmpty,
        orElse: () => '',
      );
  if (firstLine.trim().isNotEmpty) return firstLine.trim();
  return 'Untitled post';
}

/// Parses an ISO timestamp to a comparable instant, or epoch for unparseable
/// values (so they sort last under a descending order).
DateTime _instant(String iso) =>
    DateTime.tryParse(iso)?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// A post's last-activity instant: its newest reply, falling back to creation.
DateTime _lastActivity(AccordMessage post) {
  final last = post.lastReplyAt;
  if (last is String && last.isNotEmpty) {
    final dt = DateTime.tryParse(last);
    if (dt != null) return dt.toUtc();
  }
  return _instant(post.timestamp);
}

/// A "last reply ..." label for a post with replies, else null.
String? _lastReplyText(AccordMessage post) {
  if (post.replyCount <= 0) return null;
  final last = post.lastReplyAt;
  if (last is! String || last.isEmpty) return null;
  final when = _relativeOrDate(last);
  return when.isEmpty ? null : 'last reply $when';
}

/// A short date-aware label for an ISO timestamp (reusing the message-time
/// formatter), or empty when unparseable.
String _relativeOrDate(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  return messageTimeString(dt.toLocal());
}
