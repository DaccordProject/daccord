import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the audit-log dialog for [spaceId], listing recent moderation/admin
/// actions. Caller is responsible for gating on the `view_audit_log` permission.
Future<void> showAccordAuditLog(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AuditLogDialog(spaceId: spaceId),
  );
}

class _AuditLogDialog extends ConsumerStatefulWidget {
  const _AuditLogDialog({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_AuditLogDialog> createState() => _AuditLogDialogState();
}

class _AuditLogDialogState extends ConsumerState<_AuditLogDialog> {
  List<AccordAuditLogEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    if (client == null) return;
    final result =
        await client.auditLogs.list(widget.spaceId, query: {'limit': 50});
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _error = 'Failed to load audit log');
      return;
    }
    setState(() => _entries = _parse(result.data));
  }

  /// The endpoint returns raw JSON; entries may be a bare list or wrapped under
  /// `entries`/`audit_log_entries`.
  List<AccordAuditLogEntry> _parse(Object? data) {
    List<dynamic>? raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      raw = (data['entries'] ?? data['audit_log_entries']) as List<dynamic>?;
    }
    if (raw == null) return const [];
    return [
      for (final e in raw)
        if (e is Map<String, dynamic>) AccordAuditLogEntry.fromJson(e),
    ];
  }

  String _actionLabel(String actionType) {
    if (actionType.isEmpty) return 'Action';
    return actionType
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final entries = _entries;
    final members = ref.watch(accordMembersControllerProvider(widget.spaceId));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.history, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Audit log', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                          child: Text(_error!,
                              style: theme.textTheme.bodyMedium)),
                    )
                  : entries == null
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : entries.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                  child: Text('No audit log entries',
                                      style: theme.textTheme.bodyMedium)),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: entries.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final entry = entries[index];
                                final actor = members?[entry.userId];
                                final actorName = accordMemberName(actor,
                                    fallback: entry.userId);
                                return ListTile(
                                  leading: Icon(Icons.bolt,
                                      size: 18, color: colors.gray),
                                  title: Text(_actionLabel(entry.actionType),
                                      style: theme.textTheme.titleSmall),
                                  subtitle: Text(
                                    entry.reason.isEmpty
                                        ? 'by $actorName'
                                        : 'by $actorName — ${entry.reason}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
