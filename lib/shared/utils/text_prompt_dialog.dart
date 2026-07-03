import 'package:flutter/material.dart';

/// Shows an [AlertDialog] with a single [TextField] and resolves to the
/// entered text when confirmed, or `null` when cancelled/dismissed.
///
/// Consolidates the hand-rolled "one text field + Cancel/Save" dialogs that
/// were copy-pasted across the space settings (nickname), rail (folder name),
/// soundboard/emoji renames, admin space rename, DM group rename and profile
/// rename. Callers keep their own trim/empty-input semantics.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  String? label,
  String? helperText,
  String initial = '',
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
  bool obscureText = false,
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscureText,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            helperText: helperText,
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  } finally {
    // The route (and the TextField using the controller) is gone by the time
    // the dialog future resolves; dispose off the current frame to be safe.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
}
