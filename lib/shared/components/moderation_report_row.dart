import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/ban_dialog.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Status filters shared by the per-space and instance-wide report queues.
const moderationReportStatuses = <({String label, String? value})>[
  (label: 'Pending', value: 'pending'),
  (label: 'All', value: null),
  (label: 'Actioned', value: 'actioned'),
  (label: 'Dismissed', value: 'dismissed'),
];

/// What a [ModerationReportRow] button asks for.
enum ModerationReportAction { dismiss, resolve, deleteMessage, kick, ban }

/// Carries out [action] on [report] in [spaceId] for a report queue.
///
/// Kick and message deletion are confirmed (ban asks for its options) before
/// their request, which [onBusy] brackets; a successful action then marks the
/// report `actioned`. Failures go to [onError] and [onResolved] runs once the
/// report has left the queue. Nothing is reported after [context] unmounts.
Future<void> runModerationReportAction(
  BuildContext context,
  AccordClient client, {
  required String spaceId,
  required AccordReport report,
  required ModerationReportAction action,
  required ValueChanged<bool> onBusy,
  required ValueChanged<String> onError,
  required VoidCallback onResolved,
}) async {
  Future<void> resolve(String status, String? actionTaken) async {
    if (spaceId.isEmpty || report.id.isEmpty) return;
    final result = await client.reports.resolve(spaceId, report.id, {
      'status': status,
      if (actionTaken != null) 'action_taken': actionTaken,
    });
    if (!context.mounted) return;
    if (result.ok) {
      onResolved();
    } else {
      onError(result.errorOr('Failed to resolve'));
    }
  }

  final userId = report.reportedUserId;
  final channelId = report.channelId;
  final Future<RestResult> Function() request;
  final String actionTaken;
  final String failure;
  switch (action) {
    case ModerationReportAction.dismiss:
      return resolve('dismissed', null);
    case ModerationReportAction.resolve:
      return resolve('resolved', 'none');
    case ModerationReportAction.deleteMessage:
      if (channelId == null || report.targetId.isEmpty) return;
      final ok = await showConfirmDialog(
        context,
        title: 'Delete message',
        message: 'Delete the reported message and action this report?',
        confirmLabel: 'Delete',
      );
      if (ok != true) return;
      request = () => client.messages.delete(channelId, report.targetId);
      actionTaken = 'delete_message';
      failure = 'Failed to delete message';
    case ModerationReportAction.kick:
      if (userId == null) return;
      final ok = await showConfirmDialog(
        context,
        title: 'Kick member',
        message: 'Kick the reported member and action this report?',
        confirmLabel: 'Kick',
      );
      if (ok != true) return;
      request = () => client.members.kick(spaceId, userId);
      actionTaken = 'kick_member';
      failure = 'Failed to kick';
    case ModerationReportAction.ban:
      if (userId == null) return;
      final ban = await showBanDialog(
        context,
        memberName: 'The reported member',
      );
      if (ban == null) return;
      request = () => client.bans.create(spaceId, userId, data: ban.toJson());
      actionTaken = 'ban_member';
      failure = 'Failed to ban';
  }
  if (!context.mounted) return;
  onBusy(true);
  final result = await request();
  if (!context.mounted) return;
  onBusy(false);
  if (result.ok) {
    await resolve('actioned', actionTaken);
  } else {
    onError(result.errorOr(failure));
  }
}

/// Shared presentation and actions for one moderation report.
class ModerationReportRow extends StatelessWidget {
  const ModerationReportRow({
    super.key,
    required this.report,
    required this.busy,
    required this.onAction,
  });

  final AccordReport report;
  final bool busy;
  final void Function(AccordReport report, ModerationReportAction action)
  onAction;

  VoidCallback? _on(ModerationReportAction action) =>
      busy ? null : () => onAction(report, action);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final category = AccordReportCategory.labelFor(report.category);
    final categoryLabel = category.isEmpty ? 'report' : category;
    final description = report.description ?? '';
    final canDeleteMessage =
        report.targetType.contains('message') && report.channelId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flag_outlined, size: 16, color: colors.red),
            const SizedBox(width: 6),
            Text(categoryLabel, style: theme.textTheme.titleSmall),
            const SizedBox(width: 6),
            Text(
              '· ${report.targetType}',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(description, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 4,
          children: [
            if (canDeleteMessage)
              TextButton.icon(
                onPressed: _on(ModerationReportAction.deleteMessage),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete msg'),
              ),
            if (report.reportedUserId != null) ...[
              TextButton.icon(
                onPressed: _on(ModerationReportAction.kick),
                icon: const Icon(Icons.exit_to_app, size: 16),
                label: const Text('Kick'),
              ),
              TextButton.icon(
                onPressed: _on(ModerationReportAction.ban),
                style: TextButton.styleFrom(foregroundColor: colors.red),
                icon: const Icon(Icons.gavel, size: 16),
                label: const Text('Ban'),
              ),
            ],
            TextButton(
              onPressed: _on(ModerationReportAction.dismiss),
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: _on(ModerationReportAction.resolve),
              child: const Text('Resolve'),
            ),
          ],
        ),
      ],
    );
  }
}
