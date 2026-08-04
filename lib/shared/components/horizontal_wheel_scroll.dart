import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Makes a horizontal scrollable respond to a plain mouse wheel on desktop.
///
/// Flutter picks the delta component that matches the scrollable's axis
/// (`Scrollable._pointerSignalEventDelta`), so a horizontal list reads
/// `scrollDelta.dx` — which a standard wheel never sets. The event is then
/// dropped and the list sits still. This wrapper listens for the same pointer
/// signal and pushes the vertical delta onto a horizontal [ScrollController]
/// itself.
///
/// Deliberately narrow so the framework keeps ownership of everything it
/// already handles:
///
/// * events carrying a real `dx` (trackpad two-finger panning) are ignored, so
///   they aren't applied twice;
/// * events with a `pointerAxisModifiers` key held (Shift by default) are
///   ignored, because [ScrollBehavior] already flips the axis for those;
/// * macOS trackpad `PointerPanZoom*` events aren't pointer signals at all and
///   never reach this handler.
///
/// Usage — [builder] receives the controller to hand to the scrollable:
///
/// ```dart
/// HorizontalWheelScroll(
///   builder: (context, controller) => ListView(
///     controller: controller,
///     scrollDirection: Axis.horizontal,
///     children: ...,
///   ),
/// )
/// ```
///
/// Pass [controller] when the caller already owns one (and disposes it).
class HorizontalWheelScroll extends StatefulWidget {
  const HorizontalWheelScroll({
    super.key,
    this.controller,
    required this.builder,
  });

  /// An externally owned controller. When null one is created and disposed
  /// here.
  final ScrollController? controller;

  /// Builds the scrollable, which must be attached to the supplied controller
  /// and scroll horizontally.
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<HorizontalWheelScroll> createState() => _HorizontalWheelScrollState();
}

class _HorizontalWheelScrollState extends State<HorizontalWheelScroll> {
  ScrollController? _owned;

  ScrollController get _controller =>
      widget.controller ?? (_owned ??= ScrollController());

  @override
  void didUpdateWidget(HorizontalWheelScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Once the caller supplies its own controller ours is dead weight.
    if (widget.controller != null && _owned != null) {
      _owned!.dispose();
      _owned = null;
    }
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Trackpads deliver real horizontal deltas, which the framework already
    // applies — don't scroll twice.
    if (event.scrollDelta.dx != 0) return;
    // Holding a pointer-axis modifier (Shift by default) makes the framework
    // read dy for a horizontal list, so it has this covered too.
    if (event.kind == PointerDeviceKind.mouse) {
      final modifiers = ScrollConfiguration.of(context).pointerAxisModifiers;
      final pressed = HardwareKeyboard.instance.logicalKeysPressed;
      if (modifiers.any(pressed.contains)) return;
    }
    final controller = widget.controller ?? _owned;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    if (position.axis != Axis.horizontal) return;
    final target = (position.pixels + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: widget.builder(context, _controller),
    );
  }
}
