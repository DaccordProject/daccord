import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/confirm_logout.dart';
import 'package:bonfire/features/channels/views/channel_context_menu.dart';
import 'package:bonfire/features/channels/views/channel_management.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/models/open_tab.dart';
import 'package:bonfire/features/channels/utils/channel_reorder.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/channels/utils/channel_sort.dart';
import 'package:bonfire/features/developer/services/mcp_home_bridge.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/views/accord_member_list.dart';
import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/features/onboarding/models/onboarding_step.dart';
import 'package:bonfire/features/onboarding/views/onboarding_anchors.dart';
import 'package:bonfire/features/messaging/views/thread_view.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/controllers/role_preview.dart';
import 'package:bonfire/features/spaces/models/space_folder.dart';
import 'package:bonfire/features/spaces/views/role_preview_banner.dart';
import 'package:bonfire/features/spaces/views/accord_discovery.dart';
import 'package:bonfire/features/spaces/views/accord_gates.dart';
import 'package:bonfire/features/spaces/views/accord_channel_reorder.dart';
import 'package:bonfire/features/spaces/views/accord_invites.dart';
import 'package:bonfire/features/spaces/views/accord_search.dart';
import 'package:bonfire/features/user/views/self_status_button.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/views/accord_space_settings.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/features/updates/views/update_banner.dart';
import 'package:bonfire/features/updates/views/web_update_prompt.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/color_swatch_chip.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/shared/components/drawer_swipe_area.dart';
import 'package:bonfire/shared/components/horizontal_wheel_scroll.dart';
import 'package:bonfire/shared/components/server_unreachable.dart';
import 'package:bonfire/shared/models/server_entity_key.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart'
    show isVoiceDoubleTap;
import 'package:bonfire/features/voice/views/voice_bar.dart';
import 'package:bonfire/features/voice/views/voice_participants.dart';
import 'package:bonfire/features/voice/views/voice_pip_overlay.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'accord_home_rail.dart';
part 'accord_home_rail_tiles.dart';
part 'accord_home_space_actions.dart';
part 'accord_home_tabs.dart';
part 'accord_home_channels.dart';

/// The primary Accord screen: a three-pane view (space rail → channel list →
/// message history) wired to the Accord controllers.
class AccordHomeScreen extends ConsumerStatefulWidget {
  const AccordHomeScreen({
    super.key,
    this.initialSpaceId,
    this.initialChannelId,
    this.initialChannelName,
    this.initialMessageId,
  });

  /// A space to focus as soon as the screen mounts (e.g. when arriving from the
  /// admin panel's "Open"). Takes precedence over the restored last selection.
  final String? initialSpaceId;
  final String? initialChannelId;
  final String? initialChannelName;
  final String? initialMessageId;

  @override
  ConsumerState<AccordHomeScreen> createState() => _AccordHomeScreenState();
}

class _AccordHomeScreenState extends ConsumerState<AccordHomeScreen> {
  // A space navigated to from the rail whose default channel should auto-open as
  // a tab once its channels load. Cleared as soon as a tab is opened/activated.
  String? _pendingOpenSpaceId;
  String? _pendingChannelId;
  String? _pendingChannelName;
  String? _pendingMessageId;
  String? _deepLinkChannelInFlight;
  bool _deepLinkFailureScheduled = false;
  // The channel id currently being auto-opened in a post-frame callback, used to
  // avoid scheduling the same open twice while the gateway round-trips.
  String? _autoOpenInFlight;
  // The space we've already run the rules interstitial check for this session.
  String? _rulesCheckedSpaceId;
  // Member-list visibility, toggled by the user and by the MCP `navigate` group.
  bool _memberListVisible = true;

  // Live channel-list width while the user drags the divider; null when not
  // dragging (the persisted [AccordSettings.channelListWidth] is used instead).
  // Kept local so each drag frame doesn't write to Hive — the final width is
  // persisted on drag end.
  double? _dragChannelWidth;

  /// Scaffold for the narrow (mobile) layout, so the channel-list drawer and
  /// member-list end-drawer can be opened/closed programmatically.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Below this width the three panes can't sit side-by-side, so the channel
  /// list and member list move into drawers (see [build]).
  static const double _wideLayoutBreakpoint = 720;

  @override
  void initState() {
    super.initState();
    _pendingOpenSpaceId = widget.initialSpaceId;
    _pendingChannelId = widget.initialChannelId;
    _pendingChannelName = widget.initialChannelName;
    _pendingMessageId = widget.initialMessageId;
    mcpHomeBridge.registerAll(_mcpNavHandlers());
    // Passive, throttled startup update check (gated on the setting).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(updateControllerProvider.notifier).maybeCheckOnStartup();
      }
    });
  }

  @override
  void didUpdateWidget(AccordHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSpaceId != widget.initialSpaceId ||
        oldWidget.initialChannelId != widget.initialChannelId ||
        oldWidget.initialChannelName != widget.initialChannelName ||
        oldWidget.initialMessageId != widget.initialMessageId) {
      _pendingOpenSpaceId = widget.initialSpaceId;
      _pendingChannelId = widget.initialChannelId;
      _pendingChannelName = widget.initialChannelName;
      _pendingMessageId = widget.initialMessageId;
      _deepLinkChannelInFlight = null;
      _deepLinkFailureScheduled = false;
    }
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
      await _openChannel(
        args['channel_id'] as String,
        spaceId: args['space_id'] as String,
      );
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
          .read(accordMessagesControllerProvider(ref.readActiveServerKey() ?? '', channelId))
          ?.firstWhereOrNull((m) => m.id == messageId);
      if (root == null) return {'error': 'Message not loaded'};
      showAccordThread(context, channelId: channelId, root: root);
      return {'ok': true};
    },
    // Reveals the *current* call's channel; it never joins one (matching the
    // rest of the app after #202 — navigation is never a connect). It stays an
    // error when nothing is connected rather than silently joining something:
    // `select_channel` already opens any voice channel's lobby.
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
      return {'ok': true, 'visible': _memberListVisible};
    },
    'toggle_search': (args) async {
      if (!mounted) return _mcpUnmounted;
      final spaceId = mcpHomeBridge.state.spaceId;
      if (spaceId == null || spaceId.isEmpty) {
        return {'error': 'No space selected'};
      }
      await showAccordSearch(context, spaceId: spaceId);
      return {'ok': true};
    },
  };

  static const Map<String, dynamic> _mcpUnmounted = {
    'error': 'Home screen not mounted',
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
    final existing = ref
        .read(openTabsControllerProvider)
        .tabs
        .lastWhereOrNull(
          (t) => t.serverKey == serverKey && t.spaceId == spaceId,
        );
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
    ref
        .read(settingsControllerProvider.notifier)
        .setLastSelection(tab.serverKey, tab.spaceId, tab.channelId);
  }

  /// Opens (or switches to) a tab for [channelId] in [spaceId] on the active
  /// server. Preserves the NSFW gate and voice-join behaviour the single
  /// selection used to carry.
  Future<bool> _openChannel(String channelId, {required String spaceId}) async {
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    if (activeKey == null) return false;
    final channel = ref
        .read(accordChannelsControllerProvider(activeKey, spaceId))
        ?.firstWhereOrNull((c) => c.id == channelId);
    if (channel != null && channel.nsfw) {
      final ok = await confirmNsfwGate(
        context,
        ref,
        channelId: channelId,
        channelName: channel.name ?? 'channel',
      );
      if (!ok || !mounted) return false;
    }
    // Opening a voice channel never connects: the message pane renders the voice
    // view, which shows the lobby (participants + chat + a "Join Voice" button)
    // until the user explicitly joins. An accidental click used to be an
    // unmuted, audible join — see issue #202. The explicit join affordances are
    // the lobby button, the channel row's hover button / double-click, and the
    // row's context menu.
    ref
        .read(openTabsControllerProvider.notifier)
        .open(
          OpenTab(
            channelId: channelId,
            spaceId: spaceId,
            serverKey: activeKey,
            name: channel?.name ?? channelId,
          ),
        );
    // Voice channels carry a text chat and so carry unread state like any other
    // channel; opening one clears it exactly the same way (the ack matters most
    // here — a voice channel's messages are rarely cached, so without the
    // `last_message_id` fallback the badge would come back on every connect).
    _markChannelRead(channelId, fallbackMessageId: channel?.lastMessageId);
    setState(() => _pendingOpenSpaceId = null);
    ref
        .read(settingsControllerProvider.notifier)
        .setLastSelection(activeKey, spaceId, channelId);
    return true;
  }

  /// Opens an exact channel destination once its cache is available, then
  /// fetches and opens a shared thread/message root. The direct fetch means a
  /// link still works when the target is older than the initial history page.
  void _scheduleDeepLinkOpen(AccordChannel channel, String spaceId) {
    final serverKey = ref.readActiveServerKey();
    if (serverKey == null) return;
    final channelKey = ServerEntityKey(serverKey, channel.id).encoded;
    if (_deepLinkChannelInFlight == channelKey) return;
    _deepLinkChannelInFlight = channelKey;
    final messageId = _pendingMessageId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || ref.readActiveServerKey() != serverKey) return;
      final opened = await _openChannel(channel.id, spaceId: spaceId);
      if (!mounted || ref.readActiveServerKey() != serverKey) return;
      _deepLinkChannelInFlight = null;
      if (!opened) return;

      setState(() {
        _pendingChannelId = null;
        _pendingChannelName = null;
        _pendingMessageId = null;
      });
      if (messageId == null || messageId.isEmpty) return;

      final cached = ref
          .read(accordMessagesControllerProvider(serverKey, channel.id))
          ?.firstWhereOrNull((message) => message.id == messageId);
      var root = cached;
      if (root == null) {
        final client = ref.accordClient;
        final result = client == null
            ? null
            : await client.messages.fetch(channel.id, messageId);
        if (result?.data case final AccordMessage message) root = message;
      }
      if (!mounted || ref.readActiveServerKey() != serverKey) return;
      if (root == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('The linked message is unavailable.')),
        );
        return;
      }
      showAccordThread(
        context,
        channelId: channel.id,
        root: root,
        spaceId: spaceId,
      );
    });
  }

  void _scheduleDeepLinkFailure() {
    if (_deepLinkFailureScheduled) return;
    _deepLinkFailureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _pendingChannelId = null;
        _pendingChannelName = null;
        _pendingMessageId = null;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('The linked channel is unavailable.')),
      );
    });
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
      ref
          .read(openTabsControllerProvider.notifier)
          .open(
            OpenTab(
              channelId: channel.id,
              spaceId: spaceId,
              serverKey: activeKey,
              name: channel.name ?? channel.id,
            ),
          );
      _markChannelRead(channel.id, fallbackMessageId: channel.lastMessageId);
      ref
          .read(settingsControllerProvider.notifier)
          .setLastSelection(activeKey, spaceId, channel.id);
      if (_pendingOpenSpaceId != null) {
        setState(() => _pendingOpenSpaceId = null);
      }
    });
  }

  /// Marks [channelId] read locally and POSTs `channels.ack` on the active
  /// connection. See [markChannelRead] for why the ack (and its
  /// [fallbackMessageId]) is what makes the badge stay gone.
  void _markChannelRead(String channelId, {String? fallbackMessageId}) =>
      markChannelRead(ref, channelId, fallbackMessageId: fallbackMessageId);

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
    ref.listen(openTabsControllerProvider.select((s) => s.activeTab), (
      previous,
      next,
    ) {
      if (next == null) return;
      final activeKey = ref.read(connectionsControllerProvider).activeKey;
      if (next.serverKey != activeKey) {
        ref.read(accordAuthProvider.notifier).setActiveServer(next.serverKey);
      }
    });

    // Prune tabs belonging to a server that was logged out / removed.
    ref.listen(
      connectionsControllerProvider.select(
        (s) => s.connections.map((c) => c.key).toSet(),
      ),
      (previous, next) {
        if (previous == null) return;
        final removed = previous.difference(next);
        if (removed.isEmpty) return;
        final notifier = ref.read(openTabsControllerProvider.notifier);
        for (final key in removed) {
          notifier.removeForServer(key);
        }
      },
    );

    final spaces = ref.watch(spacesControllerProvider);
    final activeKey = ref.watch(
      connectionsControllerProvider.select((s) => s.activeKey),
    );
    final activeTab = ref.watch(
      openTabsControllerProvider.select((s) => s.activeTab),
    );

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
      // No pending/active selection (e.g. a fresh launch with no open tabs):
      // restore the last selected space when it still exists, else default to
      // the first. Mirrors the reference's `last_space_id` restore.
      final lastSpaceId = ref
          .read(settingsControllerProvider)
          .lastSpaceFor(activeKey ?? '');
      effectiveSpaceId =
          lastSpaceId.isNotEmpty && spaces.any((s) => s.id == lastSpaceId)
          ? lastSpaceId
          : spaces.first.id;
    }

    _maybeCheckRules(spaces?.firstWhereOrNull((s) => s.id == effectiveSpaceId));

    final channels = effectiveSpaceId == null
        ? null
        : ref.watch(accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', effectiveSpaceId));

    final firstText = channels?.where((c) => c.type == 'text').firstOrNull;

    // The channel shown in the message pane: the active tab when it lives in the
    // shown space, otherwise the space's default channel (auto-opened as a tab).
    String? shownChannelId;
    final activeTabHere =
        activeTab != null &&
        activeTab.serverKey == activeKey &&
        (channels?.any((c) => c.id == activeTab.channelId) ?? false);
    final requestedChannel = channels == null
        ? null
        : resolveDeepLinkChannel(
            channels,
            channelId: _pendingChannelId,
            channelName: _pendingChannelName,
          );
    final hasPendingChannel =
        _pendingChannelId != null || _pendingChannelName != null;
    if (requestedChannel != null && effectiveSpaceId != null) {
      shownChannelId = requestedChannel.id;
      _scheduleDeepLinkOpen(requestedChannel, effectiveSpaceId);
    } else if (hasPendingChannel && channels != null) {
      _scheduleDeepLinkFailure();
    } else if (activeTabHere) {
      shownChannelId = activeTab.channelId;
    } else if (effectiveSpaceId != null && channels != null) {
      // Restore the last selected channel within the restored space when it
      // still exists; otherwise fall back to the space's first text channel.
      // Routed through [_scheduleAutoOpen] (not [_openChannel]) so restoring a
      // voice channel shows its lobby instead of auto-rejoining the call.
      final settings = ref.read(settingsControllerProvider);
      final lastSpaceId = settings.lastSpaceFor(activeKey ?? '');
      final lastChannelId = settings.lastChannelFor(activeKey ?? '');
      final lastChannel =
          lastSpaceId == effectiveSpaceId && lastChannelId.isNotEmpty
          ? channels.firstWhereOrNull((c) => c.id == lastChannelId)
          : null;
      final restore = lastChannel ?? firstText;
      if (restore != null) {
        shownChannelId = restore.id;
        _scheduleAutoOpen(restore, effectiveSpaceId);
      }
    }

    // Let the notification layer skip the channel that's on screen.
    accordVisibleChannel = activeKey == null || shownChannelId == null
        ? null
        : (serverKey: activeKey, channelId: shownChannelId);

    mcpHomeBridge.setStateReader(
      () => (
        spaceId: effectiveSpaceId,
        channelId: shownChannelId,
        memberListVisible: _memberListVisible,
      ),
    );

    final shownSpaceId = effectiveSpaceId;
    final colors = BonfireThemeExtension.of(context);

    final rail = OnboardingAnchor(
      anchor: OnboardingAnchorId.spaceRail,
      child: _SpaceRail(
        selectedSpaceId: effectiveSpaceId,
        onSelect: _selectSpace,
        onAddServer: () => showAddServerDialog(context),
        onSwitchAccount: () => context.push('/switcher'),
        onOpenSettings: () => context.push('/settings'),
        onLogout: () async {
          if (!await confirmLogout(context)) return;
          if (!context.mounted) return;
          ref.read(accordAuthProvider.notifier).logout();
        },
      ),
    );

    Widget channelList({required bool inDrawer}) => OnboardingAnchor(
      anchor: OnboardingAnchorId.channelList,
      child: _ChannelList(
        spaceId: effectiveSpaceId,
        spaceName: spaces
            ?.firstWhereOrNull((s) => s.id == effectiveSpaceId)
            ?.name,
        channels: channels,
        selectedChannelId: shownChannelId,
        onSelect: shownSpaceId == null
            ? (_) {}
            : (channelId) {
                _openChannel(channelId, spaceId: shownSpaceId);
                // On narrow layouts the list is a drawer — close it so the
                // freshly-opened channel is visible.
                if (inDrawer) _scaffoldKey.currentState?.closeDrawer();
              },
      ),
    );

    final messageArea = Column(
      children: [
        _TabStrip(onSelect: _selectTab),
        Expanded(
          child: MessagePane(
            channel: channels?.firstWhereOrNull((c) => c.id == shownChannelId),
            channelId: shownChannelId,
            spaceId: effectiveSpaceId,
          ),
        ),
      ],
    );

    final pip = VoicePipOverlay(
      shownChannelId: shownChannelId,
      onOpen: (channelId, spaceId) async {
        await _openChannel(channelId, spaceId: spaceId);
      },
    );

    final hasMembers = effectiveSpaceId != null;

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideLayoutBreakpoint;
        if (wide) {
          final savedWidth = ref.watch(
            settingsControllerProvider.select((s) => s.channelListWidth),
          );
          final channelWidth = (_dragChannelWidth ?? savedWidth).clamp(
            AccordSettings.minChannelListWidth,
            AccordSettings.maxChannelListWidth,
          );
          return Stack(
            children: [
              Row(
                children: [
                  rail,
                  SizedBox(
                    width: channelWidth,
                    child: channelList(inDrawer: false),
                  ),
                  _ChannelListResizeHandle(
                    onDragDelta: (dx) => setState(() {
                      _dragChannelWidth = (channelWidth + dx).clamp(
                        AccordSettings.minChannelListWidth,
                        AccordSettings.maxChannelListWidth,
                      );
                    }),
                    onDragEnd: () {
                      final width = _dragChannelWidth;
                      if (width != null) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .setChannelListWidth(width);
                      }
                      setState(() => _dragChannelWidth = null);
                    },
                  ),
                  Expanded(child: messageArea),
                  if (hasMembers && _memberListVisible)
                    AccordMemberList(spaceId: effectiveSpaceId),
                ],
              ),
              pip,
            ],
          );
        }
        // Narrow: rail + channel list move into a drawer, members into an
        // end-drawer, so the message pane keeps full width instead of
        // overflowing.
        //
        // Wrap in [PopScope] so Android's left-edge back swipe (which shares the
        // same edge as the swipe-to-open-sidebar gesture) steps through / opens
        // the drawers instead of popping the route (#125).
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            final scaffold = _scaffoldKey.currentState;
            if (scaffold == null) return;
            if (scaffold.isEndDrawerOpen) {
              scaffold.closeEndDrawer();
            } else if (scaffold.isDrawerOpen) {
              scaffold.closeDrawer();
            } else {
              scaffold.openDrawer();
            }
          },
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: colors.background,
            drawerEdgeDragWidth: 48,
            drawer: Drawer(
              width: 292,
              backgroundColor: colors.background,
              child: SafeArea(
                child: Row(
                  children: [
                    rail,
                    Expanded(child: channelList(inDrawer: true)),
                  ],
                ),
              ),
            ),
            endDrawer: hasMembers
                ? Drawer(
                    width: 260,
                    backgroundColor: colors.background,
                    child: SafeArea(
                      child: AccordMemberList(spaceId: effectiveSpaceId),
                    ),
                  )
                : null,
            body: Stack(
              children: [
                // Inset the mobile chrome below the OS status bar / nav bar.
                // The pip overlay stays outside so it can use the full screen.
                //
                // [DrawerSwipeArea] extends swipe-to-open past the edge strip
                // `drawerEdgeDragWidth` covers, without stealing horizontal
                // drags from the tab strip or the voice rails (#125).
                DrawerSwipeArea(
                  scaffoldKey: _scaffoldKey,
                  child: SafeArea(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            OnboardingAnchor(
                              anchor: OnboardingAnchorId.navMenu,
                              child: IconButton(
                                tooltip: 'Channels',
                                icon: Icon(
                                  Icons.menu,
                                  color: colors.dirtyWhite,
                                ),
                                onPressed: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                              ),
                            ),
                            Expanded(child: _TabStrip(onSelect: _selectTab)),
                            if (hasMembers)
                              IconButton(
                                tooltip: 'Members',
                                icon: Icon(
                                  Icons.people_alt_outlined,
                                  color: colors.dirtyWhite,
                                ),
                                onPressed: () =>
                                    _scaffoldKey.currentState?.openEndDrawer(),
                              ),
                          ],
                        ),
                        Expanded(
                          child: MessagePane(
                            channel: channels?.firstWhereOrNull(
                              (c) => c.id == shownChannelId,
                            ),
                            channelId: shownChannelId,
                            spaceId: effectiveSpaceId,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pip,
              ],
            ),
          ),
        );
      },
    );

    return Column(
      children: [
        const UpdateBanner(),
        const WebUpdatePrompt(),
        const RolePreviewBanner(),
        Expanded(child: body),
      ],
    );
  }
}

/// Returns the unique channel selected by an ID or share-link name. Names are
/// deliberately fail-closed when duplicated; a link must not silently open a
/// different channel with the same display name.
@visibleForTesting
AccordChannel? resolveDeepLinkChannel(
  List<AccordChannel> channels, {
  String? channelId,
  String? channelName,
}) {
  if (channelId != null && channelId.isNotEmpty) {
    return channels.firstWhereOrNull((channel) => channel.id == channelId);
  }
  if (channelName == null || channelName.isEmpty) return null;
  final matches = channels.where((channel) => channel.name == channelName);
  return matches.length == 1 ? matches.single : null;
}
