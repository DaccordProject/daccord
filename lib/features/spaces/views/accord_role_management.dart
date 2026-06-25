import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/role_preview.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the role management dialog for [spaceId]: list, create, edit, delete,
/// and reorder roles, with a permission grid. The Accord analogue of the
/// reference client's `role_management_dialog`. Hierarchy is enforced — a user
/// may only act on roles strictly below their own highest role.
Future<void> showAccordRoleManagement(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RoleManagement(spaceId: spaceId),
  );
}

/// A small preset palette for the color picker, matching the reference client's
/// common role colors. The leading entry (0) means "no color".
const _palette = <int>[
  0x000000,
  0x1ABC9C,
  0x2ECC71,
  0x3498DB,
  0x9B59B6,
  0xE91E63,
  0xF1C40F,
  0xE67E22,
  0xE74C3C,
  0x95A5A6,
  0x607D8B,
  0x11806A,
  0x1F8B4C,
  0x206694,
  0x71368A,
  0xAD1457,
  0xC27C0E,
  0xA84300,
  0x992D22,
];

class _RoleManagement extends ConsumerStatefulWidget {
  const _RoleManagement({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_RoleManagement> createState() => _RoleManagementState();
}

class _RoleManagementState extends ConsumerState<_RoleManagement> {
  String? _selectedRoleId;
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.accordClient;

  List<AccordRole> get _roles {
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == widget.spaceId);
    return space?.roles ?? const <AccordRole>[];
  }

  int _myHighest() {
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == widget.spaceId);
    final currentUserId = ref.readUserId();
    final isAdmin = ref.readIsAdmin();
    final members = ref.read(accordMembersControllerProvider(widget.spaceId));
    return accordMyHighestRolePosition(
      space: space,
      selfMember: currentUserId == null ? null : members?[currentUserId],
      roles: _roles,
      currentUserId: currentUserId ?? '',
      currentUserIsAdmin: isAdmin,
    );
  }

  /// A role is editable when it sits strictly below the user's highest role and
  /// isn't integration-managed. `@everyone` (position 0) is editable for its
  /// permissions but can't be deleted or reordered.
  bool _canEdit(AccordRole role) =>
      !role.managed && role.position < _myHighest();

  Future<T?> _run<T>(
    Future<RestResult> Function(AccordClient client) action, {
    String failure = 'Action failed',
  }) async {
    final client = _client;
    if (client == null || _busy) return null;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action(client);
    if (!mounted) return null;
    setState(() {
      _busy = false;
      if (!result.ok) _error = result.errorOr(failure);
    });
    return result.ok ? result.data as T? : null;
  }

  Future<void> _createRole() async {
    final role = await _run<AccordRole>(
      (c) => c.roles.create(widget.spaceId, {
        'name': 'new role',
        'color': 0,
        'hoist': false,
        'mentionable': false,
        'permissions': <String>[],
      }),
      failure: 'Failed to create role',
    );
    if (role == null || !mounted) return;
    ref
        .read(spacesControllerProvider.notifier)
        .upsertRole(widget.spaceId, role);
    setState(() => _selectedRoleId = role.id);
  }

  Future<void> _saveRole(AccordRole edited) async {
    final role = await _run<AccordRole>(
      (c) => c.roles.update(widget.spaceId, edited.id, {
        'name': edited.name,
        'color': edited.color,
        'hoist': edited.hoist,
        'mentionable': edited.mentionable,
        'permissions': edited.permissions,
      }),
      failure: 'Failed to save role',
    );
    if (role == null || !mounted) return;
    ref
        .read(spacesControllerProvider.notifier)
        .upsertRole(widget.spaceId, role);
  }

  /// Enters "preview as role" for [role] and closes this dialog so the user
  /// sees the app gated as that role would (with the exit banner up top).
  void _previewRole(AccordRole role) {
    ref
        .read(rolePreviewControllerProvider.notifier)
        .enter(
          RolePreview(
            spaceId: widget.spaceId,
            roleId: role.id,
            roleName: role.name,
          ),
        );
    Navigator.of(context).maybePop();
  }

  Future<void> _deleteRole(AccordRole role) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete role',
      message: 'Delete the "${role.name}" role? This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (confirmed != true) return;
    final ok = await _run(
      (c) => c.roles.delete(widget.spaceId, role.id),
      failure: 'Failed to delete role',
    );
    if (ok == null && _error != null) return;
    if (!mounted) return;
    ref
        .read(spacesControllerProvider.notifier)
        .removeRole(widget.spaceId, role.id);
    setState(() {
      if (_selectedRoleId == role.id) _selectedRoleId = null;
    });
  }

  /// Reorders the editable (non-@everyone) roles after a drag, then persists the
  /// new positions. Positions count down from the top so higher roles outrank.
  Future<void> _reorder(List<AccordRole> ordered) async {
    // Assign descending positions, keeping @everyone pinned at 0.
    final payload = <Map<String, dynamic>>[];
    var position = ordered.length;
    for (final role in ordered) {
      payload.add({'id': role.id, 'position': position});
      position--;
    }
    final updated = await _run<List<dynamic>>(
      (c) => c.roles.reorder(widget.spaceId, payload),
      failure: 'Failed to reorder roles',
    );
    if (!mounted) return;
    if (updated != null) {
      final roles = updated.whereType<AccordRole>().toList();
      if (roles.isNotEmpty) {
        ref
            .read(spacesControllerProvider.notifier)
            .setRoles(widget.spaceId, roles);
        return;
      }
    }
    // Fall back to optimistic local reorder if the server returns nothing.
    for (final entry in payload) {
      final role = _roles.firstWhereOrNull((r) => r.id == entry['id']);
      if (role != null) role.position = entry['position'] as int;
    }
    ref.read(spacesControllerProvider.notifier).setRoles(widget.spaceId, [
      ..._roles,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final roles = ref.watch(
      spacesControllerProvider.select(
        (spaces) =>
            spaces?.firstWhereOrNull((s) => s.id == widget.spaceId)?.roles ??
            const <AccordRole>[],
      ),
    );
    final sorted = [...roles]..sort((a, b) => b.position.compareTo(a.position));
    final selected = sorted.firstWhereOrNull((r) => r.id == _selectedRoleId);

    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 720, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(onClose: () => Navigator.of(context).pop()),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 240,
                    child: _RoleListPane(
                      roles: sorted,
                      selectedId: _selectedRoleId,
                      busy: _busy,
                      canEdit: _canEdit,
                      onSelect: (id) => setState(() => _selectedRoleId = id),
                      onCreate: _createRole,
                      onReorder: _reorder,
                    ),
                  ),
                  VerticalDivider(width: 1, color: colors.background),
                  Expanded(
                    child: selected == null
                        ? Center(
                            child: Text(
                              'Select a role to edit',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : _RoleEditorPane(
                            key: ValueKey(selected.id),
                            role: selected,
                            editable: _canEdit(selected),
                            busy: _busy,
                            onSave: _saveRole,
                            onDelete: selected.position == 0
                                ? null
                                : () => _deleteRole(selected),
                            onPreview: () => _previewRole(selected),
                          ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: InlineError(_error!, centered: false),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.background, width: 1)),
      ),
      child: Row(
        children: [
          Text('Roles', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: Icon(Icons.close, size: 20, color: colors.gray),
          ),
        ],
      ),
    );
  }
}

class _RoleListPane extends StatelessWidget {
  const _RoleListPane({
    required this.roles,
    required this.selectedId,
    required this.busy,
    required this.canEdit,
    required this.onSelect,
    required this.onCreate,
    required this.onReorder,
  });

  final List<AccordRole> roles;
  final String? selectedId;
  final bool busy;
  final bool Function(AccordRole) canEdit;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<List<AccordRole>> onReorder;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // @everyone stays pinned at the bottom and isn't draggable.
    final draggable = roles.where((r) => r.position != 0).toList();
    final everyone = roles.firstWhereOrNull((r) => r.position == 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(
            onPressed: busy ? null : onCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create role'),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              if (busy) return;
              if (newIndex > oldIndex) newIndex--;
              final reordered = [...draggable];
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              onReorder(reordered);
            },
            children: [
              for (var i = 0; i < draggable.length; i++)
                _RoleListTile(
                  key: ValueKey(draggable[i].id),
                  index: i,
                  role: draggable[i],
                  selected: draggable[i].id == selectedId,
                  draggable: canEdit(draggable[i]),
                  onTap: () => onSelect(draggable[i].id),
                ),
            ],
          ),
        ),
        if (everyone != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _RoleListTile(
              role: everyone,
              selected: everyone.id == selectedId,
              draggable: false,
              onTap: () => onSelect(everyone.id),
            ),
          ),
        if (everyone != null) Divider(height: 1, color: colors.background),
      ],
    );
  }
}

class _RoleListTile extends StatelessWidget {
  const _RoleListTile({
    super.key,
    required this.role,
    required this.selected,
    required this.draggable,
    required this.onTap,
    this.index,
  });

  final AccordRole role;
  final bool selected;
  final bool draggable;
  final VoidCallback onTap;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final dot = accordRoleColor(role.color) ?? colors.gray;
    final tile = Material(
      color: selected ? colors.darkGray : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  role.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (draggable && index != null)
                ReorderableDragStartListener(
                  index: index!,
                  child: Icon(Icons.drag_handle, size: 18, color: colors.gray),
                ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: tile,
    );
  }
}

class _RoleEditorPane extends StatefulWidget {
  const _RoleEditorPane({
    super.key,
    required this.role,
    required this.editable,
    required this.busy,
    required this.onSave,
    required this.onDelete,
    required this.onPreview,
  });

  final AccordRole role;
  final bool editable;
  final bool busy;
  final ValueChanged<AccordRole> onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onPreview;

  @override
  State<_RoleEditorPane> createState() => _RoleEditorPaneState();
}

class _RoleEditorPaneState extends State<_RoleEditorPane> {
  late TextEditingController _name;
  late int _color;
  late bool _hoist;
  late bool _mentionable;
  late Set<String> _permissions;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.role.name);
    _color = widget.role.color;
    _hoist = widget.role.hoist;
    _mentionable = widget.role.mentionable;
    _permissions = widget.role.permissions.map((p) => p.toString()).toSet();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final edited = AccordRole(
      id: widget.role.id,
      name: _name.text.trim().isEmpty ? widget.role.name : _name.text.trim(),
      color: _color,
      hoist: _hoist,
      icon: widget.role.icon,
      position: widget.role.position,
      permissions: _permissions.toList(),
      managed: widget.role.managed,
      mentionable: _mentionable,
    );
    widget.onSave(edited);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final enabled = widget.editable && !widget.busy;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.editable)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                widget.role.managed
                    ? 'This role is managed by an integration.'
                    : 'This role is at or above your highest role.',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
              ),
            ),
          Text(
            'ROLE NAME',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            enabled: enabled,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.darkGray,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'COLOR',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in _palette)
                _ColorSwatch(
                  value: value,
                  selected: value == _color,
                  onTap: enabled ? () => setState(() => _color = value) : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hoist,
            onChanged: enabled ? (v) => setState(() => _hoist = v) : null,
            title: const Text('Display separately'),
            subtitle: Text(
              'Show members with this role in their own section',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _mentionable,
            onChanged: enabled ? (v) => setState(() => _mentionable = v) : null,
            title: const Text('Allow @mention'),
            subtitle: Text(
              'Anyone can @mention this role',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'PERMISSIONS',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          for (final perm in AccordPermission.all())
            _PermissionTile(
              perm: perm,
              value: _permissions.contains(perm),
              enabled: enabled,
              onChanged: (v) => setState(() {
                if (v) {
                  _permissions.add(perm);
                } else {
                  _permissions.remove(perm);
                }
              }),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.onDelete != null)
                TextButton(
                  onPressed: enabled ? widget.onDelete : null,
                  style: TextButton.styleFrom(foregroundColor: colors.red),
                  child: const Text('Delete role'),
                ),
              if (widget.onPreview != null)
                TextButton.icon(
                  onPressed: widget.busy ? null : widget.onPreview,
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('Preview as role'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: enabled ? _save : null,
                child: const Text('Save changes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final color = accordRoleColor(value);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color ?? colors.darkGray,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? colors.dirtyWhite : Colors.transparent,
            width: 2,
          ),
        ),
        child: color == null
            ? Icon(Icons.format_color_reset, size: 16, color: colors.gray)
            : (selected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.perm,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String perm;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  String get _label => perm
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final description = AccordPermission.description(perm);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: enabled ? (v) => onChanged(v) : null,
      title: Text(_label, style: theme.textTheme.bodyMedium),
      subtitle: description.isEmpty
          ? null
          : Text(
              description,
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
    );
  }
}
