import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
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

class _AdminSpacesTabState extends ConsumerState<AdminSpacesTab> {
  List<AccordSpace>? _spaces;
  String? _error;
  bool _busy = false;
  String _query = '';

  AccordClient? get _client => ref.accordClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<AccordSpace> get _filtered {
    final all = _spaces ?? const <AccordSpace>[];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.adminApi.listSpaces(query: {'limit': 200});
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.errorOr('Failed to load spaces');
      });
      return;
    }
    final data = result.data;
    setState(() {
      _busy = false;
      _spaces = data is List ? data.cast<AccordSpace>() : <AccordSpace>[];
    });
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
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _TextPromptDialog(
        title: 'Create space',
        label: 'Space name',
        action: 'Create',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.spaces.create({'name': name.trim()});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() =>
          _error = result.errorOr('Failed to create space'));
      return;
    }
    _load();
  }

  Future<void> _delete(AccordSpace space) async {
    final ok = await _confirm(
      'Delete space',
      "Delete '${space.name}'? This cannot be undone.",
      'Delete',
    );
    if (ok != true) return;
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.spaces.delete(space.id);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.errorOr('Failed to delete space');
      });
      return;
    }
    setState(() {
      _busy = false;
      _spaces?.removeWhere((s) => s.id == space.id);
    });
  }

  Future<void> _transfer(AccordSpace space) async {
    final newOwnerId = await showDialog<String>(
      context: context,
      builder: (ctx) => _TextPromptDialog(
        title: "Transfer '${space.name}'",
        label: 'New owner user ID',
        hint: 'Copy a user ID from the Users tab',
        action: 'Transfer',
      ),
    );
    if (newOwnerId == null || newOwnerId.trim().isEmpty) return;
    final client = _client;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.adminApi
        .updateSpace(space.id, {'owner_id': newOwnerId.trim()});
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.errorOr('Failed to transfer ownership');
      });
      return;
    }
    final updated = result.data;
    setState(() {
      _busy = false;
      if (updated is AccordSpace) {
        final i = _spaces?.indexWhere((s) => s.id == space.id) ?? -1;
        if (i >= 0) _spaces![i] = updated;
      }
    });
  }

  Future<bool?> _confirm(String title, String message, String action) {
    return showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final spaces = _spaces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create'),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _busy ? null : _load,
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
          child: _busy && spaces == null
              ? const Center(child: CircularProgressIndicator())
              : spaces == null
                  ? const SizedBox.shrink()
                  : Builder(builder: (context) {
                      final list = _filtered;
                      if (list.isEmpty) {
                        return Center(
                          child: Text('No spaces found.',
                              style: theme.textTheme.bodyMedium),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _SpaceRow(
                          space: list[i],
                          busy: _busy,
                          onOpen: () => _open(list[i]),
                          onDelete: () => _delete(list[i]),
                          onTransfer: () => _transfer(list[i]),
                        ),
                      );
                    }),
        ),
      ],
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

  int get _memberCount {
    final c = space.memberCount;
    if (c is int) return c;
    if (c is num) return c.toInt();
    return int.tryParse(c?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final initial =
        space.name.isNotEmpty ? space.name[0].toUpperCase() : '?';
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

/// Small single-field prompt dialog returning the entered text (or null).
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.action,
    this.hint,
  });

  final String title;
  final String label;
  final String action;
  final String? hint;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
