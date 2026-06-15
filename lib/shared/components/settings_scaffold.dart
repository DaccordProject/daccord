import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Standard chrome for a pushed settings sub-page: themed [Scaffold] +
/// [AppBar] with a back button that calls `Navigator.maybePop`.
///
/// Consolidates the identical `Scaffold(backgroundColor → AppBar(…, leading:
/// back))` shell that was copy-pasted into the connections, privacy, profiles,
/// voice, updates and developer settings screens.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.foreground,
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}
