import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desktop pointers have no "long press" affordance and scroll via the wheel,
/// so a drag should start immediately on click-drag. Touch platforms keep the
/// long-press gesture so dragging doesn't fight finger-scrolling.
bool get railDragsImmediately => switch (defaultTargetPlatform) {
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => true,
  _ => false,
};

/// The platform-appropriate draggable for a space-rail item (a space, a folder
/// member or a folder): an immediate [Draggable] on desktop (click-drag), a
/// [LongPressDraggable] on touch (press-and-hold to lift, with haptic, so
/// dragging doesn't fight finger-scrolling).
///
/// It also owns the item's context-menu triggers and its [tooltip], because
/// the three gestures share one arena and have to be reconciled here:
///
/// * Desktop: right-click opens the menu anchored at the pointer; the tooltip
///   shows on hover as usual.
/// * Touch: a long-press lifts the tile (haptic). Releasing it *in place* —
///   without dragging and without a drop being accepted — opens the menu
///   ([onMenu] with a null position, i.e. the touch-friendly bottom sheet);
///   moving the finger instead reorders as before. Touch has no right-click,
///   and long-press is the platform's universal "show actions" gesture.
///
/// On touch the tooltip's own long-press trigger is disabled
/// ([TooltipTriggerMode.manual]; hover still works with a mouse). Left at the
/// default, [Tooltip] adds a `LongPressGestureRecognizer` with the same
/// timeout as [LongPressDraggable]'s delayed drag recogniser, and being the
/// inner listener its timer fires first and *always* wins the arena — so a
/// long press showed the space's name and the drag (and with it the menu)
/// never started (#327). The name is shown as the sheet's title instead.
class RailDraggable<T extends Object> extends StatefulWidget {
  const RailDraggable({
    super.key,
    required this.data,
    required this.tooltip,
    required this.feedback,
    required this.childWhenDragging,
    required this.child,
    this.onMenu,
  });

  final T data;

  /// The item's name: a hover tooltip on desktop, the menu sheet's title on
  /// touch (via the caller's [onMenu]).
  final String tooltip;
  final Widget feedback;
  final Widget childWhenDragging;
  final Widget child;

  /// Open the item's management menu. [position] is the global right-click
  /// position on desktop (anchor the menu there) and null for a touch
  /// long-press (present it as a bottom sheet).
  final void Function(Offset? position)? onMenu;

  @override
  State<RailDraggable<T>> createState() => _RailDraggableState<T>();
}

class _RailDraggableState<T extends Object> extends State<RailDraggable<T>> {
  // Where the finger landed, and whether it has since travelled far enough to
  // count as a drag rather than a hold. Tracked on the raw pointer stream (the
  // drag callbacks don't carry the press origin) so a release-in-place can be
  // told apart from a reorder that happened to miss every drop target.
  Offset? _downPosition;
  bool _moved = false;

  void _onPointerDown(PointerDownEvent event) {
    _downPosition = event.position;
    _moved = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final down = _downPosition;
    if (_moved || down == null) return;
    if ((event.position - down).distance > kTouchSlop) _moved = true;
  }

  // A system cancel (incoming call, notification shade) ends the drag without
  // a release; that is not a request for the menu.
  void _onPointerCancel(PointerCancelEvent event) => _moved = true;

  void _onDragEnd(DraggableDetails details) {
    if (!_moved && !details.wasAccepted) widget.onMenu?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final onMenu = widget.onMenu;
    final desktop = railDragsImmediately;
    final child = Tooltip(
      message: widget.tooltip,
      triggerMode: desktop ? null : TooltipTriggerMode.manual,
      child: GestureDetector(
        onSecondaryTapUp: onMenu == null
            ? null
            : (d) => onMenu(d.globalPosition),
        child: widget.child,
      ),
    );
    if (desktop) {
      return Draggable<T>(
        data: widget.data,
        feedback: widget.feedback,
        childWhenDragging: widget.childWhenDragging,
        child: child,
      );
    }
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerCancel: _onPointerCancel,
      child: LongPressDraggable<T>(
        data: widget.data,
        feedback: widget.feedback,
        childWhenDragging: widget.childWhenDragging,
        // One clear "lifted" pulse instead of the framework's selection click
        // plus ours.
        hapticFeedbackOnStart: false,
        onDragStarted: HapticFeedback.mediumImpact,
        onDragEnd: _onDragEnd,
        child: child,
      ),
    );
  }
}
