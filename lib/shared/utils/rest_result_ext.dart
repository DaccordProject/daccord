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

  /// Branches on the result: runs [onOk] when [ok], otherwise [onError] with the
  /// error text ([fallback] when the error is null). Collapses the
  /// `if (!result.ok) { ...error... } else { ...parse... }` boilerplate repeated
  /// across the async-list views.
  T fold<T>(
    T Function() onOk,
    T Function(String error) onError, {
    String fallback = 'Something went wrong',
  }) =>
      ok ? onOk() : onError(errorOr(fallback));
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

/// Shows a SnackBar with an informational [message] (success/confirmation).
///
/// Companion to [showErrorSnack] for the non-error toasts that were otherwise
/// hand-inlined as `ScaffoldMessenger.maybeOf(context)?.showSnackBar(...)`
/// across the moderation, settings and DM screens.
void showInfoSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message)),
  );
}
