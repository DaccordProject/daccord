import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Shows a simple confirm/cancel [AlertDialog] and resolves to `true` when the
/// user confirms, `false` when they cancel, or `null` when dismissed.
///
/// Consolidates the near-identical confirmation dialogs that were copy-pasted
/// across the admin tabs, space moderation views and DM/member popouts. Set
/// [danger] to tint the confirm button with the theme's red for destructive
/// actions.
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
}) {
  final colors = BonfireThemeExtension.of(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: danger
              ? FilledButton.styleFrom(backgroundColor: colors.red)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
