import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a dialog listing the channel's pinned messages. When [canManage] is
/// true each row offers an unpin action.
Future<void> showPinnedMessages(
  BuildContext context, {
  required String channelId,
  String? spaceId,
  required bool canManage,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PinnedMessagesDialog(
      channelId: channelId,
      spaceId: spaceId,
      canManage: canManage,
    ),
  );
}

class _PinnedMessagesDialog extends ConsumerStatefulWidget {
  const _PinnedMessagesDialog({
    required this.channelId,
    required this.spaceId,
    required this.canManage,
  });

  final String channelId;
  final String? spaceId;
  final bool canManage;

  @override
  ConsumerState<_PinnedMessagesDialog> createState() =>
      _PinnedMessagesDialogState();
}

class _PinnedMessagesDialogState extends ConsumerState<_PinnedMessagesDialog> {
  Future<List<AccordMessage>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AccordMessage>> _load() async {
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    if (client == null) return const [];
    final result = await client.messages.listPins(widget.channelId);
    final data = result.data;
    if (!result.ok || data is! List) return const [];
    return data.whereType<AccordMessage>().toList();
  }

  Future<void> _unpin(AccordMessage message) async {
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    if (client == null) return;
    await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .unpin(client, message.id);
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final members = widget.spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(widget.spaceId!));
    final users = ref.watch(accordUsersControllerProvider);
    final ensureUser =
        ref.read(accordUsersControllerProvider.notifier).ensure;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.push_pin, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Pinned messages',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<AccordMessage>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: LoadingView(),
                    );
                  }
                  final pins = snapshot.data ?? const <AccordMessage>[];
                  if (pins.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text('No pinned messages',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: pins.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final message = pins[index];
                      final name = accordAuthorName(message.authorId,
                          members: members,
                          users: users,
                          ensure: ensureUser);
                      return ListTile(
                        // Keyed by message id so rows track their message, not
                        // their slot, when the list reloads after an unpin
                        // (see #198). The unpin handler already captures its
                        // message rather than reading it back from the row.
                        key: ValueKey(message.id),
                        title: Text(name,
                            style: Theme.of(context).textTheme.titleSmall),
                        subtitle: Text(
                          message.content.isEmpty
                              ? '(attachment)'
                              : message.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: widget.canManage
                            ? IconButton(
                                tooltip: 'Unpin',
                                onPressed: () => _unpin(message),
                                icon: const Icon(Icons.push_pin_outlined,
                                    size: 18),
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
