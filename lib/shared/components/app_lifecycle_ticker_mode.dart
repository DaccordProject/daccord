import 'package:flutter/widgets.dart';

/// Pauses descendant animations only while the app is not visible.
/// An inactive desktop window is still visible and must keep rendering updates.
///
/// Flutter's [Image] widget responds to [TickerMode] by retaining the currently
/// displayed frame of a multiframe image, unsubscribing from further frames,
/// and resuming the same image stream when tickers are enabled again. Placing
/// this above the app therefore covers GIF avatars, emoji, stickers, and
/// message media without changing their existing URL validation or loading
/// widgets.
class AppLifecycleTickerMode extends StatefulWidget {
  const AppLifecycleTickerMode({super.key, required this.child});

  final Widget child;

  @override
  State<AppLifecycleTickerMode> createState() => _AppLifecycleTickerModeState();
}

class _AppLifecycleTickerModeState extends State<AppLifecycleTickerMode>
    with WidgetsBindingObserver {
  late bool _isVisible;

  bool _isVisibleState(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _isVisible = _isVisibleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isVisible = _isVisibleState(state);
    if (_isVisible == isVisible) return;
    setState(() => _isVisible = isVisible);
  }

  @override
  Widget build(BuildContext context) {
    // Do not re-enable tickers disabled by a route or another accessibility /
    // visibility boundary higher in the tree.
    final ancestorTickersEnabled = TickerMode.valuesOf(context).enabled;
    return TickerMode(
      enabled: ancestorTickersEnabled && _isVisible,
      child: widget.child,
    );
  }
}
