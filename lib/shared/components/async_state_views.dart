import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Centered progress spinner shown while a screen, list or dialog loads.
///
/// Replaces the `Center(child: CircularProgressIndicator())` that was
/// hand-inlined as the busy state at ~28 sites across the admin, moderation,
/// settings, messaging and DM screens.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Inline error text rendered in the theme's red at `bodySmall` (the size used
/// by every error arm in the app).
///
/// Replaces the `Text(error, style: ...bodySmall...copyWith(color: colors.red))`
/// that was the error arm of the async-list state machine at ~20 sites. Pass
/// [centered] (the default) for the full-region case — equivalent to wrapping
/// the text in a [Center] — or `centered: false` to drop it inline in a column.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key, this.centered = true});

  final String message;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final text = Text(
      message,
      textAlign: centered ? TextAlign.center : null,
      style: theme.textTheme.bodySmall?.copyWith(color: colors.red),
    );
    return centered ? Center(child: text) : text;
  }
}
