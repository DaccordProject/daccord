import 'package:bonfire/shared/utils/client_access.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/utils/message_visibility.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
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
  ValueChanged<AccordUser>? onUserTap,
  void Function(AccordUser user, Offset? globalPosition)? onUserContextMenu,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PinnedMessagesDialog(
      channelId: channelId,
      spaceId: spaceId,
      canManage: canManage,
      onUserTap: onUserTap,
      onUserContextMenu: onUserContextMenu,
    ),
  );
}

class _PinnedMessagesDialog extends ConsumerStatefulWidget {
  const _PinnedMessagesDialog({
    required this.channelId,
    required this.spaceId,
    required this.canManage,
    required this.onUserTap,
    required this.onUserContextMenu,
  });

  final String channelId;
  final String? spaceId;
  final bool canManage;
  final ValueChanged<AccordUser>? onUserTap;
  final void Function(AccordUser user, Offset? globalPosition)?
  onUserContextMenu;

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
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) return const [];
    final result = await client.messages.listPins(widget.channelId);
    final data = result.data;
    if (!result.ok || data is! List) return const [];
    return data.whereType<AccordMessage>().toList();
  }

  Future<void> _unpin(AccordMessage message) async {
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) return;
    await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .unpin(client, message.id);
    if (mounted) setState(() => _future = _load());
  }

  /// Reports a pinned message. The pinned list shows other people's content
  /// like any other message surface, so it offers the same action (#290).
  void _report(AccordMessage message, String authorName) {
    showReportDialog(
      context,
      spaceId: widget.spaceId,
      targetType: 'message',
      targetId: message.id,
      channelId: widget.channelId,
      reportedUserId: message.authorId.isEmpty ? null : message.authorId,
      reportedName: authorName,
    );
  }

  /// A pinned row's trailing actions: Report for anyone else's message, Unpin
  /// where the user may manage them. Null when there is neither.
  Widget? _rowActions(
    AccordMessage message,
    String authorName, {
    required String? currentUserId,
  }) {
    final actions = <Widget>[
      if (message.authorId != currentUserId)
        IconButton(
          tooltip: 'Report',
          onPressed: () => _report(message, authorName),
          icon: const Icon(Icons.flag_outlined, size: 18),
        ),
      if (widget.canManage)
        IconButton(
          tooltip: 'Unpin',
          onPressed: () => _unpin(message),
          icon: const Icon(Icons.push_pin_outlined, size: 18),
        ),
    ];
    if (actions.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Watched here rather than inside the FutureBuilder, which builds outside
    // this widget's build phase.
    final visibility = ref.watchMessageVisibility();
    final currentUserId = ref.watchUserId();
    final members = widget.spaceId == null
        ? null
        : ref.watch(
            accordMembersControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.spaceId!,
            ),
          );
    final users = ref.watch(
      accordUsersControllerProvider(ref.readActiveServerKey() ?? ''),
    );
    final ensureUser = ref
        .read(
          accordUsersControllerProvider(
            ref.readActiveServerKey() ?? '',
          ).notifier,
        )
        .ensure;
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
                  Text(
                    'Pinned messages',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                  final pins = visibility.filter(
                    snapshot.data ?? const <AccordMessage>[],
                  );
                  if (pins.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No pinned messages',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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
                      final name = accordAuthorName(
                        message.authorId,
                        members: members,
                        users: users,
                        ensure: ensureUser,
                      );
                      final author =
                          members?[message.authorId]?.user ??
                          users[message.authorId];
                      Widget authorName = Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall,
                      );
                      if (author != null &&
                          (widget.onUserTap != null ||
                              widget.onUserContextMenu != null)) {
                        authorName = MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onUserTap == null
                                ? null
                                : () => widget.onUserTap!(author),
                            onLongPressStart: widget.onUserContextMenu == null
                                ? null
                                : (details) => widget.onUserContextMenu!(
                                    author,
                                    details.globalPosition,
                                  ),
                            onSecondaryTapUp: widget.onUserContextMenu == null
                                ? null
                                : (details) => widget.onUserContextMenu!(
                                    author,
                                    details.globalPosition,
                                  ),
                            child: authorName,
                          ),
                        );
                      }
                      return ListTile(
                        // Keyed by message id so rows track their message, not
                        // their slot, when the list reloads after an unpin
                        // (see #198). The unpin handler already captures its
                        // message rather than reading it back from the row.
                        key: ValueKey(message.id),
                        title: authorName,
                        subtitle: Text(
                          message.content.isEmpty
                              ? '(attachment)'
                              : message.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _rowActions(
                          message,
                          name,
                          currentUserId: currentUserId,
                        ),
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
