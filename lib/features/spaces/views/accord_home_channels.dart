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
  void _toggleCollapsed(String categoryId) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    final settings = ref.read(settingsControllerProvider);
    ref.read(settingsControllerProvider.notifier).setCategoryCollapsed(
          spaceId,
          categoryId,
          !settings.isCategoryCollapsed(spaceId, categoryId),
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
            spacesControllerProvider
                .select((s) => s?.firstWhereOrNull((sp) => sp.id == id)),
          );
    final cdnUrl = ref.watchCdnUrl();
    final bannerUrl =
        space == null ? null : accordSpaceBannerUrl(space, cdnUrl);

    // Collapsed categories are persisted per-space via SettingsController
    // (mirrors the reference client's Config.set_category_collapsed).
    final collapsed = id == null
        ? const <String>{}
        : ref.watch(settingsControllerProvider
            .select((s) => s.collapsedCategories[id]?.toSet() ?? const <String>{}));

    // Show the settings gear only to members who can manage the space or roles,
    // and the channel-management affordances to those with manage_channels.
    var canManage = false;
    var canManageChannels = false;
    var canInvite = false;
    if (id != null) {
      final currentUserId = ref.watchUserId();
      final isAdmin = ref.watchIsAdmin();
      final members = ref.watch(accordMembersControllerProvider(id));
      final preview = ref.watch(rolePreviewControllerProvider);
      final perms = accordEffectivePermissions(
        space: space,
        selfMember: currentUserId == null ? null : members?[currentUserId],
        roles: space?.roles ?? const <AccordRole>[],
        currentUserId: currentUserId ?? '',
        currentUserIsAdmin: isAdmin,
        previewRoleId: preview?.spaceId == id ? preview?.roleId : null,
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
                  _HeaderAction(
                    tooltip: 'Search',
                    icon: Icons.search,
                    color: colors.dirtyWhite,
                    onPressed: () async {
                      final selection =
                          await showAccordSearch(context, spaceId: id);
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
                    onPressed: () => showAccordChannelReorder(context,
                        spaceId: id, channels: channels),
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
                ? (ref
                        .watch(connectionControllerProvider)
                        .isUnreachable
                    ? ServerUnreachable(onRetry: () {
                        final auth = ref.read(accordAuthProvider);
                        if (auth is AccordAuthLoggedIn) {
                          auth.client.ensureConnected();
                        }
                      })
                    : const Center(child: CircularProgressIndicator()))
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

  Widget tile(AccordChannel channel) => _ChannelTile(
        channel: channel,
        spaceId: spaceId,
        selected: channel.id == selectedChannelId,
        canManageChannels: canManageChannels,
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
    final isCollapsed = collapsed.contains(category.id);
    entries.add(_CategoryHeader(
      category: category,
      spaceId: spaceId,
      canManageChannels: canManageChannels,
      collapsed: isCollapsed,
      onToggle: () => onToggleCollapsed(category.id),
      onAdd: canManageChannels && spaceId != null
          ? () => showCreateChannelDialog(context,
              spaceId: spaceId, parentId: category.id)
          : null,
      onEdit: canManageChannels && spaceId != null
          ? () => showEditChannelDialog(context,
              spaceId: spaceId, channel: category)
          : null,
    ));
    if (!isCollapsed) {
      for (final channel in byParent[category.id] ?? const <AccordChannel>[]) {
        entries.add(tile(channel));
      }
    }
  }
  return entries;
}

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

  void _showMenu([Offset? position]) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    showChannelContextMenu(
      context,
      ref,
      channel: widget.channel,
      spaceId: spaceId,
      canManageChannels: widget.canManageChannels,
      globalPosition: position,
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
    final enabled = isVoice ||
        channel.type == 'text' ||
        channel.type == 'forum' ||
        channel.type == 'announcement';
    final activeKey = ref.watch(
      connectionsControllerProvider.select((s) => s.activeKey),
    );
    final readState = activeKey == null
        ? const ReadStateSnapshot()
        : ref.watch(readStateControllerProvider(activeKey));
    final unread = readState.isUnread(channel.id) && !widget.selected;
    final mentions = readState.mentionCount(channel.id);

    // Voice extras: green tint + count when anyone is present / we're connected.
    final connectedHere = isVoice &&
        ref.watch(voiceControllerProvider
            .select((v) => v.channelId == channel.id));
    final voiceCount = isVoice
        ? ref.watch(voiceStatesControllerProvider
            .select((cache) => voiceUserCount(cache, channel.id)))
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
            onTap: enabled ? widget.onTap : null,
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
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.normal,
                          ),
                    ),
                  ),
                  if (isVoice && voiceCount > 0)
                    Text('$voiceCount',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall!
                            .copyWith(color: colors.gray))
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
                  if (widget.onEdit != null && _hovered) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: widget.onEdit,
                      child: Icon(Icons.settings,
                          size: 14, color: colors.gray),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tileRow,
        VoiceParticipantList(channelId: channel.id, spaceId: widget.spaceId),
      ],
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

/// Sidebar channel list with inline long-press drag-to-reorder for space managers.
class _ChannelDragList extends ConsumerStatefulWidget {
  const _ChannelDragList({
    required this.spaceId,
    required this.channels,
    required this.selectedChannelId,
    required this.onSelect,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final String spaceId;
  final List<AccordChannel> channels;
  final String? selectedChannelId;
  final ValueChanged<String> onSelect;
  final Set<String> collapsed;
  final ValueChanged<String> onToggleCollapsed;

  @override
  ConsumerState<_ChannelDragList> createState() => _ChannelDragListState();
}

class _ChannelDragListState extends ConsumerState<_ChannelDragList> {
  late List<_DragEntry> _items;
  late String _signature;
  bool _persisting = false;
  bool _pendingPersist = false;

  @override
  void initState() {
    super.initState();
    _items = _flatten(widget.channels);
    _signature = _signatureOf(widget.channels);
  }

  @override
  void didUpdateWidget(covariant _ChannelDragList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ignore incoming list churn while our own optimistic PATCHes are landing;
    // we reconcile once at the end of [_persist].
    if (_persisting) return;
    final sig = _signatureOf(widget.channels);
    if (sig != _signature) _resync();
  }

  void _resync() {
    setState(() {
      _items = _flatten(widget.channels);
      _signature = _signatureOf(widget.channels);
    });
  }

  static int _pos(AccordChannel c) => parseChannelPosition(c);

  static String _signatureOf(List<AccordChannel> channels) =>
      channelListSignature(channels);

  /// Categories (each followed by their children) then uncategorized channels,
  /// each group ordered by `position`. Children carry their parent's id.
  static List<_DragEntry> _flatten(List<AccordChannel> channels) {
    final sorted = [...channels]..sort((a, b) => _pos(a).compareTo(_pos(b)));
    final categories = sorted.where((c) => c.type == 'category').toList();
    final leaves = sorted.where((c) => c.type != 'category').toList();
    final byParent = <String?, List<AccordChannel>>{};
    for (final c in leaves) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    final out = <_DragEntry>[];
    for (final c in byParent[null] ?? const <AccordChannel>[]) {
      out.add(_DragEntry.channel(c, parentId: null));
    }
    for (final category in categories) {
      out.add(_DragEntry.category(category));
      for (final child in byParent[category.id] ?? const <AccordChannel>[]) {
        out.add(_DragEntry.channel(child, parentId: category.id));
      }
    }
    return out;
  }

  /// The items actually shown: every category, plus the children of categories
  /// that aren't collapsed (uncategorized channels are always shown).
  List<_DragEntry> get _visible => _items
      .where((e) => e.isCategory || !widget.collapsed.contains(e.parentId))
      .toList();

  void _recomputeParents(_DragEntry moved) {
    if (moved.isCategory) return;
    String? newParent;
    for (final e in _items) {
      if (e.isCategory) {
        newParent = e.channel.id;
      } else if (identical(e, moved)) {
        moved.parentId = newParent;
        return;
      }
    }
    moved.parentId = null;
  }

  // [ReorderableListView.onReorder] reports [newIndex] in pre-removal
  // coordinates (the slot is counted as if the dragged item were still
  // present), so apply the canonical decrement to convert it to the target
  // index within the post-removal list that the logic below expects.
  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final visible = _visible;
    final moved = visible[oldIndex];
    final newVisible = [...visible]..removeAt(oldIndex);
    final _DragEntry? before =
        newIndex < newVisible.length ? newVisible[newIndex] : null;

    // A dragged category carries its contiguous children with it.
    final List<_DragEntry> block;
    if (moved.isCategory) {
      final start = _items.indexOf(moved);
      var end = start + 1;
      while (end < _items.length && !_items[end].isCategory) {
        end++;
      }
      block = _items.sublist(start, end);
    } else {
      block = [moved];
    }

    setState(() {
      _items.removeWhere(block.contains);
      final insertAt = before == null ? _items.length : _items.indexOf(before);
      _items.insertAll(insertAt < 0 ? _items.length : insertAt, block);
      _recomputeParents(moved);
    });
    _schedulePersist();
  }

  void _schedulePersist() {
    if (_persisting) {
      _pendingPersist = true;
    } else {
      _persist();
    }
  }

  /// Walks the new ordering and PATCHes any channel whose (parent, position)
  /// changed. Positions count within each bucket (categories share one bucket;
  /// each category's children share another) so siblings stay coherent.
  Future<void> _persist() async {
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    if (client == null) return;
    final notifier =
        ref.read(accordChannelsControllerProvider(widget.spaceId).notifier);

    final updates = <_DragUpdate>[];
    var categoryPos = 0;
    final childPos = <String?, int>{};
    for (final entry in _items) {
      final ch = entry.channel;
      if (entry.isCategory) {
        if (_pos(ch) != categoryPos) {
          updates.add(_DragUpdate(ch.id, position: categoryPos));
        }
        categoryPos++;
      } else {
        final pos = childPos[entry.parentId] ?? 0;
        childPos[entry.parentId] = pos + 1;
        final parentChanged = ch.parentId != entry.parentId;
        final positionChanged = _pos(ch) != pos;
        if (parentChanged || positionChanged) {
          updates.add(_DragUpdate(
            ch.id,
            position: pos,
            parentId: parentChanged ? entry.parentId : null,
            includeParent: parentChanged,
          ));
        }
      }
    }

    if (updates.isEmpty) return;

    _persisting = true;
    try {
      for (final u in updates) {
        final body = <String, dynamic>{'position': u.position};
        if (u.includeParent) body['parent_id'] = u.parentId;
        await notifier.updateChannel(client, u.channelId, body);
      }
    } finally {
      _persisting = false;
      if (_pendingPersist && mounted) {
        _pendingPersist = false;
        _persist();
      } else if (mounted) {
        _resync();
      }
    }
  }

  Widget _buildItem(BuildContext context, _DragEntry entry) {
    if (entry.isCategory) {
      final cat = entry.channel;
      return _CategoryHeader(
        category: cat,
        spaceId: widget.spaceId,
        canManageChannels: true,
        collapsed: widget.collapsed.contains(cat.id),
        onToggle: () => widget.onToggleCollapsed(cat.id),
        onAdd: () => showCreateChannelDialog(context,
            spaceId: widget.spaceId, parentId: cat.id),
        onEdit: () => showEditChannelDialog(context,
            spaceId: widget.spaceId, channel: cat),
      );
    }
    final ch = entry.channel;
    return _ChannelTile(
      channel: ch,
      spaceId: widget.spaceId,
      selected: ch.id == widget.selectedChannelId,
      canManageChannels: true,
      onTap: () => widget.onSelect(ch.id),
      onEdit: () =>
          showEditChannelDialog(context, spaceId: widget.spaceId, channel: ch),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      buildDefaultDragHandles: false,
      itemCount: visible.length,
      onReorder: _onReorder,
      itemBuilder: (context, index) {
        final entry = visible[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(entry.channel.id),
          index: index,
          child: _buildItem(context, entry),
        );
      },
    );
  }
}

/// One row in the drag model: a category header or a channel tile.
class _DragEntry {
  _DragEntry.category(this.channel)
      : isCategory = true,
        parentId = null;
  _DragEntry.channel(this.channel, {required this.parentId})
      : isCategory = false;

  final AccordChannel channel;
  final bool isCategory;
  String? parentId;
}

/// A pending PATCH from a reorder: channel's new position and optional new parent.
class _DragUpdate {
  const _DragUpdate(
    this.channelId, {
    required this.position,
    this.parentId,
    this.includeParent = false,
  });

  final String channelId;
  final int position;
  final String? parentId;
  final bool includeParent;
}
