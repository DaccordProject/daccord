part of 'accord_home.dart';

/// A rail entry: either a folder (with its in-group member spaces) or a single
/// ungrouped space. Built per server group in the persisted order.
class _RailUnit {
  const _RailUnit.folder(this.folder, this.spaces) : space = null;
  const _RailUnit.space(_RailSpace this.space)
    : folder = null,
      spaces = const [];

  final SpaceFolder? folder;
  final _RailSpace? space;
  final List<_RailSpace> spaces; // folder members present in this group

  bool get isFolder => folder != null;
}

class _RailSpace {
  const _RailSpace(this.key, this.space);

  final String key;
  final AccordSpace space;
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
    final hidden = <_RailSpace>[];
    for (final conn in connections.connections) {
      final isActive = conn.key == activeKey;
      final spaces = isActive ? (liveActiveSpaces ?? conn.spaces) : conn.spaces;
      final cdnUrl = conn.session.server.cdnUrl;
      for (final s in spaces) {
        final entityKey = ServerEntityKey(conn.key, s.id).encoded;
        connOf[entityKey] = _SpaceConn(conn.key, cdnUrl, isActive);
        if (settings.isSpaceHidden(conn.key, s.id)) {
          hidden.add(_RailSpace(entityKey, s));
        } else {
          byId[entityKey] = s;
        }
      }
    }

    // The effective global order, used when persisting a reorder so dragged
    // spaces keep a stable position.
    final globalOrder = _orderedIds(byId.keys.toList(), settings.spaceOrder);
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
      onDropSpace: (spaceId) => _dropSpaceBefore(
        settingsCtl,
        settings,
        globalOrder,
        spaceId,
        anchorId,
      ),
      onDropFolder: (folderId) => _moveFolderBefore(
        settingsCtl,
        settings,
        globalOrder,
        folderId,
        anchorId,
      ),
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
            onDropSpace: (spaceKey) => settingsCtl.moveSpaceToFolder(
              ServerEntityKey.tryDecode(spaceKey)!,
              unit.folder!.id,
            ),
            onReorderFolderBefore: (folderId) => _moveFolderBefore(
              settingsCtl,
              settings,
              globalOrder,
              folderId,
              unit.spaces.first.key,
            ),
            onMemberDropBefore: (draggedId, targetMemberId) =>
                settingsCtl.moveSpaceToFolder(
                  ServerEntityKey.tryDecode(draggedId)!,
                  unit.folder!.id,
                  before: ServerEntityKey.tryDecode(targetMemberId)!,
                ),
          ),
        );
      } else {
        final railSpace = unit.space!;
        final space = railSpace.space;
        final entityKey = railSpace.key;
        final sc = connOf[entityKey];
        final serverKey = sc?.serverKey ?? '';
        railItems.add(
          _DraggableSpace(
            space: space,
            cdnUrl: sc?.cdnUrl,
            serverKey: serverKey,
            entityKey: entityKey,
            selected: (sc?.active ?? false) && space.id == selectedSpaceId,
            onTap: () => onSelect(serverKey, space.id),
            onMergeSpace: (movedId) => settingsCtl.createFolder(
              spaces: [
                ServerEntityKey.tryDecode(entityKey)!,
                ServerEntityKey.tryDecode(movedId)!,
              ],
            ),
            onDropFolderBefore: (folderId) => _moveFolderBefore(
              settingsCtl,
              settings,
              globalOrder,
              folderId,
              entityKey,
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
  static List<String> _orderedIds(List<String> ids, List<String> savedOrder) {
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
          final members = <_RailSpace>[
            for (final sid in folder.spaceIds)
              if (byId[sid] != null) _RailSpace(sid, byId[sid]!),
          ];
          units.add(_RailUnit.folder(folder, members));
        }
        continue;
      }
      final space = byId[id];
      if (space != null) units.add(_RailUnit.space(_RailSpace(id, space)));
    }
    return units;
  }

  /// The id used to anchor an insertion before [unit]: a standalone space's own
  /// id, or a folder's first member (folders anchor at their first member's
  /// position in [spaceOrder]).
  String _unitAnchor(_RailUnit unit) =>
      unit.isFolder ? unit.spaces.first.key : unit.space!.key;

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
    ctl.setSpaceOrder([for (final id in next) ServerEntityKey.tryDecode(id)!]);
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
    if (inFolder) {
      ctl.moveSpaceToFolder(ServerEntityKey.tryDecode(movedId)!, null);
    }
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
    ctl.setSpaceOrder([for (final id in rest) ServerEntityKey.tryDecode(id)!]);
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
    final entityKey = ServerEntityKey(serverKey, space.id);
    final inFolder = settings.spaceFolders.any(
      (f) => f.spaceIds.contains(entityKey.encoded),
    );

    final entries = <AccordMenuEntry>[
      ..._serverActionEntries(context, ref, space, serverKey),
      AccordMenuEntry(
        label: 'New folder with this space',
        icon: Icons.create_new_folder_outlined,
        onSelected: () => ctl.createFolder(spaces: [entityKey]),
      ),
      for (final f in settings.spaceFolders)
        if (!f.spaceIds.contains(entityKey.encoded))
          AccordMenuEntry(
            label: 'Move to "${f.name.isEmpty ? 'Folder' : f.name}"',
            icon: Icons.folder_outlined,
            onSelected: () => ctl.moveSpaceToFolder(entityKey, f.id),
          ),
      if (inFolder)
        AccordMenuEntry(
          label: 'Remove from folder',
          icon: Icons.folder_off_outlined,
          onSelected: () => ctl.moveSpaceToFolder(entityKey, null),
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
    List<_RailSpace> hidden,
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
            for (final railSpace in hidden)
              ListTile(
                leading: _SpaceIcon(
                  space: railSpace.space,
                  selected: false,
                  cdnUrl: connOf[railSpace.key]?.cdnUrl,
                  serverKey: connOf[railSpace.key]?.serverKey ?? '',
                  // Identification only — the row's action is "Unhide".
                  onTap: null,
                ),
                title: Text(
                  railSpace.space.name,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Unhide'),
                  onPressed: () {
                    final key = ServerEntityKey.tryDecode(railSpace.key)!;
                    ctl.setSpaceHidden(key.serverKey, key.entityId, false);
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
