import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/admin/views/admin_list_scaffold.dart';
import 'package:bonfire/shared/components/moderation_report_row.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _maxConcurrentReportRequests = 4;

/// Instance-admin "Reports" tab: aggregates the per-space reports queues across
/// all spaces the admin belongs to (matching the reference
/// `server_management_reports`, which iterates `Client.spaces`). The Accord SDK
/// has no instance-wide reports endpoint, so we fan out `reports.list` per space
/// and merge, sorted by `created_at` descending.
class AdminReportsTab extends ConsumerStatefulWidget {
  const AdminReportsTab({super.key});

  @override
  ConsumerState<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends ConsumerState<AdminReportsTab> {
  final List<AccordReport> _reports = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _status = 'pending';

  AccordClient? get _client => ref.accordClient;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final spaces = ref.read(spacesControllerProvider) ?? const <AccordSpace>[];
    setState(() {
      _loading = true;
      _error = null;
    });
    final merged = <AccordReport>[];
    String? firstError;
    final reportSpaces = spaces.where((space) => space.id.isNotEmpty).toList();
    final status = _status;
    final results = List<RestResult?>.filled(reportSpaces.length, null);
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < reportSpaces.length) {
        final index = nextIndex++;
        results[index] = await client.reports.list(
          reportSpaces[index].id,
          query: {if (status != null) 'status': status, 'limit': 25},
        );
      }
    }

    await Future.wait([
      for (
        var i = 0;
        i < _maxConcurrentReportRequests && i < reportSpaces.length;
        i++
      )
        worker(),
    ]);
    for (var i = 0; i < reportSpaces.length; i++) {
      final result = results[i]!;
      if (!result.ok) {
        firstError ??= result.error?.toString();
        continue;
      }
      final reports = result.data is List
          ? (result.data as List).whereType<AccordReport>()
          : const <AccordReport>[];
      for (final report in reports) {
        if (report.id.isEmpty) continue;
        report.spaceId = reportSpaces[i].id;
        merged.add(report);
      }
    }
    if (!mounted) return;
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() {
      _loading = false;
      _reports
        ..clear()
        ..addAll(merged);
      _error = merged.isEmpty ? firstError : null;
    });
  }

  void _onAction(AccordReport report, ModerationReportAction action) {
    final client = _client;
    if (client == null) return;
    runModerationReportAction(
      context,
      client,
      spaceId: report.spaceId,
      report: report,
      action: action,
      onBusy: (busy) => setState(() => _busy = busy),
      onError: (message) => setState(() => _error = message),
      onResolved: () =>
          setState(() => _reports.removeWhere((e) => e.id == report.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return AdminListScaffold(
      error: _error,
      loading: _loading,
      isEmpty: _reports.isEmpty,
      emptyMessage: 'No reports',
      header: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                children: [
                  for (final s in moderationReportStatuses)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _status == s.value,
                      onSelected: _loading
                          ? null
                          : (_) {
                              setState(() => _status = s.value);
                              _load();
                            },
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
      ),
      list: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _reports.length,
        separatorBuilder: (_, _) =>
            Divider(height: 16, color: colors.background),
        itemBuilder: (context, i) => ModerationReportRow(
          report: _reports[i],
          busy: _busy,
          onAction: _onAction,
        ),
      ),
    );
  }
}
