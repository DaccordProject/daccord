import 'package:flutter/material.dart';

/// Wraps the app so it can be fully rebuilt from scratch. Switching device
/// profiles reopens the `accord-session` / `accord-settings` boxes from a
/// different directory; the simplest correct way to re-seed every provider that
/// reads them is to recreate the [ProviderScope] subtree. Calling [restart]
/// swaps the subtree's key, disposing the old provider container (closing the
/// previous profile's gateway connections) and building a fresh one against the
/// now-active profile's storage.
class AppRestart extends StatefulWidget {
  const AppRestart({super.key, required this.child});

  final Widget child;

  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_AppRestartState>()?.restart();
  }

  @override
  State<AppRestart> createState() => _AppRestartState();
}

class _AppRestartState extends State<AppRestart> {
  Key _key = UniqueKey();

  void restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
