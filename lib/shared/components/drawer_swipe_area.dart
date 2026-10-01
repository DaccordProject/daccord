import 'package:flutter/material.dart';

/// Minimum horizontal travel, in logical pixels, before a body swipe counts as
/// a drawer gesture. Measured *after* the gesture recognizer's own touch slop,
/// so the finger has really committed to a direction.
const double kDrawerSwipeDistance = 40;

/// Minimum horizontal fling speed, in logical pixels/second, that opens a
/// drawer no matter how short the flick was.
const double kDrawerSwipeVelocity = 320;

/// What a finished body swipe should do.
enum DrawerSwipeAction { none, openDrawer, openEndDrawer }

/// Resolves a completed horizontal body swipe into a drawer action.
///
/// [distance] and [velocity] are measured towards the [Scaffold.drawer] edge —
/// positive is "towards the drawer" (rightwards in LTR). A decisive fling wins
/// over the accumulated distance, so a drag that wanders one way and flicks
/// back the other opens what the flick pointed at.
DrawerSwipeAction drawerSwipeAction({
  required double distance,
  required double velocity,
}) {
  if (velocity.abs() >= kDrawerSwipeVelocity) {
    return velocity > 0
        ? DrawerSwipeAction.openDrawer
        : DrawerSwipeAction.openEndDrawer;
  }
  if (distance >= kDrawerSwipeDistance) return DrawerSwipeAction.openDrawer;
  if (distance <= -kDrawerSwipeDistance) return DrawerSwipeAction.openEndDrawer;
  return DrawerSwipeAction.none;
}

/// Opens a [Scaffold]'s drawers from a horizontal swipe started *anywhere* over
/// [child], not just in the narrow edge strip Flutter listens on by default.
///
/// Widening the framework's edge strip instead would not work: it is hit-tested
/// before the body, so it would steal drags from every horizontal scrollable
/// (tab strip, voice rails). Sitting inside the body lets content recognizers
/// claim their drags first. The edge strip stays because it drags the drawer
/// under the finger, which this widget can't (`ScaffoldState` only snaps).
class DrawerSwipeArea extends StatefulWidget {
  const DrawerSwipeArea({
    super.key,
    required this.scaffoldKey,
    required this.child,
  });

  /// Key of the [Scaffold] whose drawers this swipe opens.
  final GlobalKey<ScaffoldState> scaffoldKey;

  final Widget child;

  @override
  State<DrawerSwipeArea> createState() => _DrawerSwipeAreaState();
}

class _DrawerSwipeAreaState extends State<DrawerSwipeArea> {
  /// Horizontal travel accumulated since the current drag was recognized.
  double _distance = 0;

  /// Mirrors `DrawerController`'s own check: swipe-to-open is a touch idiom,
  /// and a mouse drag across a desktop window shouldn't fling a panel open.
  bool get _swipeEnabled => switch (Theme.of(context).platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => true,
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.windows => false,
  };

  /// Sign that maps raw dx onto "towards the drawer": the drawer hangs off the
  /// start edge, which is the right in RTL.
  double get _towardsDrawer =>
      Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  void _onEnd(DragEndDetails details) {
    final scaffold = widget.scaffoldKey.currentState;
    // An open drawer covers the screen with its own drag target, so this only
    // fires while both are shut — but a stale key or a mid-animation drag
    // shouldn't reopen anything.
    if (scaffold == null || scaffold.isDrawerOpen || scaffold.isEndDrawerOpen) {
      return;
    }
    final action = drawerSwipeAction(
      distance: _distance * _towardsDrawer,
      velocity: details.velocity.pixelsPerSecond.dx * _towardsDrawer,
    );
    switch (action) {
      case DrawerSwipeAction.openDrawer:
        if (scaffold.hasDrawer) scaffold.openDrawer();
      case DrawerSwipeAction.openEndDrawer:
        if (scaffold.hasEndDrawer) scaffold.openEndDrawer();
      case DrawerSwipeAction.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_swipeEnabled) return widget.child;
    return GestureDetector(
      // Opaque so the gaps between the content's own widgets swipe too;
      // children are still hit-tested first, so they keep winning the arena.
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onHorizontalDragStart: (_) => _distance = 0,
      onHorizontalDragUpdate: (details) => _distance += details.delta.dx,
      onHorizontalDragEnd: _onEnd,
      child: widget.child,
    );
  }
}
