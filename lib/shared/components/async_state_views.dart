import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Centered progress spinner shown while a screen, list or dialog loads.
///
/// Replaces the `Center(child: CircularProgressIndicator())` that was
/// hand-inlined as the busy state at ~29 sites across the admin, moderation,
/// settings, messaging and DM screens.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Inline error text rendered in the theme's red.
///
/// Replaces the `Text(error, style: ...copyWith(color: colors.red))` that was
/// the error arm of the same async-list state machine at ~20 sites.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key, this.centered = true});

  final String message;

  /// Whether to center and pad the message (the common full-region case) or
  /// render it as bare inline text (when the caller positions it).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final text = Text(
      message,
      textAlign: centered ? TextAlign.center : null,
      style: theme.textTheme.bodyMedium?.copyWith(color: colors.red),
    );
    if (!centered) return text;
    return Center(
      child: Padding(padding: const EdgeInsets.all(16), child: text),
    );
  }
}

/// Centered placeholder for an empty list or section: an optional [icon] above
/// a muted [message].
class EmptyView extends StatelessWidget {
  const EmptyView(this.message, {super.key, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: colors.gray, size: 40),
              const SizedBox(height: 12),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.gray),
            ),
          ],
        ),
      ),
    );
  }
}
