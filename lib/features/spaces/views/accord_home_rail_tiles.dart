part of 'accord_home.dart';

/// Payload carried while dragging a rail item, so a drop target can tell a
/// space drag (reorder / move between folders) from a folder drag (reorder the
/// whole folder) without overloading a bare id string.
sealed class _RailDrag {
  const _RailDrag();
}

class _SpaceDrag extends _RailDrag {
  const _SpaceDrag(this.spaceId);
  final String spaceId;
}

class _FolderDrag extends _RailDrag {
  const _FolderDrag(this.folderId);
  final String folderId;
}

/// Desktop pointers have no "long press" affordance and scroll via the wheel,
/// so a drag should start immediately on click-drag. Touch platforms keep the
/// long-press gesture so dragging doesn't fight finger-scrolling.
bool get _immediateDrag => switch (defaultTargetPlatform) {
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => true,
  _ => false,
};

/// The platform-appropriate draggable for a rail item: an immediate [Draggable]
/// on desktop (click-drag), a [LongPressDraggable] on touch (press-and-hold to
/// lift, with haptic, so dragging doesn't fight finger-scrolling).
///
/// On touch a long-press that is *released in place* (no drag) is treated as a
/// context-menu request via [onPressMenu] — that's the menu's discoverable home
/// there, since touch has no right-click and long-press is the platform's
/// universal "show actions" gesture. Desktop opens the same menu on right-click
/// instead (handled by the child), so [onPressMenu] never fires there.
class _RailDraggable extends StatefulWidget {
  const _RailDraggable({
    required this.data,
    required this.feedback,
    required this.childWhenDragging,
    required this.child,
    this.onPressMenu,
  });

  final _RailDrag data;
  final Widget feedback;
  final Widget childWhenDragging;
  final Widget child;

  /// Touch only: the user long-pressed and released without dragging at this
  /// global position — open the item's management menu there.
  final ValueChanged<Offset>? onPressMenu;

  @override
  State<_RailDraggable> createState() => _RailDraggableState();
}

class _RailDraggableState extends State<_RailDraggable> {
  // Captured on pointer-down so a release-in-place can anchor the menu where the
  // finger landed (the drag callbacks don't carry the press origin).
  Offset _downPos = Offset.zero;
  bool _moved = false;

  @override
  Widget build(BuildContext context) {
    if (_immediateDrag) {
      return Draggable<_RailDrag>(
        data: widget.data,
        feedback: widget.feedback,
        childWhenDragging: widget.childWhenDragging,
        child: widget.child,
      );
    }
    return Listener(
      onPointerDown: (e) => _downPos = e.position,
      child: LongPressDraggable<_RailDrag>(
        data: widget.data,
        feedback: widget.feedback,
        childWhenDragging: widget.childWhenDragging,
        onDragStarted: () => _moved = false,
        onDragUpdate: (d) {
          if (!_moved && (d.globalPosition - _downPos).distance > 24) {
            _moved = true;
          }
        },
        onDragEnd: (d) {
          if (!_moved && !d.wasAccepted) widget.onPressMenu?.call(_downPos);
        },
        child: widget.child,
      ),
    );
  }
}

/// A drop zone occupying the track between two rail items, so a space or folder
/// can be inserted *at* that position (e.g. between a space and a folder)
/// instead of only onto an icon. Grows and shows an insertion bar while a
/// compatible drag hovers it.
class _InsertionGap extends StatelessWidget {
  const _InsertionGap({
    required this.onDropSpace,
    required this.onDropFolder,
  });

  /// A space [spaceId] was dropped in this gap: place it here as a standalone
  /// rail entry (pulled out of any folder it was in).
  final ValueChanged<String> onDropSpace;

  /// A folder [folderId] was dropped in this gap: move the whole folder here.
  final ValueChanged<String> onDropFolder;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return DragTarget<_RailDrag>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        switch (d.data) {
          case _SpaceDrag(:final spaceId):
            onDropSpace(spaceId);
          case _FolderDrag(:final folderId):
            onDropFolder(folderId);
        }
      },
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: active ? 24 : 12,
          alignment: Alignment.center,
          child: active
              ? Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : null,
        );
      },
    );
  }
}

/// A space icon that can be dragged to reorder (drop in the gaps between tiles)
/// or to group: dropping another space *onto* it merges the two into a new
/// folder (Discord-style), and dropping a folder onto it reorders that folder
/// before this space.
class _DraggableSpace extends StatelessWidget {
  const _DraggableSpace({
    required this.space,
    required this.cdnUrl,
    required this.selected,
    required this.onTap,
    required this.onMergeSpace,
    required this.onDropFolderBefore,
    required this.onMenu,
    this.serverKey = '',
  });

  final AccordSpace space;
  final String? cdnUrl;
  final bool selected;
  final VoidCallback onTap;

  /// A space [spaceId] was dropped *onto* this tile: group the two into a new
  /// folder (drop between tiles to reorder instead).
  final ValueChanged<String> onMergeSpace;

  /// A folder [folderId] was dropped on this tile: move the whole folder before
  /// this space.
  final ValueChanged<String> onDropFolderBefore;
  final void Function(Offset position) onMenu;
  final String serverKey;

  @override
  Widget build(BuildContext context) {
    final icon = _SpaceIcon(
      space: space,
      selected: selected,
      cdnUrl: cdnUrl,
      serverKey: serverKey,
      onTap: onTap,
    );
    return DragTarget<_RailDrag>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        _SpaceDrag(:final spaceId) => spaceId != space.id,
        _FolderDrag() => true,
      },
      onAcceptWithDetails: (d) {
        switch (d.data) {
          case _SpaceDrag(:final spaceId):
            onMergeSpace(spaceId);
          case _FolderDrag(:final folderId):
            onDropFolderBefore(folderId);
        }
      },
      builder: (context, candidate, _) => Opacity(
        opacity: candidate.isNotEmpty ? 0.5 : 1,
        child: _RailDraggable(
          data: _SpaceDrag(space.id),
          feedback: Material(
            color: Colors.transparent,
            child: _SpaceIcon(
              space: space,
              selected: false,
              cdnUrl: cdnUrl,
              serverKey: serverKey,
              onTap: () {},
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: icon),
          // Drag drives reorder / grouping; the management menu (new folder,
          // move/remove, leave) opens via long-press on touch and right-click on
          // desktop so it stays reachable everywhere.
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
  final List<AccordSpace> spaces;

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
  List<AccordSpace> get spaces => widget.spaces;

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
                feedback: Material(color: Colors.transparent, child: folderIcon),
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
          for (final space in spaces)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _FolderMemberTile(
                space: space,
                conn: widget.connOf[space.id],
                selected: (widget.connOf[space.id]?.active ?? false) &&
                    space.id == widget.selectedSpaceId,
                onTap: () =>
                    widget.onSelect(widget.connOf[space.id]?.serverKey ?? '', space.id),
                onDropBefore: (draggedId) =>
                    widget.onMemberDropBefore(draggedId, space.id),
                onMenu: (pos) => _memberMenu(context, ref, ctl, space, pos),
              ),
            ),
      ],
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
        widget.connOf[space.id]?.serverKey ?? '',
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
    ).whenComplete(controller.dispose);
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

/// A space icon shown inside an expanded folder. Like [_DraggableSpace] but its
/// drops are scoped to the folder: dragging it out onto a rail space pulls it
/// from the folder, and a space dropped on it lands before it within the folder.
class _FolderMemberTile extends StatelessWidget {
  const _FolderMemberTile({
    required this.space,
    required this.conn,
    required this.selected,
    required this.onTap,
    required this.onDropBefore,
    required this.onMenu,
  });

  final AccordSpace space;
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
        _SpaceDrag(:final spaceId) => spaceId != space.id,
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
          data: _SpaceDrag(space.id),
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

/// The Direct Messages affordance pinned at the top of the rail, styled as a
/// space-icon tile (Discord-style "home" button) rather than a small footer
/// icon. Opens the DM/friends modal.
class _DirectMessagesButton extends StatelessWidget {
  const _DirectMessagesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Tooltip(
        message: 'Direct messages',
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
              Icons.chat_bubble_outline,
              size: 22,
              color: colors.dirtyWhite,
            ),
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
