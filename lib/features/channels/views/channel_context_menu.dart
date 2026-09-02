import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/views/channel_management.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/channels/utils/toggle_channel_mute.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/shared/components/context_menu.dart';
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

AccordClient? _clientOf(WidgetRef ref) => ref.read(
  accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null),
);

/// Opens the long-press / right-click context menu for a leaf [channel]. On
/// desktop it anchors next to [globalPosition]; on touch it opens a bottom
/// sheet. [hostContext] is the launching tile's context (kept distinct so
/// dialogs opened after the menu closes still have a live ancestor).
/// Management actions are gated on [canManageChannels]. [leadingEntries] are
/// prepended verbatim, for actions only the caller knows about (the channel
/// list's voice join/disconnect).
Future<void> showChannelContextMenu(
  BuildContext hostContext,
  WidgetRef ref, {
  required AccordChannel channel,
  required String spaceId,
  required bool canManageChannels,
  Offset? globalPosition,
  List<AccordMenuEntry> leadingEntries = const [],
}) async {
  final client = _clientOf(ref);
  final activeKey = ref.read(connectionsControllerProvider).activeKey;
  final mutedChannels = activeKey == null
      ? const <String>{}
      : await ref.read(mutedChannelsControllerProvider(activeKey).future);
  final muted = mutedChannels.contains(channel.id);
  if (!hostContext.mounted) return;

  final unread =
      activeKey != null &&
      ref.read(readStateControllerProvider(activeKey)).isUnread(channel.id);

  // Falls back to the channel's `last_message_id` so acking a channel whose
  // history was never opened (any voice channel, or one only ever seen as a
  // badge) still moves the server's read position — otherwise the badge returns
  // on the next connect.
  void markRead() => markChannelRead(
    ref,
    channel.id,
    fallbackMessageId: channel.lastMessageId,
  );

  final entries = <AccordMenuEntry>[
    ...leadingEntries,
    if (unread)
      AccordMenuEntry(
        label: 'Mark as read',
        icon: Icons.mark_chat_read_outlined,
        onSelected: markRead,
      ),
    AccordMenuEntry(
      label: muted ? 'Unmute channel' : 'Mute channel',
      icon: muted
          ? Icons.notifications_active_outlined
          : Icons.notifications_off_outlined,
      onSelected: client == null
          ? null
          : () {
              if (activeKey != null) {
                toggleChannelMute(
                  hostContext,
                  ref,
                  serverKey: activeKey,
                  channelId: channel.id,
                  muted: muted,
                );
              }
            },
    ),
    if (canManageChannels) ...[
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: 'Edit channel',
        icon: Icons.settings_outlined,
        onSelected: () => showEditChannelDialog(
          hostContext,
          spaceId: spaceId,
          channel: channel,
        ),
      ),
      AccordMenuEntry(
        label: 'Delete channel',
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: () => confirmAndDeleteChannel(
          hostContext,
          ref,
          spaceId: spaceId,
          channel: channel,
        ),
      ),
    ],
  ];

  return showAccordContextMenu(
    hostContext,
    entries: entries,
    globalPosition: globalPosition,
    title: channel.name ?? channel.id,
    titleIcon: _glyphFor(channel.type),
  );
}

/// Opens the long-press / right-click context menu for a [category] header. On
/// desktop it anchors next to [globalPosition]; on touch it opens a bottom
/// sheet. [collapsed]/[onToggle] mirror the header's expand state so the menu
/// can flip it; management actions are gated on [canManageChannels].
Future<void> showCategoryContextMenu(
  BuildContext hostContext,
  WidgetRef ref, {
  required AccordChannel category,
  required String spaceId,
  required bool canManageChannels,
  required bool collapsed,
  required VoidCallback onToggle,
  Offset? globalPosition,
}) {
  final entries = <AccordMenuEntry>[
    AccordMenuEntry(
      label: collapsed ? 'Expand category' : 'Collapse category',
      icon: collapsed ? Icons.expand_more : Icons.expand_less,
      onSelected: onToggle,
    ),
    if (canManageChannels) ...[
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: 'Create channel here',
        icon: Icons.add,
        onSelected: () => showCreateChannelDialog(
          hostContext,
          spaceId: spaceId,
          parentId: category.id,
        ),
      ),
      AccordMenuEntry(
        label: 'Edit category',
        icon: Icons.settings_outlined,
        onSelected: () => showEditChannelDialog(
          hostContext,
          spaceId: spaceId,
          channel: category,
        ),
      ),
      AccordMenuEntry(
        label: 'Delete category',
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: () => confirmAndDeleteChannel(
          hostContext,
          ref,
          spaceId: spaceId,
          channel: category,
        ),
      ),
    ],
  ];

  return showAccordContextMenu(
    hostContext,
    entries: entries,
    globalPosition: globalPosition,
    title: (category.name ?? category.id).toUpperCase(),
    titleIcon: Icons.folder,
  );
}
