import 'package:accordkit/accordkit.dart';
import 'package:flutter/material.dart';

/// Error-message helpers for accordkit's [RestResult].
///
/// Consolidates the `result.error?.toString() ?? 'Failed to …'` idiom and the
/// `'Failed: ${result.error ?? 'unknown error'}'` SnackBar that were repeated at
/// ~50 call sites across the admin, moderation, settings and DM screens.
extension RestResultErrorText on RestResult {
  /// The error rendered as text, or [fallback] when there is none.
  String errorOr(String fallback) => error?.toString() ?? fallback;
}

/// Shows a SnackBar reporting a failed [result] as `'<prefix>: <error>'`.
void showErrorSnack(
  BuildContext context,
  RestResult result, {
  required String prefix,
}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text('$prefix: ${result.error ?? 'unknown error'}')),
  );
}
