import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/components/user_avatar.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/missed_calls.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/views/voice_pip_overlay.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'accord_direct_messages_conversations.dart';
part 'accord_direct_messages_friends.dart';
part 'accord_direct_messages_groups.dart';
part 'accord_direct_messages_user_search.dart';

/// Relationship type enum mirrored from the server: 1 = friend, 2 = blocked,
/// 3 = pending incoming, 4 = pending outgoing.
class _Rel {
  static const friend = 1;
  static const blocked = 2;
  static const pendingIn = 3;
  static const pendingOut = 4;
}

/// Best display name for a user.
String _userName(AccordUser? user) {
  if (user == null) return 'Unknown';
  final display = user.displayName;
  if (display != null && display.isNotEmpty) return display;
  return user.username.isNotEmpty ? user.username : user.id;
}

/// The recipients of [channel] excluding the current user.
List<AccordUser> _others(AccordChannel channel, String? selfId) =>
    (channel.recipients ?? const <AccordUser>[])
        .where((u) => u.id != selfId)
        .toList();

/// The home domain of a 1:1 DM's remote participant, or null for a local DM or
/// a group. Drives the federated-origin badge so a cross-server DM is visually
/// distinguishable from a same-server one.
String? _dmRemoteOrigin(AccordChannel channel, String? selfId) {
  final others = _others(channel, selfId);
  if (others.length != 1) return null;
  return accordUserOrigin(others.first);
}

/// Whether [channel] is a group DM (3+ participants). Accord types DM channels
/// as `dm` (1:1) or `group_dm`; we also fall back to the recipient count since
/// some payloads omit the type.
bool _isGroup(AccordChannel channel, String? selfId) =>
    channel.type == 'group_dm' || _others(channel, selfId).length > 1;

/// Title for a DM/group channel: a group's custom name, else the joined
/// recipient names.
String _channelTitle(AccordChannel channel, String? selfId) {
  final name = channel.name;
  if (name != null && name.isNotEmpty) return name;
  final others = _others(channel, selfId);
  if (others.isEmpty) return 'Direct message';
  return others.map(_userName).join(', ');
}

/// Opens the direct-messages & friends panel: a tabbed dialog with the user's DM
/// conversations and their friends list (with requests). The Accord analogue of
/// the reference client's `dm_list` + `friends_list`. Pass [initialChannel] to
/// open straight into a conversation.
Future<void> showAccordDirectMessages(
  BuildContext context, {
  AccordChannel? initialChannel,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DirectMessagesDialog(initialChannel: initialChannel),
  );
}

/// Opens (creating if needed) the 1:1 direct message with [userId] and shows the
/// DM dialog focused on that conversation. Accord's `createDm` is idempotent for
/// a single recipient — it returns the existing DM when one already exists.
///
/// A **qualified** [userId] (`<snowflake>@<domain>`) opens a *cross-server* DM:
/// the server picks a deterministic home server and mirrors a replica DM channel
/// for us, returned with a qualified channel ID. A bare id is a same-server DM.
Future<void> openAccordDirectMessage(
  BuildContext context,
  WidgetRef ref,
  String userId,
) async {
  final client = ref.accordClient;
  final serverKey = ref.readActiveServerKey();
  if (client == null || serverKey == null) return;
  final result = await client.users.createDm(dmCreateBody(userId));
  if (!context.mounted || ref.readActiveServerKey() != serverKey) return;
  final data = result.data;
  if (result.ok && data is AccordChannel) {
    ref.read(dmChannelsControllerProvider(serverKey).notifier).upsert(data);
    await showAccordDirectMessages(context, initialChannel: data);
  } else {
    // Surface the server's reason (federation disabled, recipient not
    // qualified, peer untrusted, recipient blocked, …) rather than a generic
    // failure, so a rejected cross-server open is actionable.
    _snackDmError(context, result.error, 'Failed to open direct message');
  }
}

/// Shows [error]'s server message (when present) or [fallback] in a snackbar.
void _snackDmError(BuildContext context, AccordError? error, String fallback) {
  final reason = error?.message;
  showInfoSnack(
    context,
    reason != null && reason.isNotEmpty ? reason : fallback,
  );
}

/// Account-level profile used where there is no space/member context. It keeps
/// DM author and recipient interactions useful without pretending that a DM
/// user has space roles, nicknames, or moderation controls.
Future<void> showAccordUserProfile(
  BuildContext context,
  AccordUser user, {
  String? cdnUrl,
}) {
  final name = _userName(user);
  final origin = accordUserOrigin(user);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              name,
              imageUrl: accordAvatarUrl(user, cdnUrl),
              radius: 30,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  if (user.username.isNotEmpty) Text('@${user.username}'),
                  const SizedBox(height: 8),
                  SelectableText(user.id),
                  if (origin != null) ...[
                    const SizedBox(height: 8),
                    RemoteOriginBadge(domain: origin),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Responsive right-click/long-press menu for users shown in DMs. Relationship
/// state is fetched when the menu opens so the action is accurate even when the
/// Friends tab has not been visited this session.
Future<void> showAccordDmUserContextMenu(
  BuildContext context,
  WidgetRef ref,
  AccordUser user, {
  Offset? globalPosition,
  String? currentDmUserId,
  List<AccordMenuEntry> extraEntries = const [],
}) async {
  final client = ref.accordClient;
  final selfId = ref.readUserId();
  AccordRelationship? relationship;
  if (client != null && user.id != selfId) {
    final result = await client.users.listRelationships();
    final data = result.data;
    if (data is List) {
      for (final item in data.whereType<AccordRelationship>()) {
        if (item.user?.id == user.id) {
          relationship = item;
          break;
        }
      }
    }
  }
  if (!context.mounted) return;

  final rel = relationship;
  final entries = <AccordMenuEntry>[
    AccordMenuEntry(
      label: 'View profile',
      icon: Icons.account_circle_outlined,
      onSelected: () =>
          showAccordUserProfile(context, user, cdnUrl: ref.readCdnUrl()),
    ),
    if (user.id != selfId && user.id != currentDmUserId)
      AccordMenuEntry(
        label: 'Direct message',
        icon: Icons.chat_bubble_outline,
        onSelected: () => openAccordDirectMessage(context, ref, user.id),
      ),
    if (user.id != selfId) ...[
      AccordMenuEntry(
        label: switch (rel?.type) {
          _Rel.friend => 'Remove friend',
          _Rel.blocked => 'Unblock',
          _Rel.pendingIn => 'Accept friend request',
          _Rel.pendingOut => 'Cancel friend request',
          _ => 'Add friend',
        },
        icon: switch (rel?.type) {
          _Rel.friend => Icons.person_remove_outlined,
          _Rel.blocked => Icons.lock_open_outlined,
          _Rel.pendingIn => Icons.person_add_alt_1,
          _Rel.pendingOut => Icons.person_remove_outlined,
          _ => Icons.person_add_outlined,
        },
        destructive: rel?.type == _Rel.friend,
        onSelected: () => _changeDmRelationship(context, ref, user, rel?.type),
      ),
      AccordMenuEntry(
        label: 'Report user',
        icon: Icons.flag_outlined,
        destructive: true,
        onSelected: () => showReportDialog(
          context,
          targetType: 'user',
          targetId: user.id,
          reportedUserId: user.id,
          reportedName: _userName(user),
        ),
      ),
      if (rel?.type != _Rel.blocked)
        AccordMenuEntry(
          label: 'Block',
          icon: Icons.block,
          destructive: true,
          onSelected: () => _blockDmUser(context, ref, user),
        ),
    ],
    const AccordMenuEntry.divider(),
    AccordMenuEntry(
      label: 'Copy user ID',
      icon: Icons.copy_outlined,
      onSelected: () => Clipboard.setData(ClipboardData(text: user.id)),
    ),
    if (user.username.isNotEmpty)
      AccordMenuEntry(
        label: 'Copy username',
        icon: Icons.alternate_email,
        onSelected: () => Clipboard.setData(ClipboardData(text: user.username)),
      ),
    ...extraEntries,
  ];
  await showAccordContextMenu(
    context,
    entries: entries,
    globalPosition: globalPosition,
    title: _userName(user),
    titleIcon: Icons.person_outline,
  );
}

Future<void> _changeDmRelationship(
  BuildContext context,
  WidgetRef ref,
  AccordUser user,
  int? currentType,
) async {
  final client = ref.accordClient;
  if (client == null) return;
  final removing =
      currentType == _Rel.friend ||
      currentType == _Rel.blocked ||
      currentType == _Rel.pendingOut;
  final result = removing
      ? await client.users.deleteRelationship(user.id)
      : await client.users.putRelationship(user.id, {'type': _Rel.friend});
  if (!context.mounted) return;
  showInfoSnack(
    context,
    result.ok
        ? switch (currentType) {
            _Rel.friend => 'Friend removed',
            _Rel.blocked => 'User unblocked',
            _Rel.pendingIn => 'Friend request accepted',
            _Rel.pendingOut => 'Friend request cancelled',
            _ => 'Friend request sent',
          }
        : 'Failed to update relationship',
  );
}

Future<void> _blockDmUser(
  BuildContext context,
  WidgetRef ref,
  AccordUser user,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Block user',
    message: 'Blocked users cannot DM you and their messages are hidden.',
    confirmLabel: 'Block',
    danger: true,
  );
  if (confirmed != true || !context.mounted) return;
  final result = await ref.accordClient?.users.putRelationship(user.id, {
    'type': _Rel.blocked,
  });
  if (!context.mounted) return;
  showInfoSnack(
    context,
    result?.ok == true ? 'User blocked' : 'Failed to block user',
  );
}

class _DirectMessagesDialog extends ConsumerStatefulWidget {
  const _DirectMessagesDialog({this.initialChannel});

  final AccordChannel? initialChannel;

  @override
  ConsumerState<_DirectMessagesDialog> createState() =>
      _DirectMessagesDialogState();
}

class _DirectMessagesDialogState extends ConsumerState<_DirectMessagesDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late AccordChannel? _openChannel = widget.initialChannel;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String? get _selfId => ref.readUserId();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final openChannel = _openChannel;
    final dialog = Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 900, maxHeight: 720),
        child: openChannel != null
            ? _DmConversation(
                channel: openChannel,
                selfId: _selfId,
                onBack: () => setState(() => _openChannel = null),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Direct messages',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close, size: 20, color: colors.gray),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabs,
                    tabs: const [
                      Tab(text: 'Messages'),
                      Tab(text: 'Friends'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _DmListTab(
                          selfId: _selfId,
                          onOpen: (c) => setState(() => _openChannel = c),
                        ),
                        const _FriendsTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
    final inDmCall = ref.watch(
      voiceControllerProvider.select(
        (voice) => voice.isConnected && voice.spaceId == null,
      ),
    );
    return Stack(
      children: [
        dialog,
        // The home screen's PiP sits below this modal route. Host a DM-only
        // copy here so minimizing the full-screen call returns to a visible,
        // interactive preview instead of hiding it behind the conversation.
        // Space calls keep using the home overlay, whose channel opener can
        // restore the correct space and tab.
        if (inDmCall)
          VoicePipOverlay(
            shownChannelId: null,
            onOpen: (_, _) {
              // This overlay is only mounted for spaceless calls, which reopen
              // themselves without consulting the space-channel callback.
            },
          ),
      ],
    );
  }
}
