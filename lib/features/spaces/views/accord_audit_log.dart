import 'dart:async';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
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

const _pageSize = 25;

class _AuditLogDialog extends ConsumerStatefulWidget {
  const _AuditLogDialog({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_AuditLogDialog> createState() => _AuditLogDialogState();
}

class _AuditLogDialogState extends ConsumerState<_AuditLogDialog> {
  final List<AccordAuditLogEntry> _entries = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String? _actionFilter; // null = all
  String _userQuery = '';
  StreamSubscription<Map<String, dynamic>>? _liveSub;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeLive();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  void _subscribeLive() {
    final client = _client;
    if (client == null) return;
    _liveSub = client.onAuditLogCreate.listen((data) {
      // The gateway may scope the event with a space id; only prepend ours.
      final spaceId = (data['space_id'] ?? data['guild_id'])?.toString();
      if (spaceId != null && spaceId != widget.spaceId) return;
      final entry = AccordAuditLogEntry.fromJson(data);
      if (entry.id.isNotEmpty && _entries.any((e) => e.id == entry.id)) return;
      if (!mounted) return;
      setState(() => _entries.insert(0, entry));
    });
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await client.auditLogs.list(
      widget.spaceId,
      query: {'limit': _pageSize},
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _loading = false;
        _error = 'Failed to load audit log';
      });
      return;
    }
    final parsed = _parse(result.data);
    setState(() {
      _loading = false;
      _entries
        ..clear()
        ..addAll(parsed);
      _hasMore = parsed.length >= _pageSize;
    });
  }

  Future<void> _loadMore() async {
    final client = _client;
    if (client == null || _loadingMore || !_hasMore || _entries.isEmpty) return;
    setState(() => _loadingMore = true);
    final result = await client.auditLogs.list(
      widget.spaceId,
      query: {'limit': _pageSize, 'before': _entries.last.id},
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _loadingMore = false;
        _error = 'Failed to load more entries';
      });
      return;
    }
    final parsed = _parse(result.data);
    final existing = _entries.map((e) => e.id).toSet();
    final fresh = parsed.where((e) => !existing.contains(e.id)).toList();
    setState(() {
      _loadingMore = false;
      _entries.addAll(fresh);
      _hasMore = parsed.length >= _pageSize && fresh.isNotEmpty;
    });
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
    final members = ref.watch(accordMembersControllerProvider(widget.spaceId));
    final users = ref.watch(accordUsersControllerProvider);
    final ensureUser = ref.read(accordUsersControllerProvider.notifier).ensure;

    // Distinct action types present, for the filter dropdown.
    final actionTypes = <String>{
      for (final e in _entries)
        if (e.actionType.isNotEmpty) e.actionType,
    }.toList()..sort();

    final query = _userQuery.trim().toLowerCase();
    final visible = _entries.where((e) {
      if (_actionFilter != null && e.actionType != _actionFilter) return false;
      if (query.isNotEmpty) {
        final actor = accordAuthorName(
          e.userId,
          members: members,
          users: users,
          ensure: ensureUser,
        ).toLowerCase();
        if (!actor.contains(query)) return false;
      }
      return true;
    }).toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 520, maxHeight: 640),
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
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _actionFilter,
                      decoration: const InputDecoration(
                        labelText: 'Action',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All actions'),
                        ),
                        for (final a in actionTypes)
                          DropdownMenuItem(
                            value: a,
                            child: Text(_actionLabel(a)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _actionFilter = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'User',
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _userQuery = v),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _error != null && _entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(_error!, style: theme.textTheme.bodyMedium),
                      ),
                    )
                  : _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: LoadingView(),
                    )
                  : visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No matching entries',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: visible.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index >= visible.length) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: _loadingMore
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: _loadMore,
                                      child: const Text('Load more'),
                                    ),
                            ),
                          );
                        }
                        final entry = visible[index];
                        final actorName = accordAuthorName(
                          entry.userId,
                          members: members,
                          users: users,
                          ensure: ensureUser,
                        );
                        return ListTile(
                          leading: Icon(
                            Icons.bolt,
                            size: 18,
                            color: colors.gray,
                          ),
                          title: Text(
                            _actionLabel(entry.actionType),
                            style: theme.textTheme.titleSmall,
                          ),
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
