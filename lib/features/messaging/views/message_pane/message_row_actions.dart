part of 'message_pane.dart';

/// Floats [actions] over the top-right corner of [child], or renders [child]
/// untouched when there are none. Used by narrow rows (the voice channel's chat
/// panel), where an inline action bar would take most of the row's width; the
/// bar is only passed in while the row is hovered, so nothing overlaps the
/// message the rest of the time.
class _FloatingActionsOverlay extends StatelessWidget {
  const _FloatingActionsOverlay({required this.actions, required this.child});

  final Widget? actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final actions = this.actions;
    if (actions == null) return child;
    final colors = BonfireThemeExtension.of(context);
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          right: 4,
          child: Material(
            color: colors.foreground,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: actions,
          ),
        ),
      ],
    );
  }
}

/// Wraps [child] in a click-to-open gesture (with a pointer cursor) when
/// [enabled]; otherwise renders the child untouched. Used so message authors are
/// only tappable inside a space (where a profile popout makes sense).
class _MaybeTappable extends StatelessWidget {
  const _MaybeTappable({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}

/// The hover-only timestamp shown in the avatar gutter of a grouped row (which
/// has no author header of its own). Bare HH:MM in a fixed-width slot, with the
/// full date in a tooltip.
class _GutterTimestamp extends StatelessWidget {
  const _GutterTimestamp({
    required this.width,
    required this.visible,
    required this.clock,
    required this.fullTime,
  });

  final double width;
  final bool visible;
  final String clock;
  final String fullTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      width: width,
      child: Opacity(
        opacity: visible ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Tooltip(
            message: fullTime,
            child: Text(
              clock,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall!.copyWith(color: colors.gray),
            ),
          ),
        ),
      ),
    );
  }
}

/// The desktop hover-action cluster at a row's trailing edge: react, reply,
/// thread, and (when any moderation/authorship applies) the overflow
/// [_MessageActions] menu. Revealed by hover via [visible]; the row omits it
/// entirely on touch layouts.
class _HoverActions extends StatelessWidget {
  const _HoverActions({
    required this.visible,
    required this.onReact,
    required this.onReply,
    required this.onThread,
    required this.canEdit,
    required this.canDelete,
    required this.canPin,
    required this.canReport,
    required this.pinned,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
    required this.onReport,
    required this.onMenuStateChanged,
  });

  final bool visible;
  final VoidCallback onReact;
  final VoidCallback onReply;
  final VoidCallback onThread;
  final bool canEdit;
  final bool canDelete;
  final bool canPin;
  final bool canReport;
  final bool pinned;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onReport;

  /// Notified when the "⋯" menu opens and closes, so a floated bar can stay
  /// mounted for the menu's lifetime.
  final ValueChanged<bool> onMenuStateChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Opacity(
      opacity: visible ? 1 : 0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReactButton(onPressed: onReact),
          IconButton(
            tooltip: 'Reply',
            onPressed: onReply,
            icon: Icon(Icons.reply, size: 18, color: colors.gray),
          ),
          IconButton(
            tooltip: 'Thread',
            onPressed: onThread,
            icon: Icon(Icons.forum_outlined, size: 18, color: colors.gray),
          ),
          // canEdit implies canDelete, so this matches the original
          // isOwn || canManageMessages || canReport gate.
          if (canDelete || canReport)
            _MessageActions(
              canEdit: canEdit,
              canDelete: canDelete,
              canPin: canPin,
              canReport: canReport,
              pinned: pinned,
              onEdit: onEdit,
              onDelete: onDelete,
              onTogglePin: onTogglePin,
              onReport: onReport,
              onMenuStateChanged: onMenuStateChanged,
            ),
        ],
      ),
    );
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.canEdit,
    required this.canDelete,
    required this.canPin,
    required this.canReport,
    required this.pinned,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
    required this.onReport,
    required this.onMenuStateChanged,
  });

  final bool canEdit;
  final bool canDelete;
  final bool canPin;
  final bool canReport;
  final bool pinned;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onReport;

  /// See [_HoverActions.onMenuStateChanged].
  final ValueChanged<bool> onMenuStateChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Message actions',
      icon: Icon(Icons.more_horiz, size: 18, color: colors.gray),
      // `onOpened` fires before the menu's barrier steals the hover, which is
      // what keeps this button mounted long enough for `onSelected` to run.
      onOpened: () => onMenuStateChanged(true),
      onCanceled: () => onMenuStateChanged(false),
      onSelected: (value) {
        onMenuStateChanged(false);
        switch (value) {
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
          case 'pin':
            onTogglePin();
          case 'report':
            onReport();
        }
      },
      itemBuilder: (context) => [
        if (canPin)
          PopupMenuItem(value: 'pin', child: Text(pinned ? 'Unpin' : 'Pin')),
        if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (canDelete)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        if (canReport)
          const PopupMenuItem(value: 'report', child: Text('Report')),
      ],
    );
  }
}
