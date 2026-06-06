import 'package:accordkit/accordkit.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/components/channel_management.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_list.dart';
import 'package:bonfire/features/member/views/accord_member_popout.dart';
import 'package:bonfire/features/messaging/components/box/accord_embed_box.dart';
import 'package:bonfire/features/messaging/components/emoji_picker.dart';
import 'package:bonfire/features/messaging/components/box/accord_message_content.dart';
import 'package:bonfire/features/messaging/components/forum_view.dart';
import 'package:bonfire/features/messaging/components/thread_view.dart';
import 'package:bonfire/features/messaging/components/image_lightbox.dart';
import 'package:bonfire/features/messaging/components/inline_audio_player.dart';
import 'package:bonfire/features/messaging/components/inline_video_player.dart';
import 'package:bonfire/features/messaging/components/pinned_messages.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/notifications/controllers/sound.dart';
import 'package:bonfire/features/messaging/controllers/typing.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_discovery.dart';
import 'package:bonfire/features/spaces/views/accord_gates.dart';
import 'package:bonfire/features/spaces/views/accord_channel_reorder.dart';
import 'package:bonfire/features/spaces/views/accord_invites.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/features/spaces/views/accord_search.dart';
import 'package:bonfire/features/user/components/self_status_button.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/views/accord_space_settings.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'accord_home_rail.dart';
part 'accord_home_channels.dart';
part 'accord_home_messages.dart';
part 'accord_home_message_row.dart';
part 'accord_home_composer.dart';
part 'accord_home_attachments.dart';


/// The primary Accord screen: a three-pane view (space rail → channel list →
/// message history) wired to the Accord controllers.
class AccordHomeScreen extends ConsumerStatefulWidget {
  const AccordHomeScreen({super.key});

  @override
  ConsumerState<AccordHomeScreen> createState() => _AccordHomeScreenState();
}

class _AccordHomeScreenState extends ConsumerState<AccordHomeScreen> {
  String? _selectedSpaceId;
  String? _selectedChannelId;
  // The space we've already run the rules interstitial check for this session.
  String? _rulesCheckedSpaceId;

  /// Selects [spaceId] on connection [serverKey]. When the server differs from
  /// the active connection it flips the active connection first, which reseeds
  /// the shared space/channel/member controllers from that server.
  void _selectSpace(String serverKey, String spaceId) {
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    if (serverKey != activeKey) {
      ref.read(accordAuthProvider.notifier).setActiveServer(serverKey);
    }
    setState(() {
      _selectedSpaceId = spaceId;
      _selectedChannelId = null;
    });
  }

  Future<void> _selectChannel(String channelId) async {
    final spaceId = _selectedSpaceId;
    final channel = spaceId == null
        ? null
        : ref
            .read(accordChannelsControllerProvider(spaceId))
            ?.firstWhereOrNull((c) => c.id == channelId);
    if (channel != null && channel.nsfw && spaceId != null) {
      final ok = await confirmNsfwGate(
        context,
        ref,
        channelId: channelId,
        channelName: channel.name ?? 'channel',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _selectedChannelId = channelId);
    _markChannelRead(channelId);
  }

  /// Marks [channelId] read locally and POSTs `channels.ack` with the latest
  /// known message ID so the server's read position catches up too. Safe to
  /// call when the channel has no cached messages (no last ID → ack is a
  /// no-op; the local clear still happens).
  void _markChannelRead(String channelId) {
    ref.read(readStateControllerProvider.notifier).markRead(channelId);
    final messages =
        ref.read(accordMessagesControllerProvider(channelId));
    final lastId = messages?.isNotEmpty == true ? messages!.last.id : null;
    if (lastId == null) return;
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    client?.channels.ack(channelId, lastId);
  }

  /// Shows the rules interstitial once when a space with a rules channel is
  /// first opened this session.
  void _maybeCheckRules(AccordSpace? space) {
    if (space == null || space.id == _rulesCheckedSpaceId) return;
    _rulesCheckedSpaceId = space.id;
    if (space.rulesChannelId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowRulesInterstitial(context, ref, space: space);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(accordAuthProvider, (previous, next) {
      if (next is! AccordAuthLoggedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/');
        });
      }
    });

    final spaces = ref.watch(spacesControllerProvider);

    // After an active-server switch the remembered selection may belong to a
    // now-background server; fall back to the active server's first space.
    final hasSelected = _selectedSpaceId != null &&
        (spaces?.any((s) => s.id == _selectedSpaceId) ?? false);
    final selectedSpaceId = hasSelected
        ? _selectedSpaceId
        : ((spaces != null && spaces.isNotEmpty) ? spaces.first.id : null);

    _maybeCheckRules(
        spaces?.firstWhereOrNull((s) => s.id == selectedSpaceId));

    final channels = selectedSpaceId == null
        ? null
        : ref.watch(accordChannelsControllerProvider(selectedSpaceId));

    final listableChannels =
        channels?.where((c) => c.type != 'category').toList();

    final firstText =
        listableChannels?.where((c) => c.type == 'text').firstOrNull;
    final selectedChannelId = _selectedChannelId ?? firstText?.id;

    // Let the notification layer skip the channel that's on screen.
    accordVisibleChannelId = selectedChannelId;

    return Row(
      children: [
        _SpaceRail(
          selectedSpaceId: selectedSpaceId,
          onSelect: _selectSpace,
          onAddServer: () => showAddServerDialog(context),
          onSwitchAccount: () => context.go('/switcher'),
          onOpenSettings: () => context.push('/settings'),
          onLogout: () => ref.read(accordAuthProvider.notifier).logout(),
        ),
        _ChannelList(
          spaceId: selectedSpaceId,
          spaceName: spaces
              ?.where((s) => s.id == selectedSpaceId)
              .firstOrNull
              ?.name,
          channels: channels,
          selectedChannelId: selectedChannelId,
          onSelect: _selectChannel,
        ),
        Expanded(
          child: _MessagePane(
            channel: channels?.where((c) => c.id == selectedChannelId).firstOrNull,
            channelId: selectedChannelId,
            spaceId: selectedSpaceId,
          ),
        ),
        if (selectedSpaceId != null) AccordMemberList(spaceId: selectedSpaceId),
      ],
    );
  }
}
