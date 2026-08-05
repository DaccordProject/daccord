import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/load_more_footer.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a dialog to report [targetType]/[targetId] (e.g. a message or member)
/// to the space's moderators.
Future<void> showReportDialog(
  BuildContext context, {
  required String spaceId,
  required String targetType,
  required String targetId,
  String? channelId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReportDialog(
      spaceId: spaceId,
      targetType: targetType,
      targetId: targetId,
      channelId: channelId,
    ),
  );
}

class _ReportDialog extends ConsumerStatefulWidget {
  const _ReportDialog({
    required this.spaceId,
    required this.targetType,
    required this.targetId,
    this.channelId,
  });

  final String spaceId;
  final String targetType;
  final String targetId;
  final String? channelId;

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<_ReportDialog> {
  /// Offered reasons. Seeded from accordkit's canonical list, then replaced by
  /// whatever `GET /reports/categories` reports so a server that adds or drops
  /// a category doesn't leave us offering reasons it will reject.
  List<({String value, String label})> _categories = [
    for (final c in AccordReportCategory.values)
      (value: c.value, label: c.label),
  ];
  String? _category;
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) return;
    final result = await client.reports.categories();
    if (!mounted || !result.ok) return;
    final raw = result.data;
    final list = raw is Map ? raw['data'] : raw;
    if (list is! List) return;
    final parsed = <({String value, String label})>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final value = entry['value']?.toString();
      if (value == null || value.isEmpty) continue;
      final label = entry['label']?.toString();
      parsed.add((
        value: value,
        label: (label == null || label.isEmpty)
            ? AccordReportCategory.labelFor(value)
            : label,
      ));
    }
    if (parsed.isEmpty) return;
    setState(() {
      _categories = parsed;
      if (!parsed.any((c) => c.value == _category)) _category = null;
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) return;
    final category = _category;
    if (category == null) {
      setState(() => _error = 'Choose a reason for this report.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.reports.create(widget.spaceId, {
      'target_type': widget.targetType,
      'target_id': widget.targetId,
      'category': category,
      if (widget.channelId != null) 'channel_id': widget.channelId,
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim(),
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _done = true;
      } else {
        _error = result.errorOr('Failed to submit report');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _done
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: colors.green, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Report submitted',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Moderators will review it shortly.',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.gray,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Report ${widget.targetType}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        hintText: 'Choose a reason',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in _categories)
                          DropdownMenuItem(
                            value: c.value,
                            child: Text(c.label),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _category = v ?? _category),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _description,
                      enabled: !_busy,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Details (optional)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      InlineError(_error!, centered: false),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _busy || _category == null
                              ? null
                              : _submit,
                          child: const Text('Submit report'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Opens the moderation reports panel for [spaceId]: lists open reports and lets
/// a moderator resolve them. Gated by the caller (e.g. on `ban_members`).
Future<void> showReportsPanel(BuildContext context, {required String spaceId}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReportsPanel(spaceId: spaceId),
  );
}

class _ReportsPanel extends ConsumerStatefulWidget {
  const _ReportsPanel({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_ReportsPanel> createState() => _ReportsPanelState();
}

/// Status filters offered in the reports panel. `null` value = all statuses.
const _reportStatuses = <({String label, String? value})>[
  (label: 'Pending', value: 'pending'),
  (label: 'All', value: null),
  (label: 'Actioned', value: 'actioned'),
  (label: 'Dismissed', value: 'dismissed'),
];

const _reportPageSize = 25;

class _ReportsPanelState extends ConsumerState<_ReportsPanel>
    with PaginatedListState<Map<String, dynamic>, _ReportsPanel> {
  bool _busy = false;
  String? _status = 'pending';

  AccordClient? get _client => ref.accordClient;

  @override
  int get pageSize => _reportPageSize;

  @override
  bool get canLoad => _client != null;

  @override
  String? itemId(Map<String, dynamic> item) => item['id']?.toString();

  @override
  Future<RestResult> fetchPage({String? before}) => _client!.reports.list(
    widget.spaceId,
    query: {
      if (_status != null) 'status': _status,
      'limit': _reportPageSize,
      if (before != null) 'before': before,
    },
  );

  @override
  List<Map<String, dynamic>> parseItems(Object? data) {
    final raw = data is List
        ? data
        : (data is Map && data['reports'] is List
              ? data['reports'] as List
              : const []);
    return [for (final e in raw) _asMap(e)];
  }

  @override
  String loadError(RestResult result) => result.errorOr('Failed to load');

  @override
  String loadMoreError(RestResult result) =>
      result.errorOr('Failed to load more');

  Map<String, dynamic> _asMap(dynamic entry) {
    if (entry is Map<String, dynamic>) return entry;
    if (entry is Map) return entry.cast<String, dynamic>();
    return const {};
  }

  /// The reported user's id, derived from common shapes of the report JSON.
  String? _reportedUserId(Map<String, dynamic> r) {
    final type = r['target_type']?.toString() ?? '';
    if (type == 'user' || type == 'member') {
      final t = r['target_id']?.toString();
      if (t != null && t.isNotEmpty) return t;
    }
    for (final key in ['reported_user_id', 'target_user_id', 'author_id']) {
      final v = r[key]?.toString();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  Future<void> _resolve(
    String reportId,
    String status, {
    String? actionTaken,
  }) async {
    final client = _client;
    if (client == null) return;
    final result = await client.reports.resolve(widget.spaceId, reportId, {
      'status': status,
      if (actionTaken != null) 'action_taken': actionTaken,
    });
    if (!mounted) return;
    if (!result.ok) {
      setState(() => error = result.errorOr('Failed to resolve'));
      return;
    }
    setState(() => items.removeWhere((r) => r['id']?.toString() == reportId));
  }

  Future<void> _deleteMessage(Map<String, dynamic> r) async {
    final client = _client;
    final channelId = r['channel_id']?.toString();
    final messageId = r['target_id']?.toString();
    final id = r['id']?.toString() ?? '';
    if (client == null || channelId == null || messageId == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete message',
      message: 'Delete the reported message and action this report?',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final result = await client.messages.delete(channelId, messageId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => error = result.errorOr('Failed to delete message'));
      return;
    }
    await _resolve(id, 'actioned', actionTaken: 'delete_message');
  }

  Future<void> _kick(Map<String, dynamic> r) async {
    final client = _client;
    final userId = _reportedUserId(r);
    final id = r['id']?.toString() ?? '';
    if (client == null || userId == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Kick member',
      message: 'Kick the reported member and action this report?',
      confirmLabel: 'Kick',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final result = await client.members.kick(widget.spaceId, userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => error = result.errorOr('Failed to kick'));
      return;
    }
    await _resolve(id, 'actioned', actionTaken: 'kick_member');
  }

  Future<void> _ban(Map<String, dynamic> r) async {
    final client = _client;
    final userId = _reportedUserId(r);
    final id = r['id']?.toString() ?? '';
    if (client == null || userId == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Ban member',
      message: 'Ban the reported member and action this report?',
      confirmLabel: 'Ban',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final result = await client.bans.create(widget.spaceId, userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => error = result.errorOr('Failed to ban'));
      return;
    }
    await _resolve(id, 'actioned', actionTaken: 'ban_member');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 540, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.background, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Reports', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: colors.gray),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final s in _reportStatuses)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _status == s.value,
                      onSelected: loading
                          ? null
                          : (_) {
                              setState(() => _status = s.value);
                              load();
                            },
                    ),
                ],
              ),
            ),
            Expanded(
              child: loading
                  ? const LoadingView()
                  : items.isEmpty
                  ? Center(
                      child: Text(
                        'No reports',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: items.length + (hasMore ? 1 : 0),
                      separatorBuilder: (_, _) =>
                          Divider(height: 12, color: colors.background),
                      itemBuilder: (context, index) {
                        if (index >= items.length) {
                          return LoadMoreFooter(
                            loading: loadingMore,
                            onPressed: loadMore,
                            spinnerPadding: const EdgeInsets.all(8),
                          );
                        }
                        return _ReportRow(
                          report: items[index],
                          busy: _busy,
                          reportedUserId: _reportedUserId(items[index]),
                          onDismiss: (id) => _resolve(id, 'dismissed'),
                          onResolve: (id) =>
                              _resolve(id, 'resolved', actionTaken: 'none'),
                          onDeleteMessage: _deleteMessage,
                          onKick: _kick,
                          onBan: _ban,
                        );
                      },
                    ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: InlineError(error!, centered: false),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.report,
    required this.busy,
    required this.reportedUserId,
    required this.onDismiss,
    required this.onResolve,
    required this.onDeleteMessage,
    required this.onKick,
    required this.onBan,
  });

  final Map<String, dynamic> report;
  final bool busy;
  final String? reportedUserId;
  final void Function(String id) onDismiss;
  final void Function(String id) onResolve;
  final void Function(Map<String, dynamic> r) onDeleteMessage;
  final void Function(Map<String, dynamic> r) onKick;
  final void Function(Map<String, dynamic> r) onBan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final id = report['id']?.toString() ?? '';
    final category = AccordReportCategory.labelFor(
      report['category']?.toString(),
    );
    final categoryLabel = category.isEmpty ? 'report' : category;
    final description = report['description']?.toString() ?? '';
    final targetType = report['target_type']?.toString() ?? '';
    final channelId = report['channel_id']?.toString();
    final canDeleteMessage =
        targetType.contains('message') && channelId != null;

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
              '· $targetType',
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
                onPressed: busy ? null : () => onDeleteMessage(report),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete msg'),
              ),
            if (reportedUserId != null) ...[
              TextButton.icon(
                onPressed: busy ? null : () => onKick(report),
                icon: const Icon(Icons.exit_to_app, size: 16),
                label: const Text('Kick'),
              ),
              TextButton.icon(
                onPressed: busy ? null : () => onBan(report),
                style: TextButton.styleFrom(foregroundColor: colors.red),
                icon: const Icon(Icons.gavel, size: 16),
                label: const Text('Ban'),
              ),
            ],
            TextButton(
              onPressed: busy ? null : () => onDismiss(id),
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: busy ? null : () => onResolve(id),
              child: const Text('Resolve'),
            ),
          ],
        ),
      ],
    );
  }
}
