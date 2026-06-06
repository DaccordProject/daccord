part of 'accord_home.dart';

/// A rail entry: either a folder (with its in-group member spaces) or a single
/// ungrouped space. Built per server group in the persisted order.
class _RailUnit {
  const _RailUnit.folder(this.folder, this.spaces) : space = null;
  const _RailUnit.space(AccordSpace this.space)
    : folder = null,
      spaces = const [];

  final SpaceFolder? folder;
  final AccordSpace? space;
  final List<AccordSpace> spaces; // folder members present in this group

  bool get isFolder => folder != null;
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
    final liveActiveSpaces = ref.watch(spacesControllerProvider);
    final multi = connections.hasMultiple;
    final settings = ref.watch(settingsControllerProvider);
    final settingsCtl = ref.read(settingsControllerProvider.notifier);

    // The effective global order across every group, used when persisting a
    // reorder so dragged spaces keep a stable position.
    final globalOrder = <String>[];
    final railItems = <Widget>[];

    for (final conn in connections.connections) {
      final isActive = conn.key == activeKey;
      final spaces = isActive ? (liveActiveSpaces ?? conn.spaces) : conn.spaces;
      final cdnUrl = conn.session.server.cdnUrl;
      if (spaces.isEmpty && !multi) continue;

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

      final ordered = _orderedIds(spaces, settings.spaceOrder);
      globalOrder.addAll(ordered);
      final byId = {for (final s in spaces) s.id: s};
      final units = _buildUnits(ordered, byId, settings.spaceFolders);

      for (final unit in units) {
        railItems.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: unit.isFolder
                ? _FolderTile(
                    folder: unit.folder!,
                    spaces: unit.spaces,
                    serverKey: conn.key,
                    cdnUrl: cdnUrl,
                    selectedSpaceId: isActive ? selectedSpaceId : null,
                    onSelect: onSelect,
                    onDropSpace: (spaceId) =>
                        settingsCtl.moveSpaceToFolder(spaceId, unit.folder!.id),
                  )
                : _DraggableSpace(
                    space: unit.space!,
                    cdnUrl: cdnUrl,
                    selected: isActive && unit.space!.id == selectedSpaceId,
                    onTap: () => onSelect(conn.key, unit.space!.id),
                    onReorderBefore: (movedId) => _reorderBefore(
                      settingsCtl,
                      globalOrder,
                      movedId,
                      unit.space!.id,
                    ),
                    onMenu: () => _spaceMenu(context, ref, unit.space!),
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
            icon: Icon(
              Icons.chat_bubble_outline,
              size: 20,
              color: colors.dirtyWhite,
            ),
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
            icon: Icon(
              Icons.switch_account,
              color: colors.dirtyWhite,
              size: 20,
            ),
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

  /// Orders [spaces] by the saved [savedOrder], appending any not listed in
  /// their natural (server) order.
  static List<String> _orderedIds(
    List<AccordSpace> spaces,
    List<String> savedOrder,
  ) {
    final ids = spaces.map((s) => s.id).toList();
    final idSet = ids.toSet();
    final inOrder = [
      for (final id in savedOrder)
        if (idSet.contains(id)) id,
    ];
    final placed = inOrder.toSet();
    final rest = [
      for (final id in ids)
        if (!placed.contains(id)) id,
    ];
    return [...inOrder, ...rest];
  }

  /// Builds the rail units for one group: folders are emitted inline at the
  /// position of their first-ordered member space; other spaces stand alone.
  static List<_RailUnit> _buildUnits(
    List<String> orderedIds,
    Map<String, AccordSpace> byId,
    List<SpaceFolder> folders,
  ) {
    final folderOf = <String, SpaceFolder>{};
    for (final f in folders) {
      for (final sid in f.spaceIds) {
        folderOf[sid] = f;
      }
    }
    final emittedFolders = <String>{};
    final units = <_RailUnit>[];
    for (final id in orderedIds) {
      final folder = folderOf[id];
      if (folder != null) {
        if (emittedFolders.add(folder.id)) {
          final members = [
            for (final sid in folder.spaceIds)
              if (byId[sid] != null) byId[sid]!,
          ];
          units.add(_RailUnit.folder(folder, members));
        }
        continue;
      }
      final space = byId[id];
      if (space != null) units.add(_RailUnit.space(space));
    }
    return units;
  }

  void _reorderBefore(
    SettingsController ctl,
    List<String> globalOrder,
    String movedId,
    String targetId,
  ) {
    if (movedId == targetId) return;
    final next = [
      for (final id in globalOrder)
        if (id != movedId) id,
    ];
    final idx = next.indexOf(targetId);
    if (idx < 0) {
      next.add(movedId);
    } else {
      next.insert(idx, movedId);
    }
    ctl.setSpaceOrder(next);
  }

  /// Long-press menu for a space: folder assignment + new-folder.
  Future<void> _spaceMenu(
    BuildContext context,
    WidgetRef ref,
    AccordSpace space,
  ) async {
    final settings = ref.read(settingsControllerProvider);
    final ctl = ref.read(settingsControllerProvider.notifier);
    final inFolder = settings.spaceFolders.any(
      (f) => f.spaceIds.contains(space.id),
    );
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder with this space'),
              onTap: () {
                ctl.createFolder(spaceIds: [space.id]);
                Navigator.of(ctx).pop();
              },
            ),
            for (final f in settings.spaceFolders)
              if (!f.spaceIds.contains(space.id))
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(
                    'Move to "${f.name.isEmpty ? 'Folder' : f.name}"',
                  ),
                  onTap: () {
                    ctl.moveSpaceToFolder(space.id, f.id);
                    Navigator.of(ctx).pop();
                  },
                ),
            if (inFolder)
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Remove from folder'),
                onTap: () {
                  ctl.moveSpaceToFolder(space.id, null);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// A space icon that can be dragged (to reorder / into folders) and accepts a
/// dropped space to reorder before itself.
class _DraggableSpace extends StatelessWidget {
  const _DraggableSpace({
    required this.space,
    required this.cdnUrl,
    required this.selected,
    required this.onTap,
    required this.onReorderBefore,
    required this.onMenu,
  });

  final AccordSpace space;
  final String? cdnUrl;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<String> onReorderBefore;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final icon = _SpaceIcon(
      space: space,
      selected: selected,
      cdnUrl: cdnUrl,
      onTap: onTap,
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != space.id,
      onAcceptWithDetails: (d) => onReorderBefore(d.data),
      builder: (context, candidate, _) => Opacity(
        opacity: candidate.isNotEmpty ? 0.5 : 1,
        child: LongPressDraggable<String>(
          data: space.id,
          feedback: Material(
            color: Colors.transparent,
            child: _SpaceIcon(
              space: space,
              selected: false,
              cdnUrl: cdnUrl,
              onTap: () {},
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: icon),
          // Long-press drives the drag (reorder / into-folder); the rail
          // management menu (new folder, move/remove) opens on double-tap or
          // right-click so it stays reachable on every platform.
          child: GestureDetector(
            onDoubleTap: onMenu,
            onSecondaryTap: onMenu,
            child: icon,
          ),
        ),
      ),
    );
  }
}

/// A collapsible folder tile in the rail. Tap toggles collapse; long-press opens
/// the management menu; it accepts dropped spaces to add them.
class _FolderTile extends ConsumerWidget {
  const _FolderTile({
    required this.folder,
    required this.spaces,
    required this.serverKey,
    required this.cdnUrl,
    required this.selectedSpaceId,
    required this.onSelect,
    required this.onDropSpace,
  });

  final SpaceFolder folder;
  final List<AccordSpace> spaces;
  final String serverKey;
  final String? cdnUrl;
  final String? selectedSpaceId;
  final void Function(String serverKey, String spaceId) onSelect;
  final ValueChanged<String> onDropSpace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final ctl = ref.read(settingsControllerProvider.notifier);
    final folderColor = folder.color != null
        ? Color(folder.color!)
        : colors.darkGray;

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => !folder.spaceIds.contains(d.data),
      onAcceptWithDetails: (d) => onDropSpace(d.data),
      builder: (context, candidate, _) {
        final highlight = candidate.isNotEmpty;
        return Column(
          children: [
            Center(
              child: GestureDetector(
                onTap: () =>
                    ctl.setFolderCollapsed(folder.id, !folder.collapsed),
                onLongPress: () => _folderMenu(context, ref),
                onSecondaryTap: () => _folderMenu(context, ref),
                child: Tooltip(
                  message: folder.name.isEmpty ? 'Folder' : folder.name,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: folderColor.withValues(alpha: highlight ? 1 : 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: highlight
                          ? Border.all(color: colors.primary, width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      folder.collapsed ? Icons.folder : Icons.folder_open,
                      color: colors.dirtyWhite,
                    ),
                  ),
                ),
              ),
            ),
            if (!folder.collapsed)
              for (final space in spaces)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    onLongPress: () => _memberMenu(context, ctl, space),
                    onSecondaryTap: () => _memberMenu(context, ctl, space),
                    child: _SpaceIcon(
                      space: space,
                      selected: space.id == selectedSpaceId,
                      cdnUrl: cdnUrl,
                      onTap: () => onSelect(serverKey, space.id),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Future<void> _memberMenu(
    BuildContext context,
    SettingsController ctl,
    AccordSpace space,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text('Remove "${space.name}" from folder'),
              onTap: () {
                ctl.moveSpaceToFolder(space.id, null);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _folderMenu(BuildContext context, WidgetRef ref) async {
    final ctl = ref.read(settingsControllerProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                folder.collapsed ? Icons.unfold_more : Icons.unfold_less,
              ),
              title: Text(folder.collapsed ? 'Expand' : 'Collapse'),
              onTap: () {
                ctl.setFolderCollapsed(folder.id, !folder.collapsed);
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final name = await _promptName(context, folder.name);
                if (name != null) ctl.renameFolder(folder.id, name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Recolor'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final color = await _pickColor(context);
                if (color != null) {
                  ctl.setFolderColor(folder.id, color == 0 ? null : color);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_delete_outlined),
              title: const Text('Delete folder'),
              onTap: () {
                ctl.deleteFolder(folder.id);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptName(BuildContext context, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Folder name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<int?> _pickColor(BuildContext context) {
    const palette = <int>[
      0, // default
      0xFF5865F2,
      0xFF57F287,
      0xFFEB459E,
      0xFFFEE75C,
      0xFFED4245,
      0xFF88C0D0,
      0xFFFF7A45,
    ];
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Folder color'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final argb in palette)
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(argb),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: argb == 0 ? Colors.grey : Color(argb),
                    shape: BoxShape.circle,
                  ),
                  child: argb == 0
                      ? const Icon(Icons.clear, size: 16, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpaceIcon extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final iconUrl = _spaceIconUrl(space, cdnUrl);
    // Roll up per-channel read state into a single rail-level indicator. We
    // only consider channels we've already loaded — the rail doesn't force a
    // fetch for every server just to compute a badge.
    final readState = ref.watch(readStateControllerProvider);
    final channels =
        ref.watch(accordChannelsControllerProvider(space.id)) ??
        const <AccordChannel>[];
    final channelIds = channels.map((c) => c.id);
    final hasUnread = !selected && readState.anyUnread(channelIds);
    final mentions = readState.mentionsAcross(channelIds);
    final radius = BorderRadius.circular(selected ? 16 : 24);
    final fallback = Text(
      _initials,
      style: Theme.of(
        context,
      ).textTheme.titleSmall!.copyWith(color: Colors.white),
    );
    return Center(
      child: Tooltip(
        message: space.name,
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
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
              if (mentions > 0)
                Positioned(
                  right: -4,
                  top: -2,
                  child: _MentionBadge(count: mentions),
                )
              else if (hasUnread)
                Positioned(
                  left: -4,
                  top: 18,
                  child: Container(
                    width: 8,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
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
            border: active ? Border.all(color: colors.primary, width: 2) : null,
          ),
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Text(
                _initial,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colors.dirtyWhite),
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
