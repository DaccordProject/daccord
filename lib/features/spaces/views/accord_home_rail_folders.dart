part of 'accord_home.dart';

/// A collapsible folder tile in the rail. Tap toggles collapse; the management
/// menu opens on long-press (touch) or right-click (desktop); dragging reorders
/// the folder. It accepts dropped spaces (to add them) and dropped folders (to
/// reorder before it).
class _FolderTile extends ConsumerStatefulWidget {
  const _FolderTile({
    required this.folder,
    required this.spaces,
    required this.connOf,
    required this.selectedSpaceId,
    required this.onSelect,
    required this.onDropSpace,
    required this.onReorderFolderBefore,
    required this.onMemberDropBefore,
  });

  final SpaceFolder folder;
  final List<_RailSpace> spaces;

  /// Per-space connection lookup so folder members can span servers: each
  /// member resolves its own CDN, owning server, and active state.
  final Map<String, _SpaceConn> connOf;
  final String? selectedSpaceId;
  final void Function(String serverKey, String spaceId) onSelect;

  /// A space [spaceId] was dropped on the folder tile: add it to this folder.
  final ValueChanged<String> onDropSpace;

  /// A folder [folderId] was dropped on this folder tile: move that folder
  /// before this one.
  final ValueChanged<String> onReorderFolderBefore;

  /// A space [draggedSpaceId] was dropped on member [targetMemberId]: place it
  /// in this folder before that member (reorder within, or move in positioned).
  final void Function(String draggedSpaceId, String targetMemberId)
  onMemberDropBefore;

  @override
  ConsumerState<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends ConsumerState<_FolderTile> {
  SpaceFolder get folder => widget.folder;
  List<_RailSpace> get spaces => widget.spaces;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final ctl = ref.read(settingsControllerProvider.notifier);
    final folderColor = folder.color != null
        ? Color(folder.color!)
        : colors.darkGray;

    final folderIcon = Tooltip(
      message: folder.name.isEmpty ? 'Folder' : folder.name,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: folderColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Icon(
          folder.collapsed ? Icons.folder : Icons.folder_open,
          color: colors.dirtyWhite,
        ),
      ),
    );

    return Column(
      children: [
        Center(
          child: DragTarget<_RailDrag>(
            onWillAcceptWithDetails: (d) => switch (d.data) {
              _SpaceDrag(:final spaceId) => !folder.spaceIds.contains(spaceId),
              _FolderDrag(:final folderId) => folderId != folder.id,
            },
            onAcceptWithDetails: (d) {
              switch (d.data) {
                case _SpaceDrag(:final spaceId):
                  widget.onDropSpace(spaceId);
                case _FolderDrag(:final folderId):
                  widget.onReorderFolderBefore(folderId);
              }
            },
            builder: (context, candidate, _) {
              final highlight = candidate.isNotEmpty;
              return _RailDraggable(
                data: _FolderDrag(folder.id),
                feedback: Material(
                  color: Colors.transparent,
                  child: folderIcon,
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: folderIcon),
                onPressMenu: (pos) => _folderMenu(context, ref, pos),
                child: GestureDetector(
                  onTap: () =>
                      ctl.setFolderCollapsed(folder.id, !folder.collapsed),
                  onSecondaryTapUp: (d) =>
                      _folderMenu(context, ref, d.globalPosition),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: highlight
                          ? Border.all(color: colors.primary, width: 2)
                          : null,
                    ),
                    child: folderIcon,
                  ),
                ),
              );
            },
          ),
        ),
        if (!folder.collapsed)
          for (final railSpace in spaces)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _FolderMemberTile(
                space: railSpace.space,
                entityKey: railSpace.key,
                conn: widget.connOf[railSpace.key],
                selected:
                    (widget.connOf[railSpace.key]?.active ?? false) &&
                    railSpace.space.id == widget.selectedSpaceId,
                onTap: () => widget.onSelect(
                  widget.connOf[railSpace.key]?.serverKey ?? '',
                  railSpace.space.id,
                ),
                onDropBefore: (draggedId) =>
                    widget.onMemberDropBefore(draggedId, railSpace.key),
                onMenu: (pos) => _memberMenu(context, ref, ctl, railSpace, pos),
              ),
            ),
      ],
    );
  }

  Future<void> _memberMenu(
    BuildContext context,
    WidgetRef ref,
    SettingsController ctl,
    _RailSpace railSpace,
    Offset position,
  ) {
    final space = railSpace.space;
    final entries = <AccordMenuEntry>[
      ..._serverActionEntries(
        context,
        ref,
        space,
        widget.connOf[railSpace.key]?.serverKey ?? '',
      ),
      AccordMenuEntry(
        label: 'Remove "${space.name}" from folder',
        icon: Icons.folder_off_outlined,
        onSelected: () => ctl.moveSpaceToFolder(
          ServerEntityKey.tryDecode(railSpace.key)!,
          null,
        ),
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
        onSelected: () => ctl.setFolderCollapsed(folder.id, !folder.collapsed),
      ),
      AccordMenuEntry(
        label: 'Rename',
        icon: Icons.edit_outlined,
        onSelected: () async {
          final name = await showTextPromptDialog(
            context,
            title: 'Folder name',
            initial: folder.name,
          );
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
              ColorSwatchChip(
                color: argb == 0 ? Colors.grey : Color(argb),
                selected: false,
                onTap: () => Navigator.of(ctx).pop(argb),
                icon: argb == 0 ? Icons.clear : null,
                iconSize: 16,
                iconColor: Colors.white,
              ),
          ],
        ),
      ),
    );
  }
}

/// A space icon shown inside an expanded folder. Like [_DraggableSpace] but its
/// drops are scoped to the folder: dragging it out onto a rail space pulls it
/// from the folder, and a space dropped on it lands before it within the folder.
class _FolderMemberTile extends StatelessWidget {
  const _FolderMemberTile({
    required this.space,
    required this.entityKey,
    required this.conn,
    required this.selected,
    required this.onTap,
    required this.onDropBefore,
    required this.onMenu,
  });

  final AccordSpace space;
  final String entityKey;
  final _SpaceConn? conn;
  final bool selected;
  final VoidCallback onTap;

  /// A space [draggedSpaceId] was dropped on this member: place it before this
  /// member within the folder.
  final ValueChanged<String> onDropBefore;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context) {
    final icon = _SpaceIcon(
      space: space,
      selected: selected,
      cdnUrl: conn?.cdnUrl,
      serverKey: conn?.serverKey ?? '',
      onTap: onTap,
    );
    return DragTarget<_RailDrag>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        _SpaceDrag(:final spaceId) => spaceId != entityKey,
        _FolderDrag() => false,
      },
      onAcceptWithDetails: (d) {
        if (d.data case _SpaceDrag(:final spaceId)) {
          onDropBefore(spaceId);
        }
      },
      builder: (context, candidate, _) => Opacity(
        opacity: candidate.isNotEmpty ? 0.5 : 1,
        child: _RailDraggable(
          data: _SpaceDrag(entityKey),
          feedback: Material(
            color: Colors.transparent,
            child: _SpaceIcon(
              space: space,
              selected: false,
              cdnUrl: conn?.cdnUrl,
              serverKey: conn?.serverKey ?? '',
              onTap: () {},
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: icon),
          onPressMenu: onMenu,
          child: GestureDetector(
            onSecondaryTapUp: (d) => onMenu(d.globalPosition),
            child: icon,
          ),
        ),
      ),
    );
  }
}
