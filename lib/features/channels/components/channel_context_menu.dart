import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/components/channel_management.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

IconData _glyphFor(String? type) {
  switch (type) {
    case 'voice':
      return Icons.volume_up;
    case 'forum':
      return Icons.forum;
    case 'announcement':
      return Icons.campaign;
    case 'category':
      return Icons.folder;
    default:
      return Icons.tag;
  }
}

/// Opens the long-press / right-click context menu for a leaf [channel].
/// [hostContext] is the launching tile's context (kept distinct from the
/// sheet's own so dialogs opened after the sheet pops still have a live
/// ancestor). Management actions are gated on [canManageChannels].
Future<void> showChannelContextMenu(
  BuildContext hostContext, {
  required AccordChannel channel,
  required String spaceId,
  required bool canManageChannels,
}) {
  return showModalBottomSheet<void>(
    context: hostContext,
    builder: (_) => _ChannelMenu(
      hostContext: hostContext,
      channel: channel,
      spaceId: spaceId,
      canManageChannels: canManageChannels,
    ),
  );
}

class _ChannelMenu extends ConsumerStatefulWidget {
  const _ChannelMenu({
    required this.hostContext,
    required this.channel,
    required this.spaceId,
    required this.canManageChannels,
  });

  final BuildContext hostContext;
  final AccordChannel channel;
  final String spaceId;
  final bool canManageChannels;

  @override
  ConsumerState<_ChannelMenu> createState() => _ChannelMenuState();
}

class _ChannelMenuState extends ConsumerState<_ChannelMenu> {
  // Server-side mute state is a separate axis from local notification levels;
  // it must be fetched (mirrors the channel-header bell). null = still loading.
  bool? _muted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadMuted();
  }

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  Future<void> _loadMuted() async {
    final client = _client;
    if (client == null) return;
    final result = await client.users.listMutes();
    if (!mounted) return;
    final data = result.data;
    final ids = data is List
        ? data.map((e) => e.toString()).toSet()
        : const <String>{};
    setState(() => _muted = ids.contains(widget.channel.id));
  }

  Future<void> _toggleMute() async {
    final client = _client;
    if (client == null || _busy || _muted == null) return;
    final next = !_muted!;
    setState(() => _busy = true);
    Navigator.of(context).maybePop();
    next
        ? await client.channels.mute(widget.channel.id)
        : await client.channels.unmute(widget.channel.id);
  }

  void _markRead() {
    ref.read(readStateControllerProvider.notifier).markRead(widget.channel.id);
    final messages =
        ref.read(accordMessagesControllerProvider(widget.channel.id));
    final lastId = messages?.isNotEmpty == true ? messages!.last.id : null;
    if (lastId != null) _client?.channels.ack(widget.channel.id, lastId);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final channel = widget.channel;
    final unread = ref.watch(
      readStateControllerProvider.select((s) => s.isUnread(channel.id)),
    );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            leading: Icon(_glyphFor(channel.type), color: colors.dirtyWhite),
            title: Text(
              channel.name ?? channel.id,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          if (unread)
            ListTile(
              leading: const Icon(Icons.mark_chat_read_outlined),
              title: const Text('Mark as read'),
              onTap: _markRead,
            ),
          ListTile(
            leading: Icon(
              _muted == true
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: Text(_muted == true ? 'Unmute channel' : 'Mute channel'),
            enabled: _muted != null && !_busy,
            trailing: _muted == null
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _toggleMute,
          ),
          if (widget.canManageChannels) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Edit channel'),
              onTap: () {
                Navigator.of(context).maybePop();
                showEditChannelDialog(
                  widget.hostContext,
                  spaceId: widget.spaceId,
                  channel: channel,
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colors.red),
              title: Text('Delete channel', style: TextStyle(color: colors.red)),
              onTap: () {
                Navigator.of(context).maybePop();
                confirmAndDeleteChannel(
                  widget.hostContext,
                  ref,
                  spaceId: widget.spaceId,
                  channel: channel,
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens the long-press / right-click context menu for a [category] header.
/// [collapsed]/[onToggle] mirror the header's expand state so the menu can flip
/// it; management actions are gated on [canManageChannels].
Future<void> showCategoryContextMenu(
  BuildContext hostContext,
  WidgetRef ref, {
  required AccordChannel category,
  required String spaceId,
  required bool canManageChannels,
  required bool collapsed,
  required VoidCallback onToggle,
}) {
  return showModalBottomSheet<void>(
    context: hostContext,
    builder: (sheetCtx) {
      final colors = BonfireThemeExtension.of(sheetCtx);
      final theme = Theme.of(sheetCtx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: Icon(Icons.folder, color: colors.dirtyWhite),
              title: Text(
                (category.name ?? category.id).toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
              title: Text(collapsed ? 'Expand category' : 'Collapse category'),
              onTap: () {
                onToggle();
                Navigator.of(sheetCtx).maybePop();
              },
            ),
            if (canManageChannels) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create channel here'),
                onTap: () {
                  Navigator.of(sheetCtx).maybePop();
                  showCreateChannelDialog(
                    hostContext,
                    spaceId: spaceId,
                    parentId: category.id,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Edit category'),
                onTap: () {
                  Navigator.of(sheetCtx).maybePop();
                  showEditChannelDialog(
                    hostContext,
                    spaceId: spaceId,
                    channel: category,
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: colors.red),
                title:
                    Text('Delete category', style: TextStyle(color: colors.red)),
                onTap: () {
                  Navigator.of(sheetCtx).maybePop();
                  confirmAndDeleteChannel(
                    hostContext,
                    ref,
                    spaceId: spaceId,
                    channel: category,
                  );
                },
              ),
            ],
          ],
        ),
      );
    },
  );
}
