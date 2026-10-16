import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/admin/views/admin_list_scaffold.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/shared/components/load_more_footer.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Instance-admin "Devices" tab: the instance's device bans, newest first,
/// with Unban. Bans are created from the Users tab ("Ban devices…"), which
/// bans every device an account has been recorded signing in from.
class AdminDeviceBansTab extends ConsumerStatefulWidget {
  const AdminDeviceBansTab({super.key});

  @override
  ConsumerState<AdminDeviceBansTab> createState() => _AdminDeviceBansTabState();
}

const _banPageSize = 50;

class _AdminDeviceBansTabState extends ConsumerState<AdminDeviceBansTab>
    with PaginatedListState<AccordDeviceBan, AdminDeviceBansTab> {
  bool _busy = false;

  AccordClient? get _client => ref.accordClient;

  @override
  int get pageSize => _banPageSize;

  @override
  bool get canLoad => _client != null;

  @override
  String itemId(AccordDeviceBan item) => item.id;

  @override
  Future<RestResult> fetchPage({String? before}) =>
      _client!.adminApi.listDeviceBans(
        query: {'limit': _banPageSize, if (before != null) 'after': before},
      );

  @override
  List<AccordDeviceBan> parseItems(Object? data) =>
      data is List ? data.cast<AccordDeviceBan>() : <AccordDeviceBan>[];

  @override
  String loadError(RestResult result) =>
      result.errorOr('Failed to load device bans');

  @override
  String loadMoreError(RestResult result) =>
      result.errorOr('Failed to load more');

  Future<void> _unban(AccordDeviceBan ban) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Unban device',
      message:
          "Lift the ban on device ${_shortFingerprint(ban)} "
          "(${_accountLabel(ban)})? It will be able to register and sign in "
          'again. Disabled accounts stay disabled.',
      confirmLabel: 'Unban',
    );
    if (ok != true) return;
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.adminApi.deleteDeviceBan(ban.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        items.removeWhere((b) => b.id == ban.id);
      } else {
        error = result.errorOr('Failed to unban device');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdminListScaffold(
      error: error,
      loading: loading,
      isEmpty: items.isEmpty,
      emptyMessage: 'No banned devices.',
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                "Banned devices can't register or sign in. Ban an account's "
                'devices from the Users tab.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
      ),
      list: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: items.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i >= items.length) {
            return LoadMoreFooter(loading: loadingMore, onPressed: loadMore);
          }
          return _DeviceBanRow(
            ban: items[i],
            busy: _busy,
            onUnban: () => _unban(items[i]),
          );
        },
      ),
    );
  }
}

String _accountLabel(AccordDeviceBan ban) {
  final username = ban.username?.trim() ?? '';
  if (username.isNotEmpty) return username;
  final userId = ban.userId?.trim() ?? '';
  return userId.isNotEmpty ? userId : 'Unknown account';
}

String _shortFingerprint(AccordDeviceBan ban) => ban.fingerprint.length > 12
    ? ban.fingerprint.substring(0, 12)
    : ban.fingerprint;

class _DeviceBanRow extends StatelessWidget {
  const _DeviceBanRow({
    required this.ban,
    required this.busy,
    required this.onUnban,
  });

  final AccordDeviceBan ban;
  final bool busy;
  final VoidCallback onUnban;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final reason = ban.reason?.trim() ?? '';
    final when = messageTimeFromIso(ban.createdAt);
    final by = ban.bannedBy?.trim() ?? '';
    final details = [
      'Device ${_shortFingerprint(ban)}',
      if (when.isNotEmpty) when,
      if (by.isNotEmpty) 'by $by',
    ].join(' · ');
    return ListTile(
      leading: Icon(Icons.phonelink_lock_outlined, color: colors.gray),
      title: Text(
        _accountLabel(ban),
        style: theme.textTheme.titleSmall,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(details, style: theme.textTheme.bodySmall),
          if (reason.isNotEmpty)
            Text(
              reason,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: TextButton(
        onPressed: busy ? null : onUnban,
        child: const Text('Unban'),
      ),
    );
  }
}
