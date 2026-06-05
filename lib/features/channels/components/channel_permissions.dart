import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the per-channel permission overwrites editor for [channel]. Lets an
/// operator grant or deny specific permissions to individual roles, layered on
/// top of the space-wide role permissions. The Accord analogue of Discord's
/// channel permission overrides.
Future<void> showChannelPermissionsDialog(
  BuildContext context, {
  required String spaceId,
  required AccordChannel channel,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ChannelPermissionsDialog(spaceId: spaceId, channel: channel),
  );
}

/// The tri-state of a single permission within an overwrite: explicitly allowed,
/// explicitly denied, or inherited (neither list contains it).
enum _OverwriteState { allow, neutral, deny }

class _ChannelPermissionsDialog extends ConsumerStatefulWidget {
  const _ChannelPermissionsDialog({required this.spaceId, required this.channel});

  final String spaceId;
  final AccordChannel channel;

  @override
  ConsumerState<_ChannelPermissionsDialog> createState() =>
      _ChannelPermissionsDialogState();
}

class _ChannelPermissionsDialogState
    extends ConsumerState<_ChannelPermissionsDialog> {
  List<AccordPermissionOverwrite>? _overwrites;
  String? _selectedId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.read(accordAuthProvider
      .select((s) => s is AccordAuthLoggedIn ? s.client : null));

  List<AccordRole> get _roles {
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == widget.spaceId);
    return space?.roles ?? const <AccordRole>[];
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.channels.listOverwrites(widget.channel.id);
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _overwrites = result.ok && data is List
          ? data.whereType<AccordPermissionOverwrite>().toList()
          : <AccordPermissionOverwrite>[];
      _selectedId ??= _overwrites!.firstOrNull?.id;
    });
  }

  /// Roles that don't yet have an overwrite, available to add.
  List<AccordRole> get _addableRoles {
    final existing = (_overwrites ?? const []).map((o) => o.id).toSet();
    return _roles.where((r) => !existing.contains(r.id)).toList()
      ..sort((a, b) => b.position.compareTo(a.position));
  }

  Future<void> _addOverwrite(String roleId) async {
    final overwrite = AccordPermissionOverwrite(id: roleId, type: 'role');
    setState(() {
      _overwrites = [...?_overwrites, overwrite];
      _selectedId = roleId;
    });
    await _persist(overwrite);
  }

  Future<void> _persist(AccordPermissionOverwrite overwrite) async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.channels.upsertOverwrite(
      widget.channel.id,
      overwrite.id,
      {
        'type': overwrite.type,
        'allow': overwrite.allow,
        'deny': overwrite.deny,
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) _error = result.error?.toString() ?? 'Failed to save';
    });
  }

  Future<void> _removeOverwrite(AccordPermissionOverwrite overwrite) async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result =
        await client.channels.deleteOverwrite(widget.channel.id, overwrite.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _overwrites = (_overwrites ?? const [])
            .where((o) => o.id != overwrite.id)
            .toList();
        if (_selectedId == overwrite.id) {
          _selectedId = _overwrites!.firstOrNull?.id;
        }
      } else {
        _error = result.error?.toString() ?? 'Failed to remove';
      }
    });
  }

  void _setPermission(
      AccordPermissionOverwrite overwrite, String perm, _OverwriteState state) {
    overwrite.allow.remove(perm);
    overwrite.deny.remove(perm);
    if (state == _OverwriteState.allow) {
      overwrite.allow.add(perm);
    } else if (state == _OverwriteState.deny) {
      overwrite.deny.add(perm);
    }
    setState(() {});
    _persist(overwrite);
  }

  String _roleName(String id) =>
      _roles.firstWhereOrNull((r) => r.id == id)?.name ?? id;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final overwrites = _overwrites;
    final selected =
        overwrites?.firstWhereOrNull((o) => o.id == _selectedId);

    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
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
                    child: Text(
                      'Permissions — ${widget.channel.name ?? widget.channel.id}',
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
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
              child: overwrites == null
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 220,
                          child: _RoleListPane(
                            overwrites: overwrites,
                            selectedId: _selectedId,
                            addable: _addableRoles,
                            busy: _busy,
                            roleName: _roleName,
                            onSelect: (id) => setState(() => _selectedId = id),
                            onAdd: _addOverwrite,
                          ),
                        ),
                        VerticalDivider(width: 1, color: colors.background),
                        Expanded(
                          child: selected == null
                              ? Center(
                                  child: Text(
                                    'Add a role to set channel permissions',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                )
                              : _OverwriteEditorPane(
                                  key: ValueKey(selected.id),
                                  overwrite: selected,
                                  roleName: _roleName(selected.id),
                                  busy: _busy,
                                  onSet: _setPermission,
                                  onRemove: () => _removeOverwrite(selected),
                                ),
                        ),
                      ],
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

class _RoleListPane extends StatelessWidget {
  const _RoleListPane({
    required this.overwrites,
    required this.selectedId,
    required this.addable,
    required this.busy,
    required this.roleName,
    required this.onSelect,
    required this.onAdd,
  });

  final List<AccordPermissionOverwrite> overwrites;
  final String? selectedId;
  final List<AccordRole> addable;
  final bool busy;
  final String Function(String) roleName;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: PopupMenuButton<String>(
            enabled: !busy && addable.isNotEmpty,
            onSelected: onAdd,
            itemBuilder: (_) => [
              for (final role in addable)
                PopupMenuItem(value: role.id, child: Text(role.name)),
            ],
            child: AbsorbPointer(
              child: FilledButton.icon(
                onPressed: addable.isEmpty ? null : () {},
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add role'),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final o in overwrites)
                Material(
                  color: o.id == selectedId
                      ? colors.darkGray
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onSelect(o.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 16, color: colors.gray),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(roleName(o.id),
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverwriteEditorPane extends StatelessWidget {
  const _OverwriteEditorPane({
    super.key,
    required this.overwrite,
    required this.roleName,
    required this.busy,
    required this.onSet,
    required this.onRemove,
  });

  final AccordPermissionOverwrite overwrite;
  final String roleName;
  final bool busy;
  final void Function(
          AccordPermissionOverwrite, String, _OverwriteState) onSet;
  final VoidCallback onRemove;

  _OverwriteState _stateOf(String perm) {
    if (overwrite.allow.contains(perm)) return _OverwriteState.allow;
    if (overwrite.deny.contains(perm)) return _OverwriteState.deny;
    return _OverwriteState.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(roleName,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              TextButton(
                onPressed: busy ? null : onRemove,
                style: TextButton.styleFrom(foregroundColor: colors.red),
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final perm in AccordPermission.all())
            _PermissionRow(
              label: _label(perm),
              state: _stateOf(perm),
              enabled: !busy,
              onChanged: (s) => onSet(overwrite, perm, s),
            ),
        ],
      ),
    );
  }

  static String _label(String perm) => perm
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.state,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final _OverwriteState state;
  final bool enabled;
  final ValueChanged<_OverwriteState> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          _TriButton(
            icon: Icons.close,
            color: colors.red,
            selected: state == _OverwriteState.deny,
            onTap: enabled
                ? () => onChanged(state == _OverwriteState.deny
                    ? _OverwriteState.neutral
                    : _OverwriteState.deny)
                : null,
          ),
          const SizedBox(width: 4),
          _TriButton(
            icon: Icons.remove,
            color: colors.gray,
            selected: state == _OverwriteState.neutral,
            onTap: enabled ? () => onChanged(_OverwriteState.neutral) : null,
          ),
          const SizedBox(width: 4),
          _TriButton(
            icon: Icons.check,
            color: colors.green,
            selected: state == _OverwriteState.allow,
            onTap: enabled
                ? () => onChanged(state == _OverwriteState.allow
                    ? _OverwriteState.neutral
                    : _OverwriteState.allow)
                : null,
          ),
        ],
      ),
    );
  }
}

class _TriButton extends StatelessWidget {
  const _TriButton({
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 28,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? color : colors.darkGray,
            width: 1.5,
          ),
        ),
        child: Icon(icon, size: 16, color: selected ? color : colors.gray),
      ),
    );
  }
}
