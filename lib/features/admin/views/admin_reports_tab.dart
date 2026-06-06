import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status filters for the server-wide reports queue. `null` value = all.
const _statuses = <({String label, String? value})>[
  (label: 'Pending', value: 'pending'),
  (label: 'All', value: null),
  (label: 'Actioned', value: 'actioned'),
  (label: 'Dismissed', value: 'dismissed'),
];

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
  final List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _status = 'pending';

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Map<String, dynamic> _asMap(dynamic e) {
    if (e is Map<String, dynamic>) return e;
    if (e is Map) return e.cast<String, dynamic>();
    return const {};
  }

  List<Map<String, dynamic>> _parse(Object? data) {
    final raw = data is List
        ? data
        : (data is Map && data['reports'] is List
            ? data['reports'] as List
            : const []);
    return [for (final e in raw) _asMap(e)];
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final spaces = ref.read(spacesControllerProvider) ?? const <AccordSpace>[];
    setState(() {
      _loading = true;
      _error = null;
    });
    final merged = <Map<String, dynamic>>[];
    String? firstError;
    for (final space in spaces) {
      if (space.id.isEmpty) continue;
      final result = await client.reports.list(space.id, query: {
        if (_status != null) 'status': _status,
        'limit': 25,
      });
      if (!result.ok) {
        firstError ??= result.error?.toString();
        continue;
      }
      for (final r in _parse(result.data)) {
        if (r['id'] == null) continue;
        merged.add({...r, '_space_id': space.id});
      }
    }
    if (!mounted) return;
    merged.sort((a, b) => (b['created_at']?.toString() ?? '')
        .compareTo(a['created_at']?.toString() ?? ''));
    setState(() {
      _loading = false;
      _reports
        ..clear()
        ..addAll(merged);
      _error = merged.isEmpty ? firstError : null;
    });
  }

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

  Future<void> _resolve(Map<String, dynamic> r, String status,
      {String? actionTaken}) async {
    final client = _client;
    final spaceId = r['_space_id']?.toString();
    final id = r['id']?.toString();
    if (client == null || spaceId == null || id == null) return;
    final result = await client.reports.resolve(spaceId, id, {
      'status': status,
      if (actionTaken != null) 'action_taken': actionTaken,
    });
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _error = result.error?.toString() ?? 'Failed to resolve');
      return;
    }
    setState(() => _reports.removeWhere((e) => e['id']?.toString() == id));
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _kick(Map<String, dynamic> r) async {
    final client = _client;
    final spaceId = r['_space_id']?.toString();
    final userId = _reportedUserId(r);
    if (client == null || spaceId == null || userId == null) return;
    if (!await _confirm('Kick member',
        'Kick the reported member and action this report?', 'Kick')) {
      return;
    }
    setState(() => _busy = true);
    final result = await client.members.kick(spaceId, userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => _error = result.error?.toString() ?? 'Failed to kick');
      return;
    }
    await _resolve(r, 'actioned', actionTaken: 'kick_member');
  }

  Future<void> _ban(Map<String, dynamic> r) async {
    final client = _client;
    final spaceId = r['_space_id']?.toString();
    final userId = _reportedUserId(r);
    if (client == null || spaceId == null || userId == null) return;
    if (!await _confirm('Ban member',
        'Ban the reported member and action this report?', 'Ban')) {
      return;
    }
    setState(() => _busy = true);
    final result = await client.bans.create(spaceId, userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => _error = result.error?.toString() ?? 'Failed to ban');
      return;
    }
    await _resolve(r, 'actioned', actionTaken: 'ban_member');
  }

  Future<void> _deleteMessage(Map<String, dynamic> r) async {
    final client = _client;
    final channelId = r['channel_id']?.toString();
    final messageId = r['target_id']?.toString();
    if (client == null || channelId == null || messageId == null) return;
    if (!await _confirm('Delete message',
        'Delete the reported message and action this report?', 'Delete')) {
      return;
    }
    setState(() => _busy = true);
    final result = await client.messages.delete(channelId, messageId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() =>
          _error = result.error?.toString() ?? 'Failed to delete message');
      return;
    }
    await _resolve(r, 'actioned', actionTaken: 'delete_message');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final s in _statuses)
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(_error!,
                style:
                    theme.textTheme.bodySmall!.copyWith(color: colors.red)),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _reports.isEmpty
                  ? Center(
                      child: Text('No reports',
                          style: theme.textTheme.bodyMedium))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _reports.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 16, color: colors.background),
                      itemBuilder: (context, i) => _ReportRow(
                        report: _reports[i],
                        busy: _busy,
                        reportedUserId: _reportedUserId(_reports[i]),
                        onDismiss: () => _resolve(_reports[i], 'dismissed'),
                        onResolve: () =>
                            _resolve(_reports[i], 'resolved', actionTaken: 'none'),
                        onDeleteMessage: () => _deleteMessage(_reports[i]),
                        onKick: () => _kick(_reports[i]),
                        onBan: () => _ban(_reports[i]),
                      ),
                    ),
        ),
      ],
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
  final VoidCallback onDismiss;
  final VoidCallback onResolve;
  final VoidCallback onDeleteMessage;
  final VoidCallback onKick;
  final VoidCallback onBan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final category = report['category']?.toString() ?? 'report';
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
            Text(category, style: theme.textTheme.titleSmall),
            const SizedBox(width: 6),
            Text('· $targetType',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray)),
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
                onPressed: busy ? null : onDeleteMessage,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete msg'),
              ),
            if (reportedUserId != null) ...[
              TextButton.icon(
                onPressed: busy ? null : onKick,
                icon: const Icon(Icons.exit_to_app, size: 16),
                label: const Text('Kick'),
              ),
              TextButton.icon(
                onPressed: busy ? null : onBan,
                style: TextButton.styleFrom(foregroundColor: colors.red),
                icon: const Icon(Icons.gavel, size: 16),
                label: const Text('Ban'),
              ),
            ],
            TextButton(
              onPressed: busy ? null : onDismiss,
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: busy ? null : onResolve,
              child: const Text('Resolve'),
            ),
          ],
        ),
      ],
    );
  }
}
