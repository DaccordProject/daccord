import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/user_avatar.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/refocus.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_content.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
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
  if (client == null) return;
  final result = await client.users.createDm(dmCreateBody(userId));
  if (!context.mounted) return;
  final data = result.data;
  if (result.ok && data is AccordChannel) {
    ref.read(dmChannelsControllerProvider.notifier).upsert(data);
    await showAccordDirectMessages(context, initialChannel: data);
  } else {
    // Surface the server's reason (federation disabled, recipient not
    // qualified, peer untrusted, recipient blocked, …) rather than a generic
    // failure, so a rejected cross-server open is actionable.
    _snackDmError(context, result.error, 'Failed to open direct message');
  }
}

/// Shows [error]'s server message (when present) or [fallback] in a snackbar.
void _snackDmError(
  BuildContext context,
  AccordError? error,
  String fallback,
) {
  final reason = error?.message;
  showInfoSnack(context, reason != null && reason.isNotEmpty ? reason : fallback);
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
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 560, maxHeight: 620),
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
  }
}
