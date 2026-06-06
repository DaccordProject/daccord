import 'package:accordkit/accordkit.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/components/channel_management.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/models/open_tab.dart';
import 'package:bonfire/features/developer/services/mcp_home_bridge.dart';
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
import 'package:bonfire/features/server/models/accord_server.dart';
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
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/voice_bar.dart';
import 'package:bonfire/features/voice/views/voice_participants.dart';
import 'package:bonfire/features/voice/views/voice_pip_overlay.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'accord_home_rail.dart';
part 'accord_home_tabs.dart';
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
  // A space navigated to from the rail whose default channel should auto-open as
  // a tab once its channels load. Cleared as soon as a tab is opened/activated.
  String? _pendingOpenSpaceId;
  // The channel id currently being auto-opened in a post-frame callback, used to
  // avoid scheduling the same open twice while the gateway round-trips.
  String? _autoOpenInFlight;
  // The space we've already run the rules interstitial check for this session.
  String? _rulesCheckedSpaceId;
  // Member-list visibility, toggled by the user and by the MCP `navigate` group.
  bool _memberListVisible = true;

  @override
  void initState() {
    super.initState();
    mcpHomeBridge.registerAll(_mcpNavHandlers());
  }

  @override
  void dispose() {
    mcpHomeBridge.clear();
    super.dispose();
  }

  /// Navigation handlers the local MCP server's `navigate` tools delegate to.
  /// Each receives the argument map already resolved by the tools layer and
  /// returns an MCP result map.
  Map<String, McpNavHandler> _mcpNavHandlers() => {
        'select_space': (args) async {
          _selectSpace(args['server_key'] as String, args['space_id'] as String);
          return {'ok': true};
        },
        'select_channel': (args) async {
          await _openChannel(args['channel_id'] as String,
              spaceId: args['space_id'] as String);
          return {'ok': true};
        },
        'open_dm': (args) async {
          if (!mounted) return _mcpUnmounted;
          showAccordDirectMessages(context);
          return {'ok': true};
        },
        'open_settings': (args) async {
          if (!mounted) return _mcpUnmounted;
          context.push('/settings');
          return {'ok': true};
        },
        'open_discovery': (args) async {
          if (!mounted) return _mcpUnmounted;
          showAccordDiscovery(context);
          return {'ok': true};
        },
        'open_thread': (args) async {
          if (!mounted) return _mcpUnmounted;
          final channelId = args['channel_id'] as String;
          final messageId = args['message_id'] as String;
          final root = ref
              .read(accordMessagesControllerProvider(channelId))
              ?.firstWhereOrNull((m) => m.id == messageId);
          if (root == null) return {'error': 'Message not loaded'};
          showAccordThread(context, channelId: channelId, root: root);
          return {'ok': true};
        },
        'open_voice_view': (args) async {
          if (!mounted) return _mcpUnmounted;
          final voice = ref.read(voiceControllerProvider);
          if (!voice.isConnected) {
            return {'error': 'Not connected to a voice channel'};
          }
          await _openChannel(voice.channelId!, spaceId: voice.spaceId!);
          return {'ok': true};
        },
        'toggle_member_list': (args) async {
          if (!mounted) return _mcpUnmounted;
          setState(() => _memberListVisible = !_memberListVisible);
          mcpHomeBridge.memberListVisible = _memberListVisible;
          return {'ok': true, 'visible': _memberListVisible};
        },
        'toggle_search': (args) async {
          if (!mounted) return _mcpUnmounted;
          final spaceId = mcpHomeBridge.currentSpaceId;
          if (spaceId == null || spaceId.isEmpty) {
            return {'error': 'No space selected'};
          }
          await showAccordSearch(context, spaceId: spaceId);
          return {'ok': true};
        },
      };

  static const Map<String, dynamic> _mcpUnmounted = {
    'error': 'Home screen not mounted'
  };

  /// Selects [spaceId] on connection [serverKey] from the rail. Flips the active
  /// connection when it differs, then either re-activates the most recent open
  /// tab for that space or, when none exists, auto-opens its default channel
  /// (mirrors the reference client jumping to a server's last/first channel).
  void _selectSpace(String serverKey, String spaceId) {
    final connections = ref.read(connectionsControllerProvider);
    if (serverKey != connections.activeKey) {
      ref.read(accordAuthProvider.notifier).setActiveServer(serverKey);
    }
    final existing = ref.read(openTabsControllerProvider).tabs.lastWhereOrNull(
        (t) => t.serverKey == serverKey && t.spaceId == spaceId);
    if (existing != null) {
      ref.read(openTabsControllerProvider.notifier).activate(existing.key);
      setState(() => _pendingOpenSpaceId = null);
      _markChannelRead(existing.channelId);
    } else {
      setState(() => _pendingOpenSpaceId = spaceId);
    }
  }

  /// Activates an already-open [tab] (from the tab strip), flipping the active
  /// server when the tab lives on a different connection.
  void _selectTab(OpenTab tab) {
    final connections = ref.read(connectionsControllerProvider);
    if (tab.serverKey != connections.activeKey) {
      ref.read(accordAuthProvider.notifier).setActiveServer(tab.serverKey);
    }
    ref.read(openTabsControllerProvider.notifier).activate(tab.key);
    setState(() => _pendingOpenSpaceId = null);
    _markChannelRead(tab.channelId);
  }

  /// Opens (or switches to) a tab for [channelId] in [spaceId] on the active
  /// server. Preserves the NSFW gate and voice-join behaviour the single
  /// selection used to carry.
  Future<void> _openChannel(String channelId, {required String spaceId}) async {
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    if (activeKey == null) return;
    final channel = ref
        .read(accordChannelsControllerProvider(spaceId))
        ?.firstWhereOrNull((c) => c.id == channelId);
    if (channel != null && channel.nsfw) {
      final ok = await confirmNsfwGate(
        context,
        ref,
        channelId: channelId,
        channelName: channel.name ?? 'channel',
      );
      if (!ok || !mounted) return;
    }
    // Tapping a voice channel joins it (unless already connected); the message
    // pane renders the voice view for the opened tab.
    if (channel?.type == 'voice') {
      final connected =
          ref.read(voiceControllerProvider).channelId == channelId;
      if (!connected) {
        ref.read(voiceControllerProvider.notifier).join(channelId, spaceId);
      }
    }
    ref.read(openTabsControllerProvider.notifier).open(OpenTab(
          channelId: channelId,
          spaceId: spaceId,
          serverKey: activeKey,
          name: channel?.name ?? channelId,
        ));
    if (channel?.type != 'voice') _markChannelRead(channelId);
    setState(() => _pendingOpenSpaceId = null);
  }

  /// Auto-opens [channel] as a tab once its space's channels have loaded (used
  /// for the fresh-login default and rail navigation to a space with no tab).
  void _scheduleAutoOpen(AccordChannel channel, String spaceId) {
    if (_autoOpenInFlight == channel.id) return;
    _autoOpenInFlight = channel.id;
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoOpenInFlight = null;
      if (!mounted || activeKey == null) return;
      ref.read(openTabsControllerProvider.notifier).open(OpenTab(
            channelId: channel.id,
            spaceId: spaceId,
            serverKey: activeKey,
            name: channel.name ?? channel.id,
          ));
      _markChannelRead(channel.id);
      if (_pendingOpenSpaceId != null) {
        setState(() => _pendingOpenSpaceId = null);
      }
    });
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

    // Keep the active connection in step with the active tab — closing a tab can
    // hand focus to one on a different server, which must become active for its
    // panes to load.
    ref.listen(openTabsControllerProvider.select((s) => s.activeTab),
        (previous, next) {
      if (next == null) return;
      final activeKey = ref.read(connectionsControllerProvider).activeKey;
      if (next.serverKey != activeKey) {
        ref.read(accordAuthProvider.notifier).setActiveServer(next.serverKey);
      }
    });

    // Prune tabs belonging to a server that was logged out / removed.
    ref.listen(
        connectionsControllerProvider
            .select((s) => s.connections.map((c) => c.key).toSet()),
        (previous, next) {
      if (previous == null) return;
      final removed = previous.difference(next);
      if (removed.isEmpty) return;
      final notifier = ref.read(openTabsControllerProvider.notifier);
      for (final key in removed) {
        notifier.removeForServer(key);
      }
    });

    final spaces = ref.watch(spacesControllerProvider);
    final activeKey =
        ref.watch(connectionsControllerProvider.select((s) => s.activeKey));
    final activeTab =
        ref.watch(openTabsControllerProvider.select((s) => s.activeTab));

    // Resolve which space drives the channel list / member pane.
    String? effectiveSpaceId;
    if (_pendingOpenSpaceId != null &&
        (spaces?.any((s) => s.id == _pendingOpenSpaceId) ?? false)) {
      effectiveSpaceId = _pendingOpenSpaceId;
    } else if (activeTab != null &&
        activeTab.serverKey == activeKey &&
        (spaces?.any((s) => s.id == activeTab.spaceId) ?? false)) {
      effectiveSpaceId = activeTab.spaceId;
    } else if (spaces != null && spaces.isNotEmpty) {
      effectiveSpaceId = spaces.first.id;
    }

    _maybeCheckRules(
        spaces?.firstWhereOrNull((s) => s.id == effectiveSpaceId));

    final channels = effectiveSpaceId == null
        ? null
        : ref.watch(accordChannelsControllerProvider(effectiveSpaceId));

    final firstText = channels
        ?.where((c) => c.type == 'text')
        .firstOrNull;

    // The channel shown in the message pane: the active tab when it lives in the
    // shown space, otherwise the space's default channel (auto-opened as a tab).
    String? shownChannelId;
    final activeTabHere = activeTab != null &&
        activeTab.serverKey == activeKey &&
        (channels?.any((c) => c.id == activeTab.channelId) ?? false);
    if (activeTabHere) {
      shownChannelId = activeTab.channelId;
    } else if (effectiveSpaceId != null && firstText != null) {
      shownChannelId = firstText.id;
      _scheduleAutoOpen(firstText, effectiveSpaceId);
    }

    // Let the notification layer skip the channel that's on screen.
    accordVisibleChannelId = shownChannelId;

    // Keep the MCP bridge's snapshot current for the `read` group's
    // get_current_state and for navigate handlers that need the active space.
    mcpHomeBridge
      ..currentSpaceId = effectiveSpaceId
      ..currentChannelId = shownChannelId
      ..memberListVisible = _memberListVisible;

    final shownSpaceId = effectiveSpaceId;
    return Stack(
      children: [
        Row(
          children: [
        _SpaceRail(
          selectedSpaceId: effectiveSpaceId,
          onSelect: _selectSpace,
          onAddServer: () => showAddServerDialog(context),
          onSwitchAccount: () => context.go('/switcher'),
          onOpenSettings: () => context.push('/settings'),
          onLogout: () => ref.read(accordAuthProvider.notifier).logout(),
        ),
        _ChannelList(
          spaceId: effectiveSpaceId,
          spaceName:
              spaces?.firstWhereOrNull((s) => s.id == effectiveSpaceId)?.name,
          channels: channels,
          selectedChannelId: shownChannelId,
          onSelect: shownSpaceId == null
              ? (_) {}
              : (channelId) => _openChannel(channelId, spaceId: shownSpaceId),
        ),
        Expanded(
          child: Column(
            children: [
              _TabStrip(onSelect: _selectTab),
              Expanded(
                child: _MessagePane(
                  channel: channels
                      ?.firstWhereOrNull((c) => c.id == shownChannelId),
                  channelId: shownChannelId,
                  spaceId: effectiveSpaceId,
                ),
              ),
            ],
          ),
        ),
        if (effectiveSpaceId != null && _memberListVisible)
          AccordMemberList(spaceId: effectiveSpaceId),
          ],
        ),
        VoicePipOverlay(
          shownChannelId: shownChannelId,
          onOpen: (channelId, spaceId) =>
              _openChannel(channelId, spaceId: spaceId),
        ),
      ],
    );
  }
}
