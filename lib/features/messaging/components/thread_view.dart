import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/components/box/accord_message_content.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a thread/forum-post view: the [root] message at the top, its replies
/// below, and a composer that posts replies into the thread (`thread_id`).
Future<void> showAccordThread(
  BuildContext context, {
  required String channelId,
  String? spaceId,
  required AccordMessage root,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _ThreadView(channelId: channelId, spaceId: spaceId, root: root),
  );
}

class _ThreadView extends ConsumerStatefulWidget {
  const _ThreadView({
    required this.channelId,
    required this.spaceId,
    required this.root,
  });

  final String channelId;
  final String? spaceId;
  final AccordMessage root;

  @override
  ConsumerState<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends ConsumerState<_ThreadView> {
  final TextEditingController _input = TextEditingController();
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

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result =
        await client.messages.listThread(widget.channelId, widget.root.id);
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _replies = result.ok && data is List
          ? data
              .whereType<AccordMessage>()
              .where((m) => m.id != widget.root.id)
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
      'thread_id': widget.root.id,
    });
    if (!mounted) return;
    setState(() => _sending = false);
    final message = result.data;
    if (result.ok && message is AccordMessage) {
      _input.clear();
      setState(() => _replies = [...?_replies, message]);
    }
  }

  String _title() {
    final title = widget.root.title;
    if (title is String && title.isNotEmpty) return title;
    return 'Thread';
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final members = widget.spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(widget.spaceId!));
    final replies = _replies;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.forum, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_title(),
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _MessageLine(message: widget.root, members: members),
                  const Divider(height: 16),
                  if (replies == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
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
                      _MessageLine(message: reply, members: members),
                ],
              ),
            ),
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
        ),
      ),
    );
  }
}

/// A compact author + content row used inside the thread view.
class _MessageLine extends StatelessWidget {
  const _MessageLine({required this.message, required this.members});

  final AccordMessage message;
  final Map<String, AccordMember>? members;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name =
        accordMemberName(members?[message.authorId], fallback: message.authorId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          AccordMessageContent(content: message.content),
        ],
      ),
    );
  }
}
