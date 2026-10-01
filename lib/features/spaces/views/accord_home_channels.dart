part of 'accord_home.dart';

class _ChannelList extends ConsumerStatefulWidget {
  const _ChannelList({
    required this.spaceId,
    required this.spaceName,
    required this.channels,
    required this.selectedChannelId,
    required this.onSelect,
    required this.onSearchSelect,
  });

  final String? spaceId;
  final String? spaceName;
  final List<AccordChannel>? channels;
  final String? selectedChannelId;
  final ValueChanged<String> onSelect;
  final ValueChanged<AccordSearchSelection> onSearchSelect;

  @override
  ConsumerState<_ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends ConsumerState<_ChannelList> {
  /// What to render in place of the channel list while there is none.
  ///
  /// A null channel list can mean loading, a failed request, or a successfully
  /// loaded account with no spaces. Only the loading case should spin.
  Widget _emptyState(BuildContext context, {required String? spaceId}) {
    final serverKey = ref.watchActiveServerKey() ?? '';

    if (spaceId != null &&
        ref.watch(channelsLoadFailedProvider(serverKey, spaceId))) {
      return ServerUnreachable(
        title: "Couldn't load channels",
        message: 'Something went wrong fetching this space’s channels.',
        onRetry: () {
          ref
              .read(channelsLoadFailedProvider(serverKey, spaceId).notifier)
              .set(false);
          ref.invalidate(accordChannelsControllerProvider(serverKey, spaceId));
        },
      );
    }

    if (ref.watch(spacesLoadFailedProvider(serverKey))) {
      return ServerUnreachable(
        title: "Couldn't load your spaces",
        message: 'Something went wrong fetching this server’s space list.',
        onRetry: () {
          final client = ref.accordClient;
          if (client == null) return;
          unawaited(ref.read(retryLoadSpacesProvider)(client, serverKey));
        },
      );
    }

    final connection = ref.watch(
      connectionsControllerProvider.select((connections) => connections.active),
    );
    final status = connection?.status ?? ConnectionStatus.disconnected;
    if (status.isUnreachable) {
      return ServerUnreachable(
        onRetry: () => ref.accordClient?.ensureConnected(),
      );
    }
    // Auth seeds an empty cache before READY. Wait for the authoritative space
    // fetch before treating that cache as an account with no memberships.
    if (spaceId == null &&
        status == ConnectionStatus.ready &&
        connection?.spacesReady == true &&
        ref.watch(spacesControllerProvider)?.isEmpty == true) {
      final isAdmin = ref.watchIsAdmin();
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.grid_view_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                'No spaces yet',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'You haven’t joined any spaces on this server.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => showAddServerDialog(context),
                child: const Text('Join with invite'),
              ),
              TextButton(
                onPressed: () => showAccordDiscovery(context),
                child: const Text('Explore public spaces'),
              ),
              if (isAdmin) ...[
                const SizedBox(height: 8),
                const Text(
                  'You can manage this server without joining a space.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => context.push('/admin'),
                  child: const Text('Server administration'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return const LoadingView();
  }

  void _toggleCollapsed(String categoryId) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    final serverKey = ref.readActiveServerKey();
    if (serverKey == null) return;
    final settings = ref.read(settingsControllerProvider);
    ref
        .read(settingsControllerProvider.notifier)
        .setCategoryCollapsed(
          serverKey,
          spaceId,
          categoryId,
          !settings.isCategoryCollapsed(serverKey, spaceId, categoryId),
        );
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final spaceId = widget.spaceId;
    final spaceName = widget.spaceName;
    final channels = widget.channels;
    final selectedChannelId = widget.selectedChannelId;
    final onSelect = widget.onSelect;
    final colors = BonfireThemeExtension.of(context);
    final id = spaceId;
    final space = id == null
        ? null
        : ref.watch(
            spacesControllerProvider.select(
              (s) => s?.firstWhereOrNull((sp) => sp.id == id),
            ),
          );
    final cdnUrl = ref.watchCdnUrl();
    final bannerUrl = space == null
        ? null
        : accordSpaceBannerUrl(space, cdnUrl);

    // Collapsed categories are persisted per-space via SettingsController
    // (mirrors the reference client's Config.set_category_collapsed).
    final collapsed = id == null
        ? const <String>{}
        : ref.watch(
            settingsControllerProvider.select(
              (s) => s.collapsedCategories[id]?.toSet() ?? const <String>{},
            ),
          );

    // Show the settings gear only to members who can manage the space or roles,
    // and the channel-management affordances to those with manage_channels.
    var canManage = false;
    var canManageChannels = false;
    var canInvite = false;
    if (id != null) {
      final perms = ref.watchAccordPermissions(space, id);
      canManage = canManageSpaceSettings(perms);
      canManageChannels = accordHasPermission(
        perms,
        AccordPermission.manageChannels,
      );
      canInvite = accordHasPermission(perms, AccordPermission.createInvites);
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.foreground,
        border: Border(left: BorderSide(color: colors.background, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (spaceId != null && ref.watchActiveServerKey() != null)
            SpaceArcadeEntry(
              serverKey: ref.watchActiveServerKey()!,
              spaceId: spaceId,
            ),
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
                if (space?.origin != null) ...[
                  const SizedBox(width: 6),
                  RemoteOriginBadge(domain: space!.origin),
                ],
                if (id != null)
                  _HeaderAction(
                    tooltip: 'Search',
                    icon: Icons.search,
                    color: colors.dirtyWhite,
                    onPressed: () async {
                      final selection = await showAccordSearch(
                        context,
                        spaceId: id,
                      );
                      if (selection != null && mounted) {
                        widget.onSearchSelect(selection);
                      }
                    },
                  ),
                if (id != null && (canInvite || canManageChannels || canManage))
                  PopupMenuButton<_HeaderAction>(
                    tooltip: 'Space actions',
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: colors.dirtyWhite,
                    ),
                    onSelected: (action) => action.onPressed(),
                    itemBuilder: (context) =>
                        <_HeaderAction>[
                              if (canInvite)
                                _HeaderAction(
                                  tooltip: 'Invite people',
                                  icon: Icons.person_add,
                                  color: colors.dirtyWhite,
                                  onPressed: () =>
                                      showAccordInvites(context, spaceId: id),
                                ),
                              if (canManageChannels)
                                _HeaderAction(
                                  tooltip: 'Create channel',
                                  icon: Icons.add,
                                  color: colors.dirtyWhite,
                                  onPressed: () => showCreateChannelDialog(
                                    context,
                                    spaceId: id,
                                  ),
                                ),
                              if (canManageChannels && channels != null)
                                _HeaderAction(
                                  tooltip: 'Reorder channels',
                                  icon: Icons.reorder,
                                  color: colors.dirtyWhite,
                                  onPressed: () => showAccordChannelReorder(
                                    context,
                                    spaceId: id,
                                    channels: channels,
                                  ),
                                ),
                              if (canManage)
                                _HeaderAction(
                                  tooltip: 'Space settings',
                                  icon: Icons.settings,
                                  color: colors.dirtyWhite,
                                  onPressed: () => showAccordSpaceSettings(
                                    context,
                                    spaceId: id,
                                  ),
                                ),
                            ]
                            .map(
                              (action) => PopupMenuItem<_HeaderAction>(
                                value: action,
                                child: Row(
                                  children: [
                                    Icon(action.icon, size: 18),
                                    const SizedBox(width: 12),
                                    Text(action.tooltip),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                  ),
              ],
            ),
          ),
          Expanded(
            child: channels == null
                ? _emptyState(context, spaceId: id)
                : (canManageChannels && id != null)
                ? _ChannelDragList(
                    spaceId: id,
                    channels: channels,
                    selectedChannelId: selectedChannelId,
                    onSelect: onSelect,
                    collapsed: collapsed,
                    onToggleCollapsed: _toggleCollapsed,
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: _buildChannelEntries(
                      context,
                      spaceId: id,
                      channels: channels,
                      selectedChannelId: selectedChannelId,
                      onSelect: onSelect,
                      canManageChannels: canManageChannels,
                      collapsed: collapsed,
                      onToggleCollapsed: _toggleCollapsed,
                    ),
                  ),
          ),
          VoiceBar(
            onTapStatus: () {
              final channelId = ref.read(voiceControllerProvider).channelId;
              if (channelId != null) onSelect(channelId);
            },
          ),
        ],
      ),
    );
  }
}

/// A thin draggable divider between the channel list and the message pane that
/// resizes the channel column. Shows a horizontal-resize cursor on hover and
/// highlights while being dragged.
class _ChannelListResizeHandle extends StatefulWidget {
  const _ChannelListResizeHandle({
    required this.onDragDelta,
    required this.onDragEnd,
  });

  final ValueChanged<double> onDragDelta;
  final VoidCallback onDragEnd;

  @override
  State<_ChannelListResizeHandle> createState() =>
      _ChannelListResizeHandleState();
}

class _ChannelListResizeHandleState extends State<_ChannelListResizeHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _active = true),
        onHorizontalDragUpdate: (d) => widget.onDragDelta(d.delta.dx),
        onHorizontalDragEnd: (_) {
          widget.onDragEnd();
          setState(() => _active = false);
        },
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: _active ? 2 : 1,
              color: _active ? colors.primary : colors.background,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon button for the channel-list header. The header is only ~200px
/// wide, so the default 48px `IconButton` hit target overflows once several
/// management actions are visible; this trims the footprint to 32px.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

/// Groups [channels] into uncategorized channels (rendered first) followed by
/// each category with its child channels. When [canManageChannels] is true,
/// categories show an inline "add channel" button and channels an edit button.
/// [collapsed] lists category IDs whose children should be hidden; tapping a
/// category header calls [onToggleCollapsed] to flip its state.
List<Widget> _buildChannelEntries(
  BuildContext context, {
  required String? spaceId,
  required List<AccordChannel> channels,
  required String? selectedChannelId,
  required ValueChanged<String> onSelect,
  required bool canManageChannels,
  required Set<String> collapsed,
  required ValueChanged<String> onToggleCollapsed,
}) {
  final categories = channels.where((c) => c.type == 'category').toList();
  final leaves = channels.where((c) => c.type != 'category').toList();
  final byParent = <String?, List<AccordChannel>>{};
  for (final c in leaves) {
    byParent.putIfAbsent(c.parentId, () => []).add(c);
  }

  Widget tile(AccordChannel channel) => _channelTile(
    context,
    channel,
    spaceId: spaceId,
    selected: channel.id == selectedChannelId,
    canManageChannels: canManageChannels,
    onTap: () => onSelect(channel.id),
  );

  final entries = <Widget>[];
  for (final channel in byParent[null] ?? const <AccordChannel>[]) {
    entries.add(tile(channel));
  }
  for (final category in categories) {
    final isCollapsed = collapsed.contains(category.id);
    entries.add(
      _categoryHeader(
        context,
        category,
        spaceId: spaceId,
        canManageChannels: canManageChannels,
        collapsed: isCollapsed,
        onToggle: () => onToggleCollapsed(category.id),
      ),
    );
    if (!isCollapsed) {
      for (final channel in byParent[category.id] ?? const <AccordChannel>[]) {
        entries.add(tile(channel));
      }
    }
  }
  return entries;
}
