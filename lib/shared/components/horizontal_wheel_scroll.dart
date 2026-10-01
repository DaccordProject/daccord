import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Makes a horizontal scrollable respond to a plain mouse wheel on desktop.
///
/// A horizontal list only reads `scrollDelta.dx`, which a standard wheel never
/// sets, so the vertical delta is applied here instead. Events the framework
/// already handles (real `dx` from trackpads, Shift-flipped axes) are left
/// alone. [builder] must attach the supplied controller to a horizontal
/// scrollable; pass [controller] when the caller owns one.
class HorizontalWheelScroll extends StatefulWidget {
  const HorizontalWheelScroll({
    super.key,
    this.controller,
    required this.builder,
  });

  final ScrollController? controller;
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
    if (event.scrollDelta.dx != 0) return;
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
