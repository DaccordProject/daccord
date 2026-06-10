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

    final railItems = <Widget>[];
    for (final unit in units) {
      if (unit.isFolder) {
        railItems.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _FolderTile(
              folder: unit.folder!,
              spaces: unit.spaces,
              connOf: connOf,
              selectedSpaceId: selectedSpaceId,
              onSelect: onSelect,
              onDropSpace: (spaceId) =>
                  settingsCtl.moveSpaceToFolder(spaceId, unit.folder!.id),
            ),
          ),
        );
      } else {
        final space = unit.space!;
        final sc = connOf[space.id];
        final serverKey = sc?.serverKey ?? '';
        railItems.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _DraggableSpace(
              space: space,
              cdnUrl: sc?.cdnUrl,
              serverKey: serverKey,
              selected: (sc?.active ?? false) && space.id == selectedSpaceId,
              onTap: () => onSelect(serverKey, space.id),
              onReorderBefore: (movedId) => _reorderBefore(
                settingsCtl,
                globalOrder,
                movedId,
                space.id,
              ),
              onMenu: (pos) =>
                  _spaceMenu(context, ref, space, serverKey, pos),
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

/// The mute / invite / settings / leave entries shared by the standalone-space
/// menu and the folder-member menu. Gated on the space's own connection session,
/// so actions hit the right server even when it isn't the active one.
List<AccordMenuEntry> _serverActionEntries(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey,
) {
  final conn = ref.read(connectionsControllerProvider).connectionFor(serverKey);
  final session = conn?.session;
  final userId = session?.userId;
  final members = ref.read(accordMembersControllerProvider(space.id));
  final preview = ref.read(rolePreviewControllerProvider);
  final perms = accordEffectivePermissions(
    space: space,
    selfMember: userId == null ? null : members?[userId],
    roles: space.roles,
    currentUserId: userId ?? '',
    currentUserIsAdmin: session?.isAdmin ?? false,
    previewRoleId: preview?.spaceId == space.id ? preview?.roleId : null,
  );
  final canInvite = accordHasPermission(perms, AccordPermission.createInvites);
  final canManage =
      accordHasPermission(perms, AccordPermission.manageSpace) ||
      accordHasPermission(perms, AccordPermission.manageRoles) ||
      accordHasPermission(perms, AccordPermission.viewAuditLog);
  final isOwner = userId != null && space.ownerId == userId;
  final settingsCtl = ref.read(settingsControllerProvider.notifier);
  final muted = ref.read(settingsControllerProvider).isSpaceMuted(space.id);
  return [
    AccordMenuEntry(
      label: muted ? 'Unmute server' : 'Mute server',
      icon: muted
          ? Icons.notifications_active_outlined
          : Icons.notifications_off_outlined,
      subtitle: muted ? null : 'Silence notifications from this server',
      onSelected: () => settingsCtl.toggleSpaceMuted(space.id),
    ),
    if (canInvite)
      AccordMenuEntry(
        label: 'Copy server link',
        icon: Icons.link_outlined,
        onSelected: () => _copyServerLink(context, ref, space, serverKey),
      ),
    if (canInvite)
      AccordMenuEntry(
        label: 'Invite people',
        icon: Icons.person_add_outlined,
        onSelected: () => showAccordInvites(context, spaceId: space.id),
      ),
    if (canManage)
      AccordMenuEntry(
        label: 'Space settings',
        icon: Icons.settings_outlined,
        onSelected: () => showAccordSpaceSettings(context, spaceId: space.id),
      ),
    AccordMenuEntry(
      label: 'Hide from list',
      icon: Icons.visibility_off_outlined,
      subtitle: 'Remove from your rail without leaving',
      onSelected: () => settingsCtl.setSpaceHidden(space.id, true),
    ),
    AccordMenuEntry(
      label: 'Leave server',
      icon: Icons.logout,
      destructive: !isOwner,
      enabled: !isOwner,
      subtitle: isOwner ? 'Transfer ownership before leaving.' : null,
      onSelected: isOwner ? null : () => _leaveSpace(context, ref, space, serverKey),
    ),
    AccordMenuEntry(
      label: 'Leave & delete data',
      icon: Icons.delete_forever_outlined,
      destructive: !isOwner,
      enabled: !isOwner,
      subtitle:
          isOwner ? null : 'Permanently delete your messages & data here',
      onSelected:
          isOwner ? null : () => _leaveAndDeleteSpace(context, ref, space, serverKey),
    ),
    const AccordMenuEntry.divider(),
  ];
}

/// Copies a shareable invite link for [space] to the clipboard, reusing an
/// existing invite when one exists or minting a default 7-day one otherwise.
/// Gated on `createInvites` by the caller. The quick equivalent of opening the
/// full invite dialog just to copy a link.
Future<void> _copyServerLink(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey,
) async {
  final conn = ref.read(connectionsControllerProvider).connectionFor(serverKey);
  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  final baseUrl = conn?.session.server.baseUrl;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (client == null) return;

  String? code;
  final existing = await client.invites.listSpace(space.id);
  final existingData = existing.data;
  if (existing.ok && existingData is List) {
    final invites = existingData.whereType<AccordInvite>().toList();
    if (invites.isNotEmpty) code = invites.first.code;
  }
  if (code == null) {
    final created = await client.invites.createSpace(
      space.id,
      data: {'max_age': 604800, 'max_uses': 0, 'temporary': false},
    );
    final createdData = created.data;
    if (created.ok && createdData is AccordInvite) {
      code = createdData.code;
    } else if (created.ok) {
      // Some servers return no body on create; refetch to recover the code.
      final refetch = await client.invites.listSpace(space.id);
      final refetchData = refetch.data;
      if (refetch.ok && refetchData is List) {
        final invites = refetchData.whereType<AccordInvite>().toList();
        if (invites.isNotEmpty) code = invites.first.code;
      }
    }
  }
  if (code == null) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not create an invite link')),
    );
    return;
  }
  final link = baseUrl == null ? code : '$baseUrl/invite/$code';
  await Clipboard.setData(ClipboardData(text: link));
  messenger?.showSnackBar(
    const SnackBar(content: Text('Server link copied')),
  );
}

/// Confirms then leaves [space] *and deletes all the user's data* on its own
/// connection (`deleteData: true`). The destructive sibling of [_leaveSpace],
/// surfaced from the space menu as well as Privacy & Data. Owner-guarded by the
/// caller (the tile is disabled for owners).
Future<void> _leaveAndDeleteSpace(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Leave & delete data'),
      content: Text(
        "This will permanently leave '${space.name}' and delete all your "
        'messages, reactions, and data from this server. Your account stays '
        'active. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Leave & delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  if (client == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await client.members.leaveMe(space.id, deleteData: true);
  if (!result.ok) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Failed to leave: ${result.error ?? 'unknown error'}'),
      ),
    );
    return;
  }
  ref
      .read(connectionsControllerProvider.notifier)
      .removeSpace(serverKey, space.id);
  ref.read(spacesControllerProvider.notifier).removeSpace(space.id);
  messenger?.showSnackBar(
    SnackBar(content: Text("Left '${space.name}' and deleted your data")),
  );
}

/// Confirms then leaves [space] on its own connection, without deleting any
/// data (the destructive leave-and-delete lives in Privacy & Data). Drops the
/// space from both the connection cache and the active list on success.
Future<void> _leaveSpace(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("Leave '${space.name}'?"),
      content: const Text(
        'You will lose access to this server until you rejoin with an '
        'invite. Your messages stay on the server.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  if (client == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await client.members.leaveMe(space.id);
  if (!result.ok) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Failed to leave: ${result.error ?? 'unknown error'}'),
      ),
    );
    return;
  }
  ref
      .read(connectionsControllerProvider.notifier)
      .removeSpace(serverKey, space.id);
  ref.read(spacesControllerProvider.notifier).removeSpace(space.id);
  messenger?.showSnackBar(SnackBar(content: Text("Left '${space.name}'")));
}

/// A space icon that can be dragged (to reorder / into folders) and accepts a
/// dropped space to reorder before itself.
class _DraggableSpace extends StatefulWidget {
  const _DraggableSpace({
    required this.space,
    required this.cdnUrl,
    required this.selected,
    required this.onTap,
    required this.onReorderBefore,
    required this.onMenu,
    this.serverKey = '',
  });

  final AccordSpace space;
  final String? cdnUrl;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<String> onReorderBefore;
  final void Function(Offset position) onMenu;
  final String serverKey;

  @override
  State<_DraggableSpace> createState() => _DraggableSpaceState();
}

class _DraggableSpaceState extends State<_DraggableSpace> {
  // Captured on the down event so the double-tap menu can anchor where the
  // user clicked (onDoubleTap itself carries no position).
  Offset _lastTap = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final icon = _SpaceIcon(
      space: widget.space,
      selected: widget.selected,
      cdnUrl: widget.cdnUrl,
      serverKey: widget.serverKey,
      onTap: widget.onTap,
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != widget.space.id,
      onAcceptWithDetails: (d) => widget.onReorderBefore(d.data),
      builder: (context, candidate, _) => Opacity(
        opacity: candidate.isNotEmpty ? 0.5 : 1,
        child: LongPressDraggable<String>(
          data: widget.space.id,
          feedback: Material(
            color: Colors.transparent,
            child: _SpaceIcon(
              space: widget.space,
              selected: false,
              cdnUrl: widget.cdnUrl,
              serverKey: widget.serverKey,
              onTap: () {},
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: icon),
          // Long-press drives the drag (reorder / into-folder); the rail
          // management menu (new folder, move/remove) opens on double-tap or
          // right-click so it stays reachable on every platform.
          child: GestureDetector(
            onDoubleTapDown: (d) => _lastTap = d.globalPosition,
            onDoubleTap: () => widget.onMenu(_lastTap),
            onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
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
    required this.connOf,
    required this.selectedSpaceId,
    required this.onSelect,
    required this.onDropSpace,
  });

  final SpaceFolder folder;
  final List<AccordSpace> spaces;

  /// Per-space connection lookup so folder members can span servers: each
  /// member resolves its own CDN, owning server, and active state.
  final Map<String, _SpaceConn> connOf;
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
                onLongPressStart: (d) =>
                    _folderMenu(context, ref, d.globalPosition),
                onSecondaryTapUp: (d) =>
                    _folderMenu(context, ref, d.globalPosition),
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
                    onLongPressStart: (d) =>
                        _memberMenu(context, ref, ctl, space, d.globalPosition),
                    onSecondaryTapUp: (d) =>
                        _memberMenu(context, ref, ctl, space, d.globalPosition),
                    child: _SpaceIcon(
                      space: space,
                      selected: (connOf[space.id]?.active ?? false) &&
                          space.id == selectedSpaceId,
                      cdnUrl: connOf[space.id]?.cdnUrl,
                      serverKey: connOf[space.id]?.serverKey ?? '',
                      onTap: () =>
                          onSelect(connOf[space.id]?.serverKey ?? '', space.id),
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
    WidgetRef ref,
    SettingsController ctl,
    AccordSpace space,
    Offset position,
  ) {
    final entries = <AccordMenuEntry>[
      ..._serverActionEntries(
        context,
        ref,
        space,
        connOf[space.id]?.serverKey ?? '',
      ),
      AccordMenuEntry(
        label: 'Remove "${space.name}" from folder',
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

  Future<void> _folderMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) {
    final ctl = ref.read(settingsControllerProvider.notifier);
    final entries = <AccordMenuEntry>[
      AccordMenuEntry(
        label: folder.collapsed ? 'Expand' : 'Collapse',
        icon: folder.collapsed ? Icons.unfold_more : Icons.unfold_less,
        onSelected: () =>
            ctl.setFolderCollapsed(folder.id, !folder.collapsed),
      ),
      AccordMenuEntry(
        label: 'Rename',
        icon: Icons.edit_outlined,
        onSelected: () async {
          final name = await _promptName(context, folder.name);
          if (name != null) ctl.renameFolder(folder.id, name);
        },
      ),
      AccordMenuEntry(
        label: 'Recolor',
        icon: Icons.palette_outlined,
        onSelected: () async {
          final color = await _pickColor(context);
          if (color != null) {
            ctl.setFolderColor(folder.id, color == 0 ? null : color);
          }
        },
      ),
      AccordMenuEntry(
        label: 'Delete folder',
        icon: Icons.folder_delete_outlined,
        destructive: true,
        onSelected: () => ctl.deleteFolder(folder.id),
      ),
    ];
    return showAccordContextMenu(
      context,
      entries: entries,
      globalPosition: position,
      title: folder.name.isEmpty ? 'Folder' : folder.name,
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
    this.serverKey = '',
  });

  final AccordSpace space;
  final bool selected;
  final String? cdnUrl;
  final VoidCallback onTap;

  /// The connection that owns this space, so the unread badge reads that
  /// server's read state (snowflakes collide across servers).
  final String serverKey;

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
    // Roll up this server's per-channel read state into a single rail-level
    // indicator. Keyed by [serverKey] so each server's badge reflects its own
    // unread; driven by the READY-hydrated + live read state (no channel fetch
    // needed, so background servers light up without opening them).
    final readState = ref.watch(readStateControllerProvider(serverKey));
    final hasUnread = !selected && readState.anyUnreadInSpace(space.id);
    final mentions = readState.mentionsInSpace(space.id);
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

/// A small affordance at the foot of the rail showing how many servers are
/// hidden; tapping it opens the restore sheet.
class _HiddenServersButton extends StatelessWidget {
  const _HiddenServersButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Tooltip(
        message: '$count hidden ${count == 1 ? 'server' : 'servers'}',
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
            child: Icon(
              Icons.visibility_off_outlined,
              size: 20,
              color: colors.dirtyWhite,
            ),
          ),
        ),
      ),
    );
  }
}
