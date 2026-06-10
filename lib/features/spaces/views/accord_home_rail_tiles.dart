part of 'accord_home.dart';

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
