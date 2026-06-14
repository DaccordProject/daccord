import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/messaging/components/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A forum channel's body: a list of top-level posts (each a thread root) with
/// a "New post" action. Replaces the message stream for `forum`-type channels.
class ForumChannelView extends ConsumerStatefulWidget {
  const ForumChannelView({
    super.key,
    required this.channelId,
    required this.spaceId,
    required this.canPost,
  });

  final String channelId;
  final String? spaceId;
  final bool canPost;

  @override
  ConsumerState<ForumChannelView> createState() => _ForumChannelViewState();
}

class _ForumChannelViewState extends ConsumerState<ForumChannelView> {
  List<AccordMessage>? _posts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ForumChannelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) {
      _posts = null;
      _load();
    }
  }

  AccordClient? get _client => ref.accordClient;

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.messages.listPosts(widget.channelId);
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _posts = result.ok && data is List
          ? data.whereType<AccordMessage>().toList()
          : const [];
    });
  }

  Future<void> _newPost() async {
    final created = await showDialog<AccordMessage>(
      context: context,
      builder: (_) => _NewPostDialog(channelId: widget.channelId),
    );
    if (created != null && mounted) {
      setState(() => _posts = [created, ...?_posts]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posts = _posts;
    final members = widget.spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(widget.spaceId!));
    final users = ref.watch(accordUsersControllerProvider);
    final ensureUser =
        ref.read(accordUsersControllerProvider.notifier).ensure;
    return Stack(
      children: [
        if (posts == null)
          const Center(child: CircularProgressIndicator())
        else if (posts.isEmpty)
          Center(
              child: Text('No posts yet', style: theme.textTheme.bodyMedium))
        else
          ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: posts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final post = posts[index];
              final title = post.title;
              final titleText =
                  title is String && title.isNotEmpty ? title : '(untitled)';
              final author = accordAuthorName(post.authorId,
                  members: members, users: users, ensure: ensureUser);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(titleText, style: theme.textTheme.titleSmall),
                  subtitle: Text(
                    post.content.isEmpty ? 'by $author' : post.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: post.replyCount > 0
                      ? Text('${post.replyCount}',
                          style: theme.textTheme.labelMedium)
                      : null,
                  onTap: () => showAccordThread(
                    context,
                    channelId: widget.channelId,
                    spaceId: widget.spaceId,
                    root: post,
                  ),
                ),
              );
            },
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

class _NewPostDialog extends ConsumerStatefulWidget {
  const _NewPostDialog({required this.channelId});

  final String channelId;

  @override
  ConsumerState<_NewPostDialog> createState() => _NewPostDialogState();
}

class _NewPostDialogState extends ConsumerState<_NewPostDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
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
    if (title.isEmpty) {
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
    final result = await client.messages.create(widget.channelId, {
      'title': title,
      if (body.isNotEmpty) 'content': body,
    });
    if (!mounted) return;
    final message = result.data;
    if (result.ok && message is AccordMessage) {
      Navigator.of(context).pop(message);
    } else {
      setState(() {
        _busy = false;
        _error = 'Failed to create post';
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
              Text('New post', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                enabled: !_busy,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Body (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
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
                    child: const Text('Post'),
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
