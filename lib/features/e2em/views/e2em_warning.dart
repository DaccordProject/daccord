import 'package:bonfire/router/navigator_key.dart';
import 'package:flutter/material.dart';

import 'package:bonfire/features/e2em/models/e2em_preferences.dart';

Future<bool> confirmE2emWarning(String text, List<String> categories) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('E2EM warning'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Your rules flagged this draft. Review it before sending.',
                  ),
                  const SizedBox(height: 12),
                  for (final category in categories)
                    Text('• ${e2emCategories[category]?.label ?? category}'),
                  const SizedBox(height: 12),
                  SelectableText(text),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep draft'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send anyway'),
            ),
          ],
        ),
      ) ??
      false;
}
