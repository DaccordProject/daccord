import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// A confirmed ban, carrying how much of the member's recent message history to
/// delete along with them.
class BanRequest {
  const BanRequest({required this.deleteMessageSeconds});

  /// How far back to purge the member's messages in this space, in seconds.
  /// `0` — the default — keeps their history.
  final int deleteMessageSeconds;

  /// The request body for `bans.create`. Omits `delete_message_seconds`
  /// entirely when nothing is being purged, so a ban against an older server
  /// that doesn't know the field looks exactly as it always did.
  Map<String, dynamic> toJson() => {
        if (deleteMessageSeconds > 0)
          'delete_message_seconds': deleteMessageSeconds,
      };
}

/// The purge windows offered in the ban dialog, matching the reference client
/// (and Discord). The server clamps anything longer than 7 days.
const _windows = <(String, int)>[
  ("Don't delete any", 0),
  ('Previous hour', 3600),
  ('Previous 6 hours', 21600),
  ('Previous 12 hours', 43200),
  ('Previous 24 hours', 86400),
  ('Previous 3 days', 259200),
  ('Previous 7 days', 604800),
];

/// Shows the ban confirmation for [memberName], including the "delete message
/// history" picker, and resolves to the chosen [BanRequest] — or `null` if the
/// moderator cancelled.
///
/// Replaces the plain [showConfirmDialog] the ban actions used, which could
/// only ever ban and leave every message behind.
Future<BanRequest?> showBanDialog(
  BuildContext context, {
  required String memberName,
}) {
  final colors = BonfireThemeExtension.of(context);
  return showDialog<BanRequest>(
    context: context,
    builder: (ctx) {
      var seconds = 0;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Ban member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$memberName will be banned from the space and removed.'),
              const SizedBox(height: 16),
              Text(
                'Delete message history',
                style: Theme.of(ctx).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: seconds,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final (label, value) in _windows)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: (value) =>
                    setState(() => seconds = value ?? seconds),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx)
                  .pop(BanRequest(deleteMessageSeconds: seconds)),
              style: FilledButton.styleFrom(backgroundColor: colors.red),
              child: const Text('Ban'),
            ),
          ],
        ),
      );
    },
  );
}
