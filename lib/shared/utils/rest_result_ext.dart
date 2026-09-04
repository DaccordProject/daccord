import 'package:accordkit/accordkit.dart';
import 'package:flutter/material.dart';

/// Error-message helpers for accordkit's [RestResult].
extension RestResultErrorText on RestResult {
  /// The error rendered as text, or [fallback] when there is none.
  String errorOr(String fallback) => error?.toString() ?? fallback;

  /// The server's own explanation, for surfaces shown to end users rather than
  /// to operators. [errorOr] renders `AccordError.toString()`, which carries the
  /// `AccordError(code: …)` wrapper — fine in an admin screen, noise in the
  /// message composer. Falls back to [fallback] when the error has no message.
  String errorMessageOr(String fallback) {
    final message = (error?.message ?? '').trim();
    return message.isEmpty ? fallback : message;
  }
}

/// Payload-parsing helpers for the self-loading cache controllers: log a
/// failed request and hand back the typed payload (or `null`) in one step.
extension RestResultParse on RestResult {
  /// The payload as a typed list, or `null` (logged) on failure or non-list
  /// data. [describe] names the resource for the failure log, e.g.
  /// `'channels for $spaceId'`.
  List<T>? listOrLog<T>(String describe) {
    if (!ok) {
      debugPrint('Failed to load $describe: $error');
      return null;
    }
    final payload = data;
    if (payload is! List) {
      debugPrint('Failed to load $describe: $error');
      return null;
    }
    return payload.whereType<T>().toList();
  }

  /// The payload as a single typed value, or `null` (logged) on failure or a
  /// type mismatch.
  T? dataOrLog<T>(String describe) {
    if (!ok) {
      debugPrint('Failed to $describe: $error');
      return null;
    }
    final payload = data;
    return payload is T ? payload : null;
  }
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
/// Companion to [showErrorSnack].
void showInfoSnack(BuildContext context, String message) {
  // Guarded here rather than at each of the call sites, several of which reach
  // this after an await.
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
