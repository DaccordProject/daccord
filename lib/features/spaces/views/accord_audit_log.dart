import 'dart:async';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/load_more_footer.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:bonfire/shared/utils/string_ext.dart';

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

class _AuditLogDialogState extends ConsumerState<_AuditLogDialog>
    with PaginatedListState<AccordAuditLogEntry, _AuditLogDialog> {
  String? _actionFilter; // null = all
  String _userQuery = '';
  StreamSubscription<Map<String, dynamic>>? _liveSub;

  @override
  void initState() {
    super.initState(); // kicks off the mixin's initial load()
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
      if (entry.id.isNotEmpty && items.any((e) => e.id == entry.id)) return;
      if (!mounted) return;
      setState(() => items.insert(0, entry));
    });
  }

  @override
  int get pageSize => _pageSize;

  @override
  bool get canLoad => _client != null;

  @override
  String? itemId(AccordAuditLogEntry item) => item.id;

  @override
  Future<RestResult> fetchPage({String? before}) => _client!.auditLogs.list(
    widget.spaceId,
    query: {'limit': _pageSize, if (before != null) 'before': before},
  );

  @override
  String loadError(RestResult result) => 'Failed to load audit log';

  @override
  String loadMoreError(RestResult result) => 'Failed to load more entries';

  /// The endpoint returns raw JSON; entries may be a bare list or wrapped under
  /// `entries`/`audit_log_entries`.
  @override
  List<AccordAuditLogEntry> parseItems(Object? data) {
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

  String _actionLabel(String actionType) =>
      actionType.isEmpty ? 'Action' : titleCaseFromToken(actionType);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final members = ref.watch(accordMembersControllerProvider(ref.readActiveServerKey() ?? '', widget.spaceId));
    final users = ref.watch(accordUsersControllerProvider(ref.readActiveServerKey() ?? ''));
    final ensureUser = ref.read(accordUsersControllerProvider(ref.readActiveServerKey() ?? '').notifier).ensure;

    // Distinct action types present, for the filter dropdown.
    final actionTypes = <String>{
      for (final e in items)
        if (e.actionType.isNotEmpty) e.actionType,
    }.toList()..sort();

    final query = _userQuery.trim().toLowerCase();
    final visible = items.where((e) {
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
                    onPressed: loading ? null : load,
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
              child: error != null && items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(error!, style: theme.textTheme.bodyMedium),
                      ),
                    )
                  : loading
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
                      itemCount: visible.length + (hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index >= visible.length) {
                          return LoadMoreFooter(
                            loading: loadingMore,
                            onPressed: loadMore,
                            padding: const EdgeInsets.all(12),
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
