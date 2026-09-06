part of 'accord_home.dart';

class _ChannelList extends ConsumerStatefulWidget {
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
  ConsumerState<_ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends ConsumerState<_ChannelList> {
  /// What to render in place of the channel list while there is none.
  ///
  /// A null channel list means one of three different things and they must not
  /// all read as a spinner: the space list failed, this space's channel list
  /// failed, the gateway is down, or we're genuinely still loading. The first
  /// three get an explanation and a Retry (see `LoadFailed`); only the last one
  /// spins.
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
          ref.invalidate(
            accordChannelsControllerProvider(serverKey, spaceId),
          );
        },
      );
    }

    if (ref.watch(spacesLoadFailedProvider(serverKey))) {
      return ServerUnreachable(
        title: "Couldn't load your spaces",
        message: 'Something went wrong fetching this server’s space list.',
        onRetry: () {
          final auth = ref.read(accordAuthProvider);
          if (auth is! AccordAuthLoggedIn) return;
          unawaited(
            ref.read(retryLoadSpacesProvider)(auth.client, serverKey),
          );
        },
      );
    }

    final status = ref.watch(
      connectionsControllerProvider.select(
        (connections) =>
            connections.active?.status ?? ConnectionStatus.disconnected,
      ),
    );
    if (status.isUnreachable) {
      return ServerUnreachable(
        onRetry: () {
          final auth = ref.read(accordAuthProvider);
          if (auth is AccordAuthLoggedIn) auth.client.ensureConnected();
        },
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
                Flexible(
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
                const Spacer(),
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
                      if (selection != null) onSelect(selection.channelId);
                    },
                  ),
                if (canInvite && id != null)
                  _HeaderAction(
                    tooltip: 'Invite people',
                    icon: Icons.person_add,
                    color: colors.dirtyWhite,
                    onPressed: () => showAccordInvites(context, spaceId: id),
                  ),
                if (canManageChannels && id != null)
                  _HeaderAction(
                    tooltip: 'Create channel',
                    icon: Icons.add,
                    color: colors.dirtyWhite,
                    onPressed: () =>
                        showCreateChannelDialog(context, spaceId: id),
                  ),
                if (canManageChannels && id != null && channels != null)
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
                if (canManage && id != null)
                  _HeaderAction(
                    tooltip: 'Space settings',
                    icon: Icons.settings,
                    color: colors.dirtyWhite,
                    onPressed: () =>
                        showAccordSpaceSettings(context, spaceId: id),
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

/// A category row for the static list and the drag list alike: the inline
/// "add channel"/edit affordances are wired only for managers of a real space.
_CategoryHeader _categoryHeader(
  BuildContext context,
  AccordChannel category, {
  required String? spaceId,
  required bool canManageChannels,
  required bool collapsed,
  required VoidCallback onToggle,
}) => _CategoryHeader(
  category: category,
  spaceId: spaceId,
  canManageChannels: canManageChannels,
  collapsed: collapsed,
  onToggle: onToggle,
  onAdd: canManageChannels && spaceId != null
      ? () => showCreateChannelDialog(
          context,
          spaceId: spaceId,
          parentId: category.id,
        )
      : null,
  onEdit: canManageChannels && spaceId != null
      ? () =>
            showEditChannelDialog(context, spaceId: spaceId, channel: category)
      : null,
);

/// A channel row for the static list and the drag list alike; see
/// [_categoryHeader] for the edit affordance rule.
_ChannelTile _channelTile(
  BuildContext context,
  AccordChannel channel, {
  required String? spaceId,
  required bool selected,
  required bool canManageChannels,
  required VoidCallback onTap,
}) => _ChannelTile(
  channel: channel,
  spaceId: spaceId,
  selected: selected,
  canManageChannels: canManageChannels,
  onTap: onTap,
  onEdit: canManageChannels && spaceId != null
      ? () => showEditChannelDialog(context, spaceId: spaceId, channel: channel)
      : null,
);

class _CategoryHeader extends ConsumerWidget {
  const _CategoryHeader({
    required this.category,
    required this.spaceId,
    required this.canManageChannels,
    required this.collapsed,
    required this.onToggle,
    this.onAdd,
    this.onEdit,
  });

  final AccordChannel category;
  final String? spaceId;
  final bool canManageChannels;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  void _showMenu(BuildContext context, WidgetRef ref, [Offset? position]) {
    final id = spaceId;
    if (id == null) return;
    showCategoryContextMenu(
      context,
      ref,
      category: category,
      spaceId: id,
      canManageChannels: canManageChannels,
      collapsed: collapsed,
      onToggle: onToggle,
      globalPosition: position,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    return InkWell(
      onTap: onToggle,
      onLongPress: () => _showMenu(context, ref, null),
      onSecondaryTapUp: (d) => _showMenu(context, ref, d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 2),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 14,
              color: colors.gray,
            ),
            const SizedBox(width: 2),
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
      ),
    );
  }
}

class _ChannelTile extends ConsumerStatefulWidget {
  const _ChannelTile({
    required this.channel,
    required this.spaceId,
    required this.selected,
    required this.canManageChannels,
    required this.onTap,
    this.onEdit,
  });

  final AccordChannel channel;
  final String? spaceId;
  final bool selected;
  final bool canManageChannels;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  ConsumerState<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends ConsumerState<_ChannelTile> {
  bool _hovered = false;

  /// When this row was last clicked, for the double-click-to-join fast path
  /// (see [isVoiceDoubleTap]). Per-tile, so clicking two rows in quick
  /// succession can't be mistaken for a double-click.
  DateTime? _lastTapAt;

  bool get _isVoice => widget.channel.type == 'voice';

  bool get _connectedHere =>
      ref.read(voiceControllerProvider).channelId == widget.channel.id;

  /// Explicitly connects to this voice channel. Selecting the channel never
  /// does this any more (#202) — only the row's hover button, its double-click,
  /// its context menu, and the lobby's Join button do.
  void _joinVoice() {
    final spaceId = widget.spaceId;
    if (!_isVoice || spaceId == null || _connectedHere) return;
    ref.read(voiceControllerProvider.notifier).join(widget.channel.id, spaceId);
  }

  /// Selects the channel; a second click inside the double-click window joins it
  /// instead of re-selecting (the first click already opened the tab).
  void _handleTap() {
    final now = DateTime.now();
    if (_isVoice && isVoiceDoubleTap(_lastTapAt, now)) {
      _lastTapAt = null;
      _joinVoice();
      return;
    }
    _lastTapAt = now;
    widget.onTap();
  }

  void _showMenu([Offset? position]) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    final connected = _connectedHere;
    showChannelContextMenu(
      context,
      ref,
      channel: widget.channel,
      spaceId: spaceId,
      canManageChannels: widget.canManageChannels,
      globalPosition: position,
      // Touch has no hover, so the sheet carries the join/disconnect action.
      leadingEntries: [
        if (_isVoice && !connected)
          AccordMenuEntry(
            label: 'Join Voice',
            icon: Icons.call,
            onSelected: _joinVoice,
          ),
        if (_isVoice && connected)
          AccordMenuEntry(
            label: 'Disconnect',
            icon: Icons.call_end,
            destructive: true,
            onSelected: () =>
                ref.read(voiceControllerProvider.notifier).leave(),
          ),
        if (_isVoice) const AccordMenuEntry.divider(),
      ],
    );
  }

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
    final isVoice = channel.type == 'voice';
    final enabled =
        isVoice ||
        channel.type == 'text' ||
        channel.type == 'forum' ||
        channel.type == 'announcement';
    final activeKey = ref.watch(
      connectionsControllerProvider.select((s) => s.activeKey),
    );
    final readState = activeKey == null
        ? const ReadStateSnapshot()
        : ref.watch(readStateControllerProvider(activeKey));
    // A channel set to `nothing` is silenced outright: no pip, no badge, no
    // bold name (its unread state is kept, so restoring the level restores the
    // indicator). A muted *space* still shows unread inside itself — that mute
    // only suppresses the rail roll-up.
    final channelLevels = ref.watch(
      settingsControllerProvider.select((s) => s.channelNotifications),
    );
    final unread =
        readState.isUnreadVisible(channel.id, channelLevels: channelLevels) &&
        !widget.selected;
    final mentions = readState.visibleMentionCount(
      channel.id,
      channelLevels: channelLevels,
    );

    // Voice extras: green tint + count when anyone is present / we're connected.
    final connectedHere =
        isVoice &&
        ref.watch(
          voiceControllerProvider.select((v) => v.channelId == channel.id),
        );
    final voiceCount = isVoice
        ? ref.watch(
            voiceStatesControllerProvider(ref.readActiveServerKey() ?? '').select(
              (cache) => voiceUserCount(cache, channel.id),
            ),
          )
        : 0;
    final iconColor = connectedHere
        ? colors.green
        : (enabled ? colors.dirtyWhite : colors.gray);

    final tileRow = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: widget.selected ? colors.darkGray : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? _handleTap : null,
            onLongPress: () => _showMenu(null),
            onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Icon(_glyph, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      channel.name ?? channel.id,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: enabled
                            ? (unread ? Colors.white : colors.dirtyWhite)
                            : colors.gray,
                        fontWeight: unread
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isVoice && voiceCount > 0)
                    Text(
                      '$voiceCount',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(color: colors.gray),
                    )
                  else if (mentions > 0)
                    _MentionBadge(count: mentions)
                  else if (unread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  // Selecting a voice channel only opens its lobby, so the row
                  // carries an explicit join (#202). Hover-only to keep the
                  // list quiet; touch users get the same action from the
                  // long-press menu, or by double-tapping the row.
                  if (isVoice &&
                      !connectedHere &&
                      _hovered &&
                      widget.spaceId != null) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Join Voice',
                      child: InkWell(
                        onTap: _joinVoice,
                        child: Icon(Icons.call, size: 14, color: colors.green),
                      ),
                    ),
                  ],
                  if (widget.onEdit != null && _hovered) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: widget.onEdit,
                      child: Icon(Icons.settings, size: 14, color: colors.gray),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!isVoice) return tileRow;
    return OnboardingAnchor(
      anchor: OnboardingAnchorId.voiceChannel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tileRow,
          VoiceParticipantList(channelId: channel.id, spaceId: widget.spaceId),
        ],
      ),
    );
  }
}

/// Red pill rendering the mention count for a channel (or rolled up across a
/// space's channels in the rail). Caps at "99+".
class _MentionBadge extends StatelessWidget {
  const _MentionBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFED4245),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
