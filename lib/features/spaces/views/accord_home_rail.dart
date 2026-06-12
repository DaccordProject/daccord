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

/// Which connection a space in the (flat, cross-account) rail belongs to, so a
/// space icon can resolve its CDN, route taps to the right server, and reflect
/// whether that server is the active one — without the rail being grouped by
/// server.
class _SpaceConn {
  const _SpaceConn(this.serverKey, this.cdnUrl, this.active);

  final String serverKey;
  final String? cdnUrl;
  final bool active;
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
    final settings = ref.watch(settingsControllerProvider);
    final settingsCtl = ref.read(settingsControllerProvider.notifier);

    // Spaces are a single flat, user-curated list across every connected
    // account; the only grouping is folders the user creates. Aggregate every
    // connection's spaces, remembering which connection each one belongs to so
    // taps route to the right server even though the rail isn't grouped by one.
    final byId = <String, AccordSpace>{};
    final connOf = <String, _SpaceConn>{};
    // Spaces the user hid from the rail (still joined) — collected so an "N
    // hidden" affordance can offer to restore them.
    final hidden = <AccordSpace>[];
    for (final conn in connections.connections) {
      final isActive = conn.key == activeKey;
      final spaces = isActive ? (liveActiveSpaces ?? conn.spaces) : conn.spaces;
      final cdnUrl = conn.session.server.cdnUrl;
      for (final s in spaces) {
        connOf[s.id] = _SpaceConn(conn.key, cdnUrl, isActive);
        if (settings.isSpaceHidden(s.id)) {
          hidden.add(s);
        } else {
          byId[s.id] = s;
        }
      }
    }

    // The effective global order, used when persisting a reorder so dragged
    // spaces keep a stable position.
    final globalOrder = _orderedIds(byId.values.toList(), settings.spaceOrder);
    final units = _buildUnits(globalOrder, byId, settings.spaceFolders);

    final railItems = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _DirectMessagesButton(
          onTap: () => showAccordDirectMessages(context),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Divider(color: colors.darkGray, height: 2, thickness: 2),
      ),
    ];
    // A drop zone for the track at [anchorId] (null = end of the list), so a
    // space/folder can be inserted between items — including between a space and
    // a folder — rather than only onto an icon.
    Widget gapFor(String? anchorId) => _InsertionGap(
      onDropSpace: (spaceId) =>
          _dropSpaceBefore(settingsCtl, settings, globalOrder, spaceId, anchorId),
      onDropFolder: (folderId) =>
          _moveFolderBefore(settingsCtl, settings, globalOrder, folderId, anchorId),
    );

    for (final unit in units) {
      railItems.add(gapFor(_unitAnchor(unit)));
      if (unit.isFolder) {
        railItems.add(
          _FolderTile(
            folder: unit.folder!,
            spaces: unit.spaces,
            connOf: connOf,
            selectedSpaceId: selectedSpaceId,
            onSelect: onSelect,
            onDropSpace: (spaceId) =>
                settingsCtl.moveSpaceToFolder(spaceId, unit.folder!.id),
            onReorderFolderBefore: (folderId) => _moveFolderBefore(
              settingsCtl,
              settings,
              globalOrder,
              folderId,
              unit.spaces.isNotEmpty ? unit.spaces.first.id : null,
            ),
            onMemberDropBefore: (draggedId, targetMemberId) =>
                settingsCtl.moveSpaceToFolder(
                  draggedId,
                  unit.folder!.id,
                  before: targetMemberId,
                ),
          ),
        );
      } else {
        final space = unit.space!;
        final sc = connOf[space.id];
        final serverKey = sc?.serverKey ?? '';
        railItems.add(
          _DraggableSpace(
            space: space,
            cdnUrl: sc?.cdnUrl,
            serverKey: serverKey,
            selected: (sc?.active ?? false) && space.id == selectedSpaceId,
            onTap: () => onSelect(serverKey, space.id),
            onDropSpaceBefore: (movedId) => _dropSpaceBefore(
              settingsCtl,
              settings,
              globalOrder,
              movedId,
              space.id,
            ),
            onDropFolderBefore: (folderId) => _moveFolderBefore(
              settingsCtl,
              settings,
              globalOrder,
              folderId,
              space.id,
            ),
            onMenu: (pos) => _spaceMenu(context, ref, space, serverKey, pos),
          ),
        );
      }
    }
    // Trailing gap so items can be dropped at the very end of the list.
    railItems.add(gapFor(null));

    railItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _AddServerButton(onTap: onAddServer),
      ),
    );

    if (hidden.isNotEmpty) {
      railItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _HiddenServersButton(
            count: hidden.length,
            onTap: () => _showHiddenServers(context, ref, hidden, connOf),
          ),
        ),
      );
    }

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
          if (members.isNotEmpty) units.add(_RailUnit.folder(folder, members));
        }
        continue;
      }
      final space = byId[id];
      if (space != null) units.add(_RailUnit.space(space));
    }
    return units;
  }

  /// The id used to anchor an insertion before [unit]: a standalone space's own
  /// id, or a folder's first member (folders anchor at their first member's
  /// position in [spaceOrder]).
  String _unitAnchor(_RailUnit unit) {
    if (unit.isFolder) {
      // spaces is always non-empty here (empty folders are skipped in
      // _buildUnits), but guard defensively so a stale unit never crashes.
      return unit.spaces.isNotEmpty ? unit.spaces.first.id : '';
    }
    return unit.space!.id;
  }

  void _reorderBefore(
    SettingsController ctl,
    List<String> globalOrder,
    String movedId,
    String? targetId,
  ) {
    if (movedId == targetId) return;
    final next = [
      for (final id in globalOrder)
        if (id != movedId) id,
    ];
    final idx = targetId == null ? -1 : next.indexOf(targetId);
    if (idx < 0) {
      next.add(movedId);
    } else {
      next.insert(idx, movedId);
    }
    ctl.setSpaceOrder(next);
  }

  /// Drops [movedId] before [targetId] in the rail, first pulling it out of any
  /// folder it belonged to (so a folder member dragged onto a rail space leaves
  /// the folder and lands at that position).
  void _dropSpaceBefore(
    SettingsController ctl,
    AccordSettings settings,
    List<String> globalOrder,
    String movedId,
    String? targetId,
  ) {
    if (movedId == targetId) return;
    final inFolder = settings.spaceFolders.any(
      (f) => f.spaceIds.contains(movedId),
    );
    if (inFolder) ctl.moveSpaceToFolder(movedId, null);
    _reorderBefore(ctl, globalOrder, movedId, targetId);
  }

  /// Reorders the whole folder [folderId] so it sits just before [anchorId] in
  /// the rail. Folders anchor at their first member's position in [spaceOrder],
  /// so this relocates the folder's member ids as a contiguous block.
  void _moveFolderBefore(
    SettingsController ctl,
    AccordSettings settings,
    List<String> globalOrder,
    String folderId,
    String? anchorId,
  ) {
    SpaceFolder? folder;
    for (final f in settings.spaceFolders) {
      if (f.id == folderId) {
        folder = f;
        break;
      }
    }
    if (folder == null) return;
    final inOrder = globalOrder.toSet();
    final block = [
      for (final id in folder.spaceIds)
        if (inOrder.contains(id)) id,
    ];
    if (block.isEmpty || block.contains(anchorId)) return;
    final blockSet = block.toSet();
    final rest = [
      for (final id in globalOrder)
        if (!blockSet.contains(id)) id,
    ];
    final idx = anchorId == null ? -1 : rest.indexOf(anchorId);
    if (idx < 0) {
      rest.addAll(block);
    } else {
      rest.insertAll(idx, block);
    }
    ctl.setSpaceOrder(rest);
  }

  /// Context menu for a space (double-tap / right-click): server actions
  /// (invite, settings, leave) above the folder-assignment actions. [serverKey]
  /// is the owning connection's key, so actions hit the right server even when
  /// it isn't the active one.
  Future<void> _spaceMenu(
    BuildContext context,
    WidgetRef ref,
    AccordSpace space,
    String serverKey,
    Offset position,
  ) {
    final settings = ref.read(settingsControllerProvider);
    final ctl = ref.read(settingsControllerProvider.notifier);
    final inFolder = settings.spaceFolders.any(
      (f) => f.spaceIds.contains(space.id),
    );

    final entries = <AccordMenuEntry>[
      ..._serverActionEntries(context, ref, space, serverKey),
      AccordMenuEntry(
        label: 'New folder with this space',
        icon: Icons.create_new_folder_outlined,
        onSelected: () => ctl.createFolder(spaceIds: [space.id]),
      ),
      for (final f in settings.spaceFolders)
        if (!f.spaceIds.contains(space.id))
          AccordMenuEntry(
            label: 'Move to "${f.name.isEmpty ? 'Folder' : f.name}"',
            icon: Icons.folder_outlined,
            onSelected: () => ctl.moveSpaceToFolder(space.id, f.id),
          ),
      if (inFolder)
        AccordMenuEntry(
          label: 'Remove from folder',
          icon: Icons.folder_off_outlined,
          onSelected: () => ctl.moveSpaceToFolder(space.id, null),
        ),
    ];

    return showAccordContextMenu(
      context,
      entries: entries,
      globalPosition: position,
      title: space.name,
    );
  }

  /// Lists the spaces hidden from the rail with a one-tap restore each — the
  /// counterpart to the "Hide from list" action so a hidden space is always
  /// reachable again without leaving and rejoining.
  Future<void> _showHiddenServers(
    BuildContext context,
    WidgetRef ref,
    List<AccordSpace> hidden,
    Map<String, _SpaceConn> connOf,
  ) async {
    final ctl = ref.read(settingsControllerProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Hidden servers'),
              ),
            ),
            const Divider(height: 1),
            for (final space in hidden)
              ListTile(
                leading: _SpaceIcon(
                  space: space,
                  selected: false,
                  cdnUrl: connOf[space.id]?.cdnUrl,
                  serverKey: connOf[space.id]?.serverKey ?? '',
                  onTap: () {},
                ),
                title: Text(space.name, overflow: TextOverflow.ellipsis),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Unhide'),
                  onPressed: () {
                    ctl.setSpaceHidden(space.id, false);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
