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
        onDragStarted: () {
          _moved = false;
          HapticFeedback.mediumImpact();
        },
        onDragUpdate: (d) {
          if (!_moved && (d.globalPosition - _downPos).distance > 8) {
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
  const _InsertionGap({required this.onDropSpace, required this.onDropFolder});

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
    required this.entityKey,
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
  final String entityKey;

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
        _SpaceDrag(:final spaceId) => spaceId != entityKey,
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
          data: _SpaceDrag(entityKey),
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

  /// Null where the icon is shown for identification only (the hidden-servers
  /// sheet, whose row action is its own "Unhide" button) — a no-op `onTap`
  /// would present the icon as interactive when it isn't (#306).
  final VoidCallback? onTap;

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
    final iconUrl = accordSpaceIconUrl(space, cdnUrl);
    // Roll up this server's per-channel read state into a single rail-level
    // indicator. Keyed by [serverKey] so each server's badge reflects its own
    // unread; driven by the READY-hydrated + live read state (no channel fetch
    // needed, so background servers light up without opening them).
    final readState = ref.watch(readStateControllerProvider(serverKey));
    // …filtered by the user's mute settings, so the rail agrees with the
    // notification gate: a muted space (or a channel set to `nothing`) keeps
    // its truthful read state but stays dark here. Filtering on this side
    // rather than in `markUnread` means unmuting reveals what arrived while
    // muted immediately, with no reconnect. Watch only the two slices that
    // matter so an unrelated settings write (a draft keystroke) can't rebuild
    // every rail icon.
    final spaceMuted = ref.watch(
      settingsControllerProvider.select(
        (s) => s.isSpaceMuted(serverKey, space.id),
      ),
    );
    final channelLevels = ref.watch(
      settingsControllerProvider.select(
        (s) => s.channelNotificationsFor(serverKey),
      ),
    );
    final hasUnread =
        !selected &&
        readState.spaceShowsUnread(
          space.id,
          spaceMuted: spaceMuted,
          channelLevels: channelLevels,
        );
    final mentions = readState.visibleMentionsInSpace(
      space.id,
      spaceMuted: spaceMuted,
      channelLevels: channelLevels,
    );
    // Dim the icon while its server's gateway is down, so an unreachable space
    // reads as offline rather than just unselected.
    final unreachable =
        serverKey.isNotEmpty &&
        (ref
                .watch(
                  connectionsControllerProvider.select(
                    (s) => s.connectionFor(serverKey)?.status,
                  ),
                )
                ?.isUnreachable ??
            false);
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
              Opacity(
                opacity: unreachable ? 0.4 : 1.0,
                child: AnimatedContainer(
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

/// A 48×48 circular utility tile for the rail (Discord-style "home"-row
/// button): a dark round background with a single icon and a tooltip. Backs
/// the DM, add-server and hidden-servers affordances below, which differ only
/// in tooltip, icon, icon size and icon color.
class _RailIconTile extends StatelessWidget {
  const _RailIconTile({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconSize,
    this.iconColor,
    this.hasUnread = false,
    this.mentionCount = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double? iconSize;

  /// Icon tint; defaults to the theme's `dirtyWhite`.
  final Color? iconColor;
  final bool hasUnread;
  final int mentionCount;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.darkGray,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: iconSize,
                  color: iconColor ?? colors.dirtyWhite,
                ),
              ),
              if (mentionCount > 0)
                Positioned(
                  right: -4,
                  top: -2,
                  child: _MentionBadge(count: mentionCount),
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
class _DirectMessagesButton extends ConsumerWidget {
  const _DirectMessagesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(
      connectionsControllerProvider.select((state) => state.connections),
    );
    var hasUnread = false;
    var mentions = 0;
    for (final connection in connections) {
      final snapshot = ref.watch(readStateControllerProvider(connection.key));
      final levels = ref.watch(
        settingsControllerProvider.select(
          (settings) => settings.channelNotificationsFor(connection.key),
        ),
      );
      for (final entry in snapshot.entries.values) {
        if (entry.spaceId != null ||
            !UnreadIndicatorGate.countsTowardSpace(
              spaceMuted: false,
              channelLevel: levels[entry.channelId],
            )) {
          continue;
        }
        hasUnread = true;
        mentions += entry.mentions;
      }
    }
    return _RailIconTile(
      tooltip: 'Direct messages',
      icon: Icons.chat_bubble_outline,
      iconSize: 22,
      hasUnread: hasUnread,
      mentionCount: mentions,
      onTap: onTap,
    );
  }
}

/// The "Add a Server" (+) affordance at the foot of the rail's space list.
class _AddServerButton extends StatelessWidget {
  const _AddServerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _RailIconTile(
    tooltip: 'Add a server',
    icon: Icons.add,
    iconColor: const Color(0xFF43B581),
    onTap: onTap,
  );
}

/// A small affordance at the foot of the rail showing how many servers are
/// hidden; tapping it opens the restore sheet.
class _HiddenServersButton extends StatelessWidget {
  const _HiddenServersButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _RailIconTile(
    tooltip: '$count hidden ${count == 1 ? 'server' : 'servers'}',
    icon: Icons.visibility_off_outlined,
    iconSize: 20,
    onTap: onTap,
  );
}
