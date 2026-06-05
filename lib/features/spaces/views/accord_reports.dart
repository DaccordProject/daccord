import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Report categories offered in the report dialog. Mirrors the reference
/// client's `report_dialog` reasons.
const _reportCategories = <({String value, String label})>[
  (value: 'spam', label: 'Spam'),
  (value: 'harassment', label: 'Harassment'),
  (value: 'hate_speech', label: 'Hate speech'),
  (value: 'nsfw', label: 'Inappropriate content'),
  (value: 'violence', label: 'Violence or threats'),
  (value: 'other', label: 'Other'),
];

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
  String _category = _reportCategories.first.value;
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.reports.create(widget.spaceId, {
      'target_type': widget.targetType,
      'target_id': widget.targetId,
      'category': _category,
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
        _error = result.error?.toString() ?? 'Failed to submit report';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _done
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: colors.green, size: 40),
                    const SizedBox(height: 12),
                    Text('Report submitted',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Moderators will review it shortly.',
                        style: theme.textTheme.bodySmall!
                            .copyWith(color: colors.gray)),
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
                    Text('Report ${widget.targetType}',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in _reportCategories)
                          DropdownMenuItem(value: c.value, child: Text(c.label)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(
                              () => _category = v ?? _category),
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
                      Text(_error!,
                          style: theme.textTheme.bodySmall!
                              .copyWith(color: colors.red)),
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
                          onPressed: _busy ? null : _submit,
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
Future<void> showReportsPanel(
  BuildContext context, {
  required String spaceId,
}) {
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

class _ReportsPanelState extends ConsumerState<_ReportsPanel> {
  List<dynamic>? _reports;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result =
        await client.reports.list(widget.spaceId, query: {'status': 'open'});
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _reports = data is List
          ? data
          : (data is Map && data['reports'] is List
              ? data['reports'] as List
              : const []);
      if (!result.ok) _error = result.error?.toString() ?? 'Failed to load';
    });
  }

  Map<String, dynamic> _asMap(dynamic entry) {
    if (entry is Map<String, dynamic>) return entry;
    if (entry is Map) return entry.cast<String, dynamic>();
    return const {};
  }

  Future<void> _resolve(String reportId, String status) async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result =
        await client.reports.resolve(widget.spaceId, reportId, {'status': status});
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      await _load();
    } else {
      setState(() => _error = result.error?.toString() ?? 'Failed to resolve');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final reports = _reports;
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: colors.background, width: 1)),
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
            Expanded(
              child: reports == null
                  ? const Center(child: CircularProgressIndicator())
                  : reports.isEmpty
                      ? Center(
                          child: Text('No open reports',
                              style: theme.textTheme.bodyMedium))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: reports.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 12, color: colors.background),
                          itemBuilder: (context, index) {
                            final r = _asMap(reports[index]);
                            final id = r['id']?.toString() ?? '';
                            final category =
                                r['category']?.toString() ?? 'report';
                            final description =
                                r['description']?.toString() ?? '';
                            final targetType =
                                r['target_type']?.toString() ?? '';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.flag_outlined,
                                        size: 16, color: colors.red),
                                    const SizedBox(width: 6),
                                    Text(category,
                                        style: theme.textTheme.titleSmall),
                                    const SizedBox(width: 6),
                                    Text('· $targetType',
                                        style: theme.textTheme.bodySmall!
                                            .copyWith(color: colors.gray)),
                                  ],
                                ),
                                if (description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(description,
                                      style: theme.textTheme.bodySmall),
                                ],
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _resolve(id, 'dismissed'),
                                      child: const Text('Dismiss'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _resolve(id, 'resolved'),
                                      child: const Text('Resolve'),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(_error!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
