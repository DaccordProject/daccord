import 'package:accordkit/accordkit.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/components/channel_management.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
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
import 'package:bonfire/features/spaces/views/accord_invites.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/features/spaces/views/accord_search.dart';
import 'package:bonfire/features/user/components/self_status_button.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/spaces/views/accord_space_settings.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// First Accord-native screen: a three-pane read view (space rail → channel
/// list → message history) wired to the Accord controllers. This is the
/// scaffold the firebridge UI is being migrated onto; it deliberately covers
/// only the read path (no DMs, folders, composer, or member resolution yet).
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
        channelId: channelId,
        channelName: channel.name ?? 'channel',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _selectedChannelId = channelId);
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

class _SpaceRail extends ConsumerWidget {
  const _SpaceRail({
    required this.selectedSpaceId,
    required this.onSelect,
    required this.onAddServer,
    required this.onSwitchAccount,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final String? selectedSpaceId;

  /// Called with the owning server's connection key and the selected space id.
  final void Function(String serverKey, String spaceId) onSelect;
  final VoidCallback onAddServer;
  final VoidCallback onSwitchAccount;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final connections = ref.watch(connectionsControllerProvider);
    final activeKey = connections.activeKey;
    // The active connection's authoritative, live space list (includes spaces
    // just joined via discovery before a gateway event arrives).
    final liveActiveSpaces = ref.watch(spacesControllerProvider);
    final multi = connections.hasMultiple;

    final railItems = <Widget>[];
    for (final conn in connections.connections) {
      final isActive = conn.key == activeKey;
      final spaces = isActive ? (liveActiveSpaces ?? conn.spaces) : conn.spaces;
      final cdnUrl = conn.session.server.cdnUrl;

      if (multi) {
        railItems.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
            child: _ServerGroupHeader(
              name: conn.session.server.name ?? conn.session.server.baseUrl,
              status: conn.status,
              active: isActive,
            ),
          ),
        );
      }

      for (final space in spaces) {
        railItems.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _SpaceIcon(
              space: space,
              selected: isActive && space.id == selectedSpaceId,
              cdnUrl: cdnUrl,
              onTap: () => onSelect(conn.key, space.id),
            ),
          ),
        );
      }
    }

    railItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _AddServerButton(onTap: onAddServer),
      ),
    );

    return Container(
      width: 72,
      color: colors.background,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: railItems,
            ),
          ),
          IconButton(
            tooltip: 'Direct messages',
            onPressed: () => showAccordDirectMessages(context),
            icon: Icon(Icons.chat_bubble_outline,
                size: 20, color: colors.dirtyWhite),
          ),
          IconButton(
            tooltip: 'Explore public spaces',
            onPressed: () => showAccordDiscovery(context),
            icon: Icon(Icons.explore, size: 22, color: colors.dirtyWhite),
          ),
          const SelfStatusButton(),
          IconButton(
            tooltip: 'Switch account',
            onPressed: onSwitchAccount,
            icon: Icon(Icons.switch_account, color: colors.dirtyWhite, size: 20),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: Icon(Icons.settings, color: colors.dirtyWhite, size: 20),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: onLogout,
            icon: Icon(Icons.logout, color: colors.dirtyWhite, size: 20),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SpaceIcon extends StatelessWidget {
  const _SpaceIcon({
    required this.space,
    required this.selected,
    required this.cdnUrl,
    required this.onTap,
  });

  final AccordSpace space;
  final bool selected;
  final String? cdnUrl;
  final VoidCallback onTap;

  String get _initials {
    final name = space.name.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final iconUrl = _spaceIconUrl(space, cdnUrl);
    final radius = BorderRadius.circular(selected ? 16 : 24);
    final fallback = Text(
      _initials,
      style:
          Theme.of(context).textTheme.titleSmall!.copyWith(color: Colors.white),
    );
    return Center(
      child: Tooltip(
        message: space.name,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 48,
            height: 48,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: selected ? colors.primary : colors.darkGray,
              borderRadius: radius,
            ),
            alignment: Alignment.center,
            child: iconUrl == null
                ? fallback
                : CachedNetworkImage(
                    imageUrl: iconUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => fallback,
                    errorWidget: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}

/// A slim per-server separator shown in the rail only when more than one server
/// is connected: the server's initial, its name as a tooltip, and a status dot.
class _ServerGroupHeader extends StatelessWidget {
  const _ServerGroupHeader({
    required this.name,
    required this.status,
    required this.active,
  });

  final String name;
  final ConnectionStatus status;
  final bool active;

  Color get _statusColor {
    switch (status) {
      case ConnectionStatus.ready:
      case ConnectionStatus.connected:
        return const Color(0xFF43B581);
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return const Color(0xFFFAA61A);
      case ConnectionStatus.disconnected:
        return const Color(0xFFF04747);
    }
  }

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Tooltip(
        message: name,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.darkGray,
            shape: BoxShape.circle,
            border: active
                ? Border.all(color: colors.primary, width: 2)
                : null,
          ),
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Text(
                _initial,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.dirtyWhite),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.background, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Add a Server" (+) affordance at the foot of the rail's space list.
class _AddServerButton extends StatelessWidget {
  const _AddServerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Tooltip(
        message: 'Add a server',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.darkGray,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add, color: Color(0xFF43B581)),
          ),
        ),
      ),
    );
  }
}

class _ChannelList extends ConsumerWidget {
  const _ChannelList({
    required this.spaceId,
    required this.spaceName,
    required this.channels,
    required this.selectedChannelId,
    required this.onSelect,
  });

  final String? spaceId;
  final String? spaceName;
  final List<AccordChannel>? channels;
  final String? selectedChannelId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final id = spaceId;
    final space = id == null
        ? null
        : ref.watch(
            spacesControllerProvider
                .select((s) => s?.firstWhereOrNull((sp) => sp.id == id)),
          );
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
          (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null),
    );
    final bannerUrl =
        space == null ? null : accordSpaceBannerUrl(space, cdnUrl);

    // Show the settings gear only to members who can manage the space or roles,
    // and the channel-management affordances to those with manage_channels.
    var canManage = false;
    var canManageChannels = false;
    var canInvite = false;
    if (id != null) {
      final currentUserId = ref.watch(
        accordAuthProvider.select(
            (s) => s is AccordAuthLoggedIn ? s.session.userId : null),
      );
      final isAdmin = ref.watch(
        accordAuthProvider.select(
            (s) => s is AccordAuthLoggedIn ? s.session.isAdmin : false),
      );
      final members = ref.watch(accordMembersControllerProvider(id));
      final perms = accordEffectivePermissions(
        space: space,
        selfMember: currentUserId == null ? null : members?[currentUserId],
        roles: space?.roles ?? const <AccordRole>[],
        currentUserId: currentUserId ?? '',
        currentUserIsAdmin: isAdmin,
      );
      canManage = accordHasPermission(perms, AccordPermission.manageSpace) ||
          accordHasPermission(perms, AccordPermission.manageRoles) ||
          accordHasPermission(perms, AccordPermission.viewAuditLog);
      canManageChannels =
          accordHasPermission(perms, AccordPermission.manageChannels);
      canInvite =
          accordHasPermission(perms, AccordPermission.createInvites);
    }

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colors.foreground,
        border: Border(
          left: BorderSide(color: colors.background, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bannerUrl != null)
            CachedNetworkImage(
              imageUrl: bannerUrl,
              height: 100,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          Container(
            height: 48,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 16, right: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.background, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    spaceName ?? 'Select a space',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (id != null)
                  IconButton(
                    tooltip: 'Search',
                    onPressed: () async {
                      final selection =
                          await showAccordSearch(context, spaceId: id);
                      if (selection != null) onSelect(selection.channelId);
                    },
                    icon: Icon(Icons.search,
                        size: 18, color: colors.dirtyWhite),
                  ),
                if (canInvite && id != null)
                  IconButton(
                    tooltip: 'Invite people',
                    onPressed: () => showAccordInvites(context, spaceId: id),
                    icon: Icon(Icons.person_add,
                        size: 18, color: colors.dirtyWhite),
                  ),
                if (canManageChannels && id != null)
                  IconButton(
                    tooltip: 'Create channel',
                    onPressed: () =>
                        showCreateChannelDialog(context, spaceId: id),
                    icon: Icon(Icons.add,
                        size: 18, color: colors.dirtyWhite),
                  ),
                if (canManage && id != null)
                  IconButton(
                    tooltip: 'Space settings',
                    onPressed: () =>
                        showAccordSpaceSettings(context, spaceId: id),
                    icon: Icon(Icons.settings,
                        size: 18, color: colors.dirtyWhite),
                  ),
              ],
            ),
          ),
          Expanded(
            child: channels == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: _buildChannelEntries(
                      context,
                      spaceId: id,
                      channels: channels!,
                      selectedChannelId: selectedChannelId,
                      onSelect: onSelect,
                      canManageChannels: canManageChannels,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Groups [channels] into uncategorized channels (rendered first) followed by
/// each category with its child channels. When [canManageChannels] is true,
/// categories show an inline "add channel" button and channels an edit button.
List<Widget> _buildChannelEntries(
  BuildContext context, {
  required String? spaceId,
  required List<AccordChannel> channels,
  required String? selectedChannelId,
  required ValueChanged<String> onSelect,
  required bool canManageChannels,
}) {
  final categories = channels.where((c) => c.type == 'category').toList();
  final leaves = channels.where((c) => c.type != 'category').toList();
  final byParent = <String?, List<AccordChannel>>{};
  for (final c in leaves) {
    byParent.putIfAbsent(c.parentId, () => []).add(c);
  }

  Widget tile(AccordChannel channel) => _ChannelTile(
        channel: channel,
        selected: channel.id == selectedChannelId,
        onTap: () => onSelect(channel.id),
        onEdit: canManageChannels && spaceId != null
            ? () => showEditChannelDialog(context,
                spaceId: spaceId, channel: channel)
            : null,
      );

  final entries = <Widget>[];
  for (final channel in byParent[null] ?? const <AccordChannel>[]) {
    entries.add(tile(channel));
  }
  for (final category in categories) {
    entries.add(_CategoryHeader(
      category: category,
      onAdd: canManageChannels && spaceId != null
          ? () => showCreateChannelDialog(context,
              spaceId: spaceId, parentId: category.id)
          : null,
      onEdit: canManageChannels && spaceId != null
          ? () => showEditChannelDialog(context,
              spaceId: spaceId, channel: category)
          : null,
    ));
    for (final channel in byParent[category.id] ?? const <AccordChannel>[]) {
      entries.add(tile(channel));
    }
  }
  return entries;
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.category,
    this.onAdd,
    this.onEdit,
  });

  final AccordChannel category;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (category.name ?? '').toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: colors.gray,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
          if (onEdit != null)
            InkWell(
              onTap: onEdit,
              child: Icon(Icons.settings, size: 14, color: colors.gray),
            ),
          if (onAdd != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onAdd,
              child: Icon(Icons.add, size: 16, color: colors.gray),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChannelTile extends StatefulWidget {
  const _ChannelTile({
    required this.channel,
    required this.selected,
    required this.onTap,
    this.onEdit,
  });

  final AccordChannel channel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _hovered = false;

  IconData get _glyph {
    switch (widget.channel.type) {
      case 'voice':
        return Icons.volume_up;
      case 'forum':
        return Icons.forum;
      case 'announcement':
        return Icons.campaign;
      default:
        return Icons.tag;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final channel = widget.channel;
    final enabled = channel.type == 'text' ||
        channel.type == 'forum' ||
        channel.type == 'announcement';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: widget.selected ? colors.darkGray : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? widget.onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Icon(_glyph,
                      size: 18,
                      color: enabled ? colors.dirtyWhite : colors.gray),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      channel.name ?? channel.id,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                            color: enabled ? colors.dirtyWhite : colors.gray,
                          ),
                    ),
                  ),
                  if (widget.onEdit != null && _hovered)
                    InkWell(
                      onTap: widget.onEdit,
                      child: Icon(Icons.settings,
                          size: 14, color: colors.gray),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessagePane extends ConsumerStatefulWidget {
  const _MessagePane({
    required this.channel,
    required this.channelId,
    required this.spaceId,
  });

  final AccordChannel? channel;
  final String? channelId;
  final String? spaceId;

  @override
  ConsumerState<_MessagePane> createState() => _MessagePaneState();
}

class _MessagePaneState extends ConsumerState<_MessagePane> {
  AccordMessage? _replyTo;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_MessagePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear any pending reply when switching channels.
    if (oldWidget.channelId != widget.channelId && _replyTo != null) {
      _replyTo = null;
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Watches for the user scrolling near the top of the history (with
  /// `reverse: true`, that means approaching [maxScrollExtent]) and pages in
  /// older messages. The controller dedupes concurrent calls so we can fire
  /// this aggressively on every scroll tick.
  void _onScroll() {
    final channelId = widget.channelId;
    if (channelId == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels > 240) return;
    final notifier =
        ref.read(accordMessagesControllerProvider(channelId).notifier);
    if (notifier.isLoadingOlder || !notifier.hasMoreOlder) return;
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    if (client == null) return;
    notifier.loadOlder(client);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final channel = widget.channel;
    final channelId = widget.channelId;
    final spaceId = widget.spaceId;

    if (channelId == null) {
      return Container(
        color: colors.background,
        alignment: Alignment.center,
        child: Text('Select a channel',
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    final messages = ref.watch(accordMessagesControllerProvider(channelId));
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(spaceId));
    final userCache = ref.watch(accordUsersControllerProvider);
    final space = spaceId == null
        ? null
        : ref.watch(spacesControllerProvider
            .select((s) => s?.firstWhereOrNull((sp) => sp.id == spaceId)));
    final roles = space?.roles ?? const <AccordRole>[];
    final currentUserId = ref.watch(
      accordAuthProvider.select(
          (s) => s is AccordAuthLoggedIn ? s.session.userId : null),
    );
    final isAdmin = ref.watch(
      accordAuthProvider.select(
          (s) => s is AccordAuthLoggedIn ? s.session.isAdmin : false),
    );
    final myRoles = (currentUserId == null ? null : members?[currentUserId])
            ?.roles ??
        const <String>[];

    final perms = accordEffectivePermissions(
      space: space,
      selfMember: currentUserId == null ? null : members?[currentUserId],
      roles: roles,
      currentUserId: currentUserId ?? '',
      currentUserIsAdmin: isAdmin,
    );
    final canManageMessages =
        accordHasPermission(perms, AccordPermission.manageMessages);
    final canSend = accordHasPermission(perms, AccordPermission.sendMessages);

    if (channel?.type == 'forum') {
      return Container(
        color: colors.background,
        child: Column(
          children: [
            Container(
              height: 48,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 16, right: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.foreground, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.forum, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(channel?.name ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ForumChannelView(
                channelId: channelId,
                spaceId: spaceId,
                canPost: canSend || canManageMessages,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: colors.background,
      child: Column(
        children: [
          Container(
            height: 48,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 16, right: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.foreground, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(channel?.type == 'announcement'
                        ? Icons.campaign
                        : Icons.tag,
                    size: 18, color: colors.dirtyWhite),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(channel?.name ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: 'Pinned messages',
                  onPressed: () => showPinnedMessages(
                    context,
                    channelId: channelId,
                    spaceId: spaceId,
                    canManage: canManageMessages,
                  ),
                  icon: Icon(Icons.push_pin_outlined,
                      size: 18, color: colors.dirtyWhite),
                ),
                _MuteButton(channelId: channelId),
              ],
            ),
          ),
          Expanded(
            child: messages == null
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? Center(
                        child: Text('No messages yet',
                            style: Theme.of(context).textTheme.bodyMedium),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        // One extra slot at the top of history (rendered last
                        // under `reverse: true`) shows a spinner while older
                        // pages load and a "Beginning of channel" hint once we
                        // hit the start of history.
                        itemCount: messages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            return _OlderHistoryHeader(channelId: channelId);
                          }
                          final messageIndex = messages.length - 1 - index;
                          final message = messages[messageIndex];
                          // Group with the previous (older) message when it's
                          // from the same author, this message isn't a reply,
                          // and the two are close together in time. Grouped
                          // rows drop the repeated avatar/name/timestamp header.
                          final prev = messageIndex > 0
                              ? messages[messageIndex - 1]
                              : null;
                          final grouped =
                              _isGrouped(previous: prev, current: message);
                          final author = members?[message.authorId];
                          // Members only loads the first page; backfill authors
                          // outside it from the on-demand user cache.
                          AccordUser? authorUser;
                          if (author == null && members != null) {
                            authorUser = userCache[message.authorId];
                            if (authorUser == null) {
                              ref
                                  .read(accordUsersControllerProvider.notifier)
                                  .ensure(message.authorId);
                            }
                          }
                          final colorRole = author == null
                              ? null
                              : memberColorRole(author, roles);
                          final isOwn = currentUserId != null &&
                              message.authorId == currentUserId;
                          final mentionsMe = !isOwn &&
                              currentUserId != null &&
                              (message.mentionEveryone ||
                                  message.mentions.contains(currentUserId) ||
                                  message.mentionRoles
                                      .any(myRoles.contains));
                          return _MessageRow(
                            message: message,
                            grouped: grouped,
                            author: author,
                            authorUser: authorUser,
                            nameColor: colorRole == null
                                ? null
                                : accordRoleColor(colorRole.color),
                            channelId: channelId,
                            spaceId: spaceId,
                            isOwn: isOwn,
                            mentionsMe: mentionsMe,
                            canManageMessages: canManageMessages,
                            onReply: () =>
                                setState(() => _replyTo = message),
                          );
                        },
                      ),
          ),
          _TypingIndicator(channelId: channelId, spaceId: spaceId),
          _Composer(
            channelId: channelId,
            channelName: channel?.name,
            spaceId: spaceId,
            replyingTo: _replyTo,
            replyName: _replyTo == null
                ? null
                : accordMemberName(members?[_replyTo!.authorId],
                    fallback: _replyTo!.authorId),
            onCancelReply: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }
}

/// How close in time two consecutive same-author messages must be to collapse
/// into a single group (matching the reference client's denser layout).
const Duration _messageGroupWindow = Duration(minutes: 7);

/// Whether [current] should render as a continuation of [previous] — same
/// author, not a reply, and within [_messageGroupWindow]. Grouped rows hide the
/// repeated avatar/name/timestamp header.
bool _isGrouped({
  required AccordMessage? previous,
  required AccordMessage current,
}) {
  if (previous == null) return false;
  if (previous.authorId != current.authorId) return false;
  if (current.replyTo != null) return false;
  final t0 = DateTime.tryParse(previous.timestamp);
  final t1 = DateTime.tryParse(current.timestamp);
  if (t0 == null || t1 == null) return false;
  return t1.difference(t0).abs() < _messageGroupWindow;
}

/// A thin "X is typing…" line above the composer, resolving typing user IDs to
/// names via the space's member cache.
class _TypingIndicator extends ConsumerWidget {
  const _TypingIndicator({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final typing = ref.watch(typingControllerProvider(channelId));
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(spaceId!));
    final userCache = ref.watch(accordUsersControllerProvider);

    String nameFor(String userId) {
      final member = members?[userId];
      if (member != null) return accordMemberName(member, fallback: 'Someone');
      final user = userCache[userId];
      if (user != null) return accordUserName(user, fallback: 'Someone');
      if (members != null) {
        ref.read(accordUsersControllerProvider.notifier).ensure(userId);
      }
      return 'Someone';
    }

    String? label;
    if (typing.length == 1) {
      label = '${nameFor(typing.first)} is typing…';
    } else if (typing.length == 2) {
      label = '${nameFor(typing[0])} and ${nameFor(typing[1])} are typing…';
    } else if (typing.length > 2) {
      label = 'Several people are typing…';
    }

    return SizedBox(
      height: 20,
      child: label == null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium!
                      .copyWith(color: colors.gray),
                ),
              ),
            ),
    );
  }
}

class _MessageRow extends ConsumerStatefulWidget {
  const _MessageRow({
    required this.message,
    required this.channelId,
    required this.spaceId,
    required this.isOwn,
    required this.mentionsMe,
    required this.canManageMessages,
    required this.onReply,
    this.grouped = false,
    this.author,
    this.authorUser,
    this.nameColor,
  });

  final AccordMessage message;
  final String channelId;

  /// Whether this message continues a group from the same author (see
  /// [_isGrouped]). Grouped rows hide the avatar/name/timestamp header and show
  /// the timestamp in the avatar gutter on hover instead.
  final bool grouped;

  /// Whether the current user can pin/unpin in this channel.
  final bool canManageMessages;

  /// Starts a reply to this message (sets the composer's reply target).
  final VoidCallback onReply;

  /// The space this message belongs to, for opening the author's profile
  /// popout. `null` in contexts without a space (e.g. DMs, not yet supported).
  final String? spaceId;

  /// Whether this message belongs to the current user (gates edit/delete).
  final bool isOwn;

  /// Whether the current user is mentioned by this message (drives highlight).
  final bool mentionsMe;

  /// The resolved member for [AccordMessage.authorId], if the space's member
  /// cache has loaded. `null` falls back to [authorUser], then the raw ID.
  final AccordMember? author;

  /// The author resolved from the on-demand user cache, used when the author
  /// isn't in the space's loaded member page. `null` falls back to the raw ID.
  final AccordUser? authorUser;

  /// The author's highest colored-role color, or null for the default color.
  final Color? nameColor;

  @override
  ConsumerState<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends ConsumerState<_MessageRow> {
  bool _hovered = false;
  bool _editing = false;
  bool _busy = false;
  TextEditingController? _editController;

  AccordMessage get _message => widget.message;

  @override
  void dispose() {
    _editController?.dispose();
    super.dispose();
  }

  String get _time {
    final dt = DateTime.tryParse(_message.timestamp);
    if (dt == null) return '';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Nickname → user display name → username → "Unknown". Falls back to the
  /// on-demand user cache when the author isn't in the loaded member page, and
  /// never shows the raw snowflake ID (the user controller fetches asynchronously
  /// — by the next rebuild a real name resolves; "Unknown" is the brief gap).
  String get _authorName {
    if (widget.author != null) {
      return accordMemberName(widget.author, fallback: 'Unknown');
    }
    if (widget.authorUser != null) {
      return accordUserName(widget.authorUser, fallback: 'Unknown');
    }
    return 'Unknown';
  }

  String get _initial {
    final name = _authorName.trim();
    if (name.isEmpty) return '?';
    return name.substring(0, 1).toUpperCase();
  }

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  void _startEdit() {
    setState(() {
      _editing = true;
      _editController = TextEditingController(text: _message.content);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editController?.dispose();
      _editController = null;
    });
  }

  Future<void> _saveEdit() async {
    final client = _client;
    final text = _editController?.text ?? '';
    if (client == null || text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .edit(client, _message.id, text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _cancelEdit();
  }

  void _openPopout() {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    showAccordMemberPopout(
      context,
      spaceId: spaceId,
      userId: _message.authorId,
    );
  }

  void _toggleReaction(String emojiName, {String? emojiId}) {
    final client = _client;
    if (client == null) return;
    ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .toggleReaction(client, _message.id, emojiName, emojiId: emojiId);
  }

  Future<void> _openReactionPicker() async {
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted) return;
    _toggleReaction(pick.name, emojiId: pick.id);
  }

  Future<void> _togglePin() async {
    final client = _client;
    if (client == null) return;
    final controller =
        ref.read(accordMessagesControllerProvider(widget.channelId).notifier);
    if (_message.pinned) {
      await controller.unpin(client, _message.id);
    } else {
      await controller.pin(client, _message.id);
    }
  }

  Future<void> _delete() async {
    final client = _client;
    if (client == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('This message will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .delete(client, _message.id);
    // Row disappears on success; if it failed we just re-enable.
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
          (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null),
    );
    final avatarUrl = widget.author != null
        ? accordMemberAvatarUrl(widget.author, cdnUrl)
        : accordAvatarUrl(widget.authorUser, cdnUrl);
    final tappable = widget.spaceId != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: widget.mentionsMe
            ? EdgeInsets.fromLTRB(13, widget.grouped ? 1 : 6, 6, 6)
            : EdgeInsets.only(top: widget.grouped ? 1 : 6, bottom: 6),
        decoration: widget.mentionsMe
            ? BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                border: Border(
                  left: BorderSide(color: colors.primary, width: 3),
                ),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.grouped)
              SizedBox(
                width: 36,
                child: Opacity(
                  opacity: _hovered ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _time,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall!
                          .copyWith(color: colors.gray),
                    ),
                  ),
                ),
              )
            else
              _MaybeTappable(
                enabled: tappable,
                onTap: _openPopout,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.darkGray,
                  foregroundImage: avatarUrl == null
                      ? null
                      : CachedNetworkImageProvider(avatarUrl),
                  child: Text(
                    _initial,
                    style: theme.textTheme.titleSmall!
                        .copyWith(color: Colors.white),
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_message.replyTo != null) _buildReplyPreview(colors),
                  if (!widget.grouped)
                    Row(
                      children: [
                        if (_message.pinned) ...[
                          Icon(Icons.push_pin, size: 12, color: colors.gray),
                          const SizedBox(width: 4),
                        ],
                        _MaybeTappable(
                          enabled: tappable,
                          onTap: _openPopout,
                          child: Text(_authorName,
                              style: theme.textTheme.titleSmall!
                                  .copyWith(color: widget.nameColor)),
                        ),
                        const SizedBox(width: 8),
                        Text(_time,
                            style: theme.textTheme.labelMedium!
                                .copyWith(color: colors.gray)),
                        if (_message.editedAt != null) ...[
                          const SizedBox(width: 6),
                          Text('(edited)',
                              style: theme.textTheme.labelSmall!
                                  .copyWith(color: colors.gray)),
                        ],
                      ],
                    ),
                  if (_editing)
                    _buildEditor(theme, colors)
                  else if (_message.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: AccordMessageContent(
                          content: _message.content,
                          spaceId: widget.spaceId),
                    ),
                  for (final attachment in _message.attachments)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _buildAttachment(attachment, cdnUrl, theme),
                    ),
                  for (final embed in _message.embeds)
                    AccordEmbedBox(embed: embed, cdnUrl: cdnUrl),
                  if ((_message.reactions ?? const []).isNotEmpty)
                    _buildReactions(theme, colors, cdnUrl),
                  if (_message.replyCount > 0) _buildThreadChip(theme, colors),
                ],
              ),
            ),
            if (!_editing)
              Opacity(
                opacity: _hovered ? 1 : 0,
                child: Row(
                  children: [
                    _ReactButton(onPressed: _openReactionPicker),
                    IconButton(
                      tooltip: 'Reply',
                      onPressed: widget.onReply,
                      icon: Icon(Icons.reply, size: 18, color: colors.gray),
                    ),
                    IconButton(
                      tooltip: 'Thread',
                      onPressed: _openThread,
                      icon: Icon(Icons.forum_outlined,
                          size: 18, color: colors.gray),
                    ),
                    if (widget.isOwn ||
                        widget.canManageMessages ||
                        (!widget.isOwn && widget.spaceId != null))
                      _MessageActions(
                        canEdit: widget.isOwn,
                        canDelete: widget.isOwn || widget.canManageMessages,
                        canPin: widget.canManageMessages,
                        canReport: !widget.isOwn && widget.spaceId != null,
                        pinned: _message.pinned,
                        onEdit: _startEdit,
                        onDelete: _delete,
                        onTogglePin: _togglePin,
                        onReport: _report,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openThread() => showAccordThread(
        context,
        channelId: widget.channelId,
        spaceId: widget.spaceId,
        root: _message,
      );

  void _report() {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    showReportDialog(
      context,
      spaceId: spaceId,
      targetType: 'message',
      targetId: _message.id,
      channelId: widget.channelId,
    );
  }

  Widget _buildThreadChip(ThemeData theme, BonfireThemeExtension colors) {
    final count = _message.replyCount;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _openThread,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              Text('$count ${count == 1 ? 'reply' : 'replies'}',
                  style: theme.textTheme.labelMedium!
                      .copyWith(color: colors.primary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(
      ThemeData theme, BonfireThemeExtension colors, String? cdnUrl) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final reaction in _message.reactions!)
            _ReactionPill(
              reaction: reaction,
              cdnUrl: cdnUrl,
              onTap: () => _toggleReaction(
                reaction.emoji['name']?.toString() ?? '',
                emojiId: reaction.emoji['id']?.toString(),
              ),
            ),
        ],
      ),
    );
  }

  /// A compact "↩ Name preview" line above a reply message, resolving the
  /// referenced message from the loaded channel cache when available.
  Widget _buildReplyPreview(BonfireThemeExtension colors) {
    final theme = Theme.of(context);
    final messages =
        ref.read(accordMessagesControllerProvider(widget.channelId));
    final referenced =
        messages?.firstWhereOrNull((m) => m.id == _message.replyTo);
    String name = 'Unknown';
    String preview = '';
    if (referenced != null) {
      final members = widget.spaceId == null
          ? null
          : ref.read(accordMembersControllerProvider(widget.spaceId!));
      name = accordMemberName(members?[referenced.authorId],
          fallback: referenced.authorId);
      preview =
          referenced.content.isEmpty ? '(attachment)' : referenced.content;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 2),
      child: Row(
        children: [
          Icon(Icons.reply, size: 12, color: colors.gray),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              preview.isEmpty ? name : '$name  $preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium!.copyWith(color: colors.gray),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders one attachment inline: tappable image (→ lightbox), video player,
  /// audio player, or a filename chip for other types.
  Widget _buildAttachment(
      AccordAttachment attachment, String? cdnUrl, ThemeData theme) {
    final url = _attachmentUrl(attachment, cdnUrl);
    if (_isImageAttachment(attachment)) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => showImageLightbox(context, url),
          child: _ImageAttachment(
            url: url,
            width: _asDouble(attachment.width),
            height: _asDouble(attachment.height),
          ),
        ),
      );
    }
    if (_isVideoAttachment(attachment)) {
      return InlineVideoPlayer(
        url: url,
        filename: attachment.filename,
        width: _asDouble(attachment.width),
        height: _asDouble(attachment.height),
      );
    }
    if (_isAudioAttachment(attachment)) {
      return InlineAudioPlayer(url: url, filename: attachment.filename);
    }
    return Text('📎 ${attachment.filename}',
        style: theme.textTheme.bodyMedium);
  }

  Widget _buildEditor(ThemeData theme, BonfireThemeExtension colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _editController,
            autofocus: true,
            enabled: !_busy,
            minLines: 1,
            maxLines: 6,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.darkGray,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _saveEdit(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: _busy ? null : _cancelEdit,
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: _busy ? null : _saveEdit,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wraps [child] in a click-to-open gesture (with a pointer cursor) when
/// [enabled]; otherwise renders the child untouched. Used so message authors are
/// only tappable inside a space (where a profile popout makes sense).
class _MaybeTappable extends StatelessWidget {
  const _MaybeTappable({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.canEdit,
    required this.canDelete,
    required this.canPin,
    required this.canReport,
    required this.pinned,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
    required this.onReport,
  });

  final bool canEdit;
  final bool canDelete;
  final bool canPin;
  final bool canReport;
  final bool pinned;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Message actions',
      icon: Icon(Icons.more_horiz, size: 18, color: colors.gray),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
          case 'pin':
            onTogglePin();
          case 'report':
            onReport();
        }
      },
      itemBuilder: (context) => [
        if (canPin)
          PopupMenuItem(
              value: 'pin', child: Text(pinned ? 'Unpin' : 'Pin')),
        if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (canDelete)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        if (canReport)
          const PopupMenuItem(value: 'report', child: Text('Report')),
      ],
    );
  }
}

/// Opens the full emoji picker to add a reaction to the message.
/// A bell toggle in the channel header that mutes/unmutes notifications for the
/// channel. Loads the user's muted-channel list once per channel and flips it
/// optimistically on tap.
class _MuteButton extends ConsumerStatefulWidget {
  const _MuteButton({required this.channelId});

  final String channelId;

  @override
  ConsumerState<_MuteButton> createState() => _MuteButtonState();
}

class _MuteButtonState extends ConsumerState<_MuteButton> {
  bool? _muted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_MuteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) {
      _muted = null;
      _load();
    }
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.users.listMutes();
    if (!mounted) return;
    final data = result.data;
    final ids = data is List
        ? data.map((e) => e.toString()).toSet()
        : const <String>{};
    setState(() => _muted = ids.contains(widget.channelId));
  }

  Future<void> _toggle() async {
    final client = _client;
    if (client == null || _busy || _muted == null) return;
    final next = !_muted!;
    setState(() {
      _busy = true;
      _muted = next;
    });
    final result = next
        ? await client.channels.mute(widget.channelId)
        : await client.channels.unmute(widget.channelId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) _muted = !next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final muted = _muted ?? false;
    return IconButton(
      tooltip: muted ? 'Unmute channel' : 'Mute channel',
      onPressed: _muted == null ? null : _toggle,
      icon: Icon(muted ? Icons.notifications_off : Icons.notifications_none,
          size: 18, color: colors.dirtyWhite),
    );
  }
}

class _ReactButton extends StatelessWidget {
  const _ReactButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return IconButton(
      tooltip: 'Add reaction',
      onPressed: onPressed,
      icon: Icon(Icons.add_reaction_outlined, size: 18, color: colors.gray),
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.reaction,
    required this.onTap,
    this.cdnUrl,
  });

  final AccordReaction reaction;
  final VoidCallback onTap;
  final String? cdnUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final name = reaction.emoji['name']?.toString() ?? '';
    final id = reaction.emoji['id']?.toString();
    final mine = reaction.includesMe;
    return Material(
      color: mine ? colors.primary.withValues(alpha: 0.25) : colors.darkGray,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mine ? colors.primary : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (id != null)
                CachedNetworkImage(
                  imageUrl: AccordCDN.emoji(id, cdnUrl: cdnUrl ?? ''),
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) =>
                      Text(name, style: const TextStyle(fontSize: 14)),
                )
              else
                Text(name, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text('${reaction.count}',
                  style: theme.textTheme.labelMedium!
                      .copyWith(color: colors.dirtyWhite)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.channelId,
    this.channelName,
    this.spaceId,
    this.replyingTo,
    this.replyName,
    this.onCancelReply,
  });

  final String channelId;
  final String? channelName;
  final String? spaceId;
  final AccordMessage? replyingTo;
  final String? replyName;
  final VoidCallback? onCancelReply;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _sending = false;

  /// Files the user has attached but not yet sent.
  final List<PlatformFile> _attachments = [];

  /// The server's typing indicator lasts ~10s, so we re-trigger at most once
  /// every 8s while the user keeps typing rather than on every keystroke.
  DateTime? _lastTypingSent;
  static const _typingInterval = Duration(seconds: 8);

  /// Mention-popup state. `_mentionQuery == null` means the popup is hidden;
  /// otherwise it's the lowercase text after the active `@`, and
  /// `[_mentionStart, _mentionEnd)` is the range in `_controller.text` that
  /// the picked handle replaces (covers the `@` and the query).
  String? _mentionQuery;
  int _mentionStart = -1;
  int _mentionEnd = -1;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _updateMentionState(value);
    if (value.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < _typingInterval) {
      return;
    }
    _lastTypingSent = now;
    final client = ref.read(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.client : null),
    );
    client?.messages.typing(widget.channelId);
  }

  /// Decides whether an `@` autocomplete is in progress and updates the
  /// popup state accordingly. Mirrors the reference composer's
  /// `_find_mention_trigger`: scan backwards from the cursor to the nearest
  /// `@` that's at line start or follows a non-word char; everything between
  /// it and the cursor is the query. A space (or no `@` before whitespace)
  /// dismisses the popup. The popup itself is only built when `_mentionQuery`
  /// is non-null AND there are candidates to show.
  void _updateMentionState(String text) {
    final selection = _controller.value.selection;
    if (!selection.isValid || !selection.isCollapsed || widget.spaceId == null) {
      _clearMentionState();
      return;
    }
    final caret = selection.baseOffset;
    var i = caret - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == '@') {
        if (i > 0 && _isMentionWordChar(text[i - 1])) {
          _clearMentionState();
          return;
        }
        final query = text.substring(i + 1, caret).toLowerCase();
        setState(() {
          _mentionQuery = query;
          _mentionStart = i;
          _mentionEnd = caret;
        });
        return;
      }
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        _clearMentionState();
        return;
      }
      i--;
    }
    _clearMentionState();
  }

  void _clearMentionState() {
    if (_mentionQuery == null) return;
    setState(() {
      _mentionQuery = null;
      _mentionStart = -1;
      _mentionEnd = -1;
    });
  }

  static bool _isMentionWordChar(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) return true; // 0-9
    if (code >= 0x41 && code <= 0x5A) return true; // A-Z
    if (code >= 0x61 && code <= 0x7A) return true; // a-z
    if (code == 0x5F) return true; // _
    return code > 0x7F; // non-ASCII letter-likes
  }

  /// Replaces the active `@query` range with `@handle ` and dismisses the
  /// popup. Mirrors the reference's `_on_mention_picked`.
  void _pickMention(String handle) {
    if (_mentionStart < 0 || _mentionEnd < 0) return;
    final text = _controller.text;
    if (_mentionEnd > text.length) return;
    final insert = '@$handle ';
    final next = text.replaceRange(_mentionStart, _mentionEnd, insert);
    _controller.value = TextEditingValue(
      text: next,
      selection:
          TextSelection.collapsed(offset: _mentionStart + insert.length),
    );
    _clearMentionState();
    _focusNode.requestFocus();
  }

  Future<void> _pickFiles() async {
    final result =
        await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result == null || !mounted) return;
    setState(() {
      for (final file in result.files) {
        if (file.bytes != null) _attachments.add(file);
      }
    });
  }

  void _removeAttachment(PlatformFile file) {
    setState(() => _attachments.remove(file));
  }

  Future<void> _pickEmoji() async {
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted) return;
    _insertAtCursor(pick.composerText);
  }

  /// Inserts [text] at the current cursor position (replacing any selection),
  /// keeping focus and placing the caret after the inserted text.
  void _insertAtCursor(String text) {
    final value = _controller.value;
    final selection = value.selection;
    final base = selection.isValid ? selection : null;
    final start = base?.start ?? value.text.length;
    final end = base?.end ?? value.text.length;
    final next = value.text.replaceRange(start, end, text);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if ((text.trim().isEmpty && _attachments.isEmpty) || _sending) return;

    final client = ref.read(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.client : null),
    );
    if (client == null) return;

    setState(() => _sending = true);
    final controller =
        ref.read(accordMessagesControllerProvider(widget.channelId).notifier);
    final replyTo = widget.replyingTo?.id;
    final bool ok;
    if (_attachments.isEmpty) {
      ok = await controller.send(client, text, replyTo: replyTo);
    } else {
      final files = [
        for (final file in _attachments)
          {
            'filename': file.name,
            'content': file.bytes!,
            'content_type': _mimeType(file.extension),
          },
      ];
      ok = await controller.sendWithAttachments(client, text, files,
          replyTo: replyTo);
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _attachments.clear();
    });
    if (ok) {
      soundManager.play('message_sent');
      _controller.clear();
      _lastTypingSent = null;
      widget.onCancelReply?.call();
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final hint = widget.channelName != null
        ? 'Message #${widget.channelName}'
        : 'Message';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colors.darkGray,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyingTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
                child: Row(
                  children: [
                    Icon(Icons.reply, size: 14, color: colors.gray),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Replying to ${widget.replyName ?? 'message'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium!
                            .copyWith(color: colors.gray),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel reply',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onCancelReply,
                      icon: Icon(Icons.close, size: 14, color: colors.gray),
                    ),
                  ],
                ),
              ),
            if (_attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final file in _attachments)
                      _AttachmentChip(
                        file: file,
                        onRemove:
                            _sending ? null : () => _removeAttachment(file),
                      ),
                  ],
                ),
              ),
            if (_mentionQuery != null && widget.spaceId != null)
              _MentionPopup(
                spaceId: widget.spaceId!,
                query: _mentionQuery!,
                onPick: _pickMention,
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Attach files',
                  onPressed: _sending ? null : _pickFiles,
                  icon: Icon(Icons.add_circle_outline,
                      size: 20, color: colors.dirtyWhite),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.send,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _send(),
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: hint,
                      hintStyle: Theme.of(context)
                          .textTheme
                          .bodyLarge!
                          .copyWith(color: colors.gray),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Emoji',
                  onPressed: _sending ? null : _pickEmoji,
                  icon: Icon(Icons.emoji_emotions_outlined,
                      size: 20, color: colors.dirtyWhite),
                ),
                IconButton(
                  tooltip: 'Send',
                  onPressed: _sending ? null : _send,
                  icon: Icon(Icons.send, size: 20, color: colors.dirtyWhite),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Resolves a space's `icon` reference to an absolute CDN URL, or null when the
/// space has no icon. The field is either a bare asset hash or a
/// server-relative/absolute path; both are handled.
String? _spaceIconUrl(AccordSpace space, String? cdnUrl) {
  final icon = space.icon;
  if (icon is! String || icon.isEmpty) return null;
  final cdn = cdnUrl ?? '';
  if (icon.contains('/') || icon.startsWith('http')) {
    return AccordCDN.resolvePath(icon, cdnUrl: cdn);
  }
  return AccordCDN.spaceIcon(space.id, icon,
      format: AccordCDN.autoFormat(icon), cdnUrl: cdn);
}

/// Resolves an attachment's server-returned URL/path to an absolute CDN URL.
String _attachmentUrl(AccordAttachment attachment, String? cdnUrl) =>
    AccordCDN.resolvePath(attachment.url, cdnUrl: cdnUrl ?? '');

/// Whether an attachment should render as an inline image (by content type,
/// falling back to the filename extension).
bool _isImageAttachment(AccordAttachment attachment) {
  final type = attachment.contentType;
  if (type != null && type.startsWith('image/')) return true;
  final name = attachment.filename.toLowerCase();
  return name.endsWith('.png') ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.gif') ||
      name.endsWith('.webp');
}

/// Whether an attachment should render with the inline video player.
bool _isVideoAttachment(AccordAttachment attachment) {
  final type = attachment.contentType;
  if (type != null && type.startsWith('video/')) return true;
  final name = attachment.filename.toLowerCase();
  return name.endsWith('.mp4') ||
      name.endsWith('.webm') ||
      name.endsWith('.mov') ||
      name.endsWith('.mkv');
}

/// Whether an attachment should render with the inline audio player.
bool _isAudioAttachment(AccordAttachment attachment) {
  final type = attachment.contentType;
  if (type != null && type.startsWith('audio/')) return true;
  final name = attachment.filename.toLowerCase();
  return name.endsWith('.mp3') ||
      name.endsWith('.ogg') ||
      name.endsWith('.wav') ||
      name.endsWith('.m4a') ||
      name.endsWith('.flac');
}

/// Best-effort conversion of an attachment's loosely-typed width/height to a
/// double for sizing hints.
double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Maps a file extension to a MIME type for attachment uploads, falling back to
/// a generic binary type when unknown.
String _mimeType(String? extension) {
  switch (extension?.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'svg':
      return 'image/svg+xml';
    case 'mp4':
      return 'video/mp4';
    case 'webm':
      return 'video/webm';
    case 'mp3':
      return 'audio/mpeg';
    case 'ogg':
      return 'audio/ogg';
    case 'wav':
      return 'audio/wav';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    case 'json':
      return 'application/json';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

/// A removable chip representing one pending attachment in the composer.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.file, this.onRemove});

  final PlatformFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined,
              size: 16, color: colors.dirtyWhite),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              file.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: colors.dirtyWhite),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: Icon(Icons.close, size: 16, color: colors.gray),
          ),
        ],
      ),
    );
  }
}

/// An inline image attachment, constrained to a readable size and preserving
/// the server-provided aspect ratio when available.
class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.url, this.width, this.height});

  final String url;
  final double? width;
  final double? height;

  static const _maxWidth = 400.0;
  static const _maxHeight = 350.0;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    double? renderWidth = width;
    double? renderHeight = height;
    if (renderWidth != null && renderWidth > _maxWidth) {
      final scale = _maxWidth / renderWidth;
      renderWidth = _maxWidth;
      if (renderHeight != null) renderHeight *= scale;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _maxWidth,
          maxHeight: _maxHeight,
        ),
        child: CachedNetworkImage(
          imageUrl: url,
          width: renderWidth,
          height: renderHeight,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(
            width: renderWidth ?? 200,
            height: renderHeight ?? 150,
            color: colors.darkGray,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, _, _) => Container(
            padding: const EdgeInsets.all(8),
            color: colors.darkGray,
            child: Icon(Icons.broken_image_outlined, color: colors.gray),
          ),
        ),
      ),
    );
  }
}

/// A "loading older" / "beginning of channel" header rendered above the
/// message list. Watches the messages controller so the spinner and end-of-
/// history hint reflect [AccordMessagesController.isLoadingOlder]/
/// [hasMoreOlder] as they change.
class _OlderHistoryHeader extends ConsumerWidget {
  const _OlderHistoryHeader({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild whenever the message list mutates (which also covers the
    // controller bumping state at the start/end of loadOlder).
    ref.watch(accordMessagesControllerProvider(channelId));
    final notifier =
        ref.read(accordMessagesControllerProvider(channelId).notifier);
    if (notifier.isLoadingOlder) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!notifier.hasMoreOlder) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            "Beginning of channel",
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}

/// Compact "@" autocomplete popup rendered above the composer. Lists
/// members of [spaceId] (and mentionable roles) whose name starts with —
/// or contains — [query]; tapping inserts the handle into the composer via
/// [onPick]. Hidden automatically by the composer when [query] becomes
/// empty of matches.
class _MentionPopup extends ConsumerWidget {
  const _MentionPopup({
    required this.spaceId,
    required this.query,
    required this.onPick,
  });

  final String spaceId;
  final String query;
  final ValueChanged<String> onPick;

  static const int _maxResults = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final members = ref.watch(accordMembersControllerProvider(spaceId));
    final space = ref.watch(spacesControllerProvider
        .select((s) => s?.firstWhereOrNull((sp) => sp.id == spaceId)));
    final roles = space?.roles ?? const <AccordRole>[];
    final entries = _filter(members, roles, query);
    if (entries.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.foreground, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            InkWell(
              onTap: () => onPick(entry.handle),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Icon(entry.isRole ? Icons.label_outline : Icons.person,
                        size: 14, color: colors.gray),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      "@${entry.handle}",
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall!
                          .copyWith(color: colors.gray),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Picks up to [_maxResults] candidates from members and mentionable roles
  /// whose handle/label matches [query] (case-insensitive). Prefix matches rank
  /// before substring matches; members rank before roles within each tier.
  List<_MentionEntry> _filter(
    Map<String, AccordMember>? members,
    List<AccordRole> roles,
    String query,
  ) {
    final q = query.toLowerCase();
    final prefix = <_MentionEntry>[];
    final contains = <_MentionEntry>[];
    void consider(_MentionEntry e) {
      final h = e.handle.toLowerCase();
      final l = e.label.toLowerCase();
      if (q.isEmpty || h.startsWith(q) || l.startsWith(q)) {
        prefix.add(e);
      } else if (h.contains(q) || l.contains(q)) {
        contains.add(e);
      }
    }

    if (members != null) {
      for (final m in members.values) {
        final user = m.user;
        final username = user?.username;
        if (username == null || username.isEmpty) continue;
        consider(_MentionEntry(
          handle: username,
          label: accordMemberName(m, fallback: username),
          isRole: false,
        ));
      }
    }
    for (final r in roles) {
      if (!r.mentionable) continue;
      consider(_MentionEntry(
        handle: r.name,
        label: r.name,
        isRole: true,
      ));
    }
    final out = [...prefix, ...contains];
    if (out.length > _maxResults) return out.sublist(0, _maxResults);
    return out;
  }
}

class _MentionEntry {
  const _MentionEntry({
    required this.handle,
    required this.label,
    required this.isRole,
  });
  final String handle;
  final String label;
  final bool isRole;
}
