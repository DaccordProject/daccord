import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/admin/views/admin_list_scaffold.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/new_space_permissions.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Instance-admin "Spaces" tab: lists every space on the instance, with search,
/// create, delete and owner-transfer. Mirrors the reference client's
/// `server_management_panel` Spaces page. Uses `client.adminApi.listSpaces`
/// (instance-wide view) and `adminApi.updateSpace` (owner transfer).
class AdminSpacesTab extends ConsumerStatefulWidget {
  const AdminSpacesTab({super.key});

  @override
  ConsumerState<AdminSpacesTab> createState() => _AdminSpacesTabState();
}

class _AdminSpacesTabState extends ConsumerState<AdminSpacesTab>
    with SelfLoadingListState<AccordSpace, AdminSpacesTab> {
  String _query = '';

  AccordClient? get _client => ref.accordClient;

  @override
  bool get canLoad => _client != null;

  @override
  Future<(List<AccordSpace>?, String?)> fetchItems() async {
    final result = await _client!.adminApi.listSpaces(query: {'limit': 200});
    if (!result.ok) return (null, result.errorOr('Failed to load spaces'));
    final data = result.data;
    return (data is List ? data.cast<AccordSpace>() : <AccordSpace>[], null);
  }

  List<AccordSpace> get _filtered {
    final all = items ?? const <AccordSpace>[];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  /// Opens [space] in the rail using the admin's own connection — no public
  /// join. As an instance admin we already have access, so we just surface the
  /// space and navigate into it rather than hitting the member-join endpoint.
  void _open(AccordSpace space) {
    final state = ref.read(accordAuthProvider);
    final key = state is AccordAuthLoggedIn ? state.session.key : null;
    // Flip the active server *before* upserting: `setActiveServer` reseeds the
    // rail from the connection's cached space list, which would otherwise wipe
    // out the space we surface here.
    if (key != null) ref.read(accordAuthProvider.notifier).setActiveServer(key);
    ref.read(spacesControllerProvider.notifier).upsertSpace(space);
    context.go('/spaces?space=${Uri.encodeComponent(space.id)}');
  }

  Future<void> _create() async {
    final name = await showTextPromptDialog(
      context,
      title: 'Create space',
      label: 'Space name',
      confirmLabel: 'Create',
    );
    if (name == null || name.trim().isEmpty) return;
    final client = _client;
    if (client == null) return;
    setState(() => loading = true);
    final result = await client.spaces.create({'name': name.trim()});
    if (!mounted) return;
    setState(() => loading = false);
    if (!result.ok) {
      setState(() => error = result.errorOr('Failed to create space'));
      return;
    }
    final created = result.data;
    if (created is AccordSpace) {
      final normalized = await normalizeNewSpaceEveryoneRole(client, created);
      if (!mounted) return;
      if (normalized != null && !normalized.ok) {
        setState(
          () => error = normalized.errorOr(
            'Space created, but its default mention permission could not be secured',
          ),
        );
        return;
      }
    }
    load();
  }

  Future<void> _delete(AccordSpace space) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete space',
      message: "Delete '${space.name}'? This cannot be undone.",
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true) return;
    final client = _client;
    if (client == null) return;
    setState(() => loading = true);
    final result = await client.spaces.delete(space.id);
    if (!mounted) return;
    setState(() {
      loading = false;
      if (result.ok) {
        items?.removeWhere((s) => s.id == space.id);
      } else {
        error = result.errorOr('Failed to delete space');
      }
    });
  }

  Future<void> _transfer(AccordSpace space) async {
    final newOwnerId = await showTextPromptDialog(
      context,
      title: "Transfer '${space.name}'",
      label: 'New owner user ID',
      helperText: 'Copy a user ID from the Users tab',
      confirmLabel: 'Transfer',
    );
    if (newOwnerId == null || newOwnerId.trim().isEmpty) return;
    final client = _client;
    if (client == null) return;
    setState(() => loading = true);
    final result = await client.adminApi.updateSpace(space.id, {
      'owner_id': newOwnerId.trim(),
    });
    if (!mounted) return;
    final updated = result.data;
    setState(() {
      loading = false;
      if (!result.ok) {
        error = result.errorOr('Failed to transfer ownership');
      } else if (updated is AccordSpace) {
        final i = items?.indexWhere((s) => s.id == space.id) ?? -1;
        if (i >= 0) items![i] = updated;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return AdminListScaffold(
      error: error,
      loading: loading && items == null,
      isEmpty: list.isEmpty,
      emptyMessage: 'No spaces found.',
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Filter by name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: loading ? null : _create,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create'),
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
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => _SpaceRow(
          space: list[i],
          busy: loading,
          onOpen: () => _open(list[i]),
          onDelete: () => _delete(list[i]),
          onTransfer: () => _transfer(list[i]),
        ),
      ),
    );
  }
}

class _SpaceRow extends StatelessWidget {
  const _SpaceRow({
    required this.space,
    required this.busy,
    required this.onOpen,
    required this.onDelete,
    required this.onTransfer,
  });

  final AccordSpace space;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onTransfer;

  int get _memberCount => asInt(space.memberCount);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final initial = accordInitial(space.name);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primary,
        child: Text(initial, style: const TextStyle(color: Colors.white)),
      ),
      title: Text(space.name, style: theme.textTheme.titleSmall),
      subtitle: Text('$_memberCount members'),
      trailing: Wrap(
        spacing: 4,
        children: [
          TextButton(
            onPressed: busy ? null : onOpen,
            child: const Text('Open'),
          ),
          TextButton(
            onPressed: busy ? null : onTransfer,
            child: const Text('Transfer'),
          ),
          TextButton(
            onPressed: busy ? null : onDelete,
            style: TextButton.styleFrom(foregroundColor: colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
