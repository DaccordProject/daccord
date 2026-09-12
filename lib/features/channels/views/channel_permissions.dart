import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/views/channel_member_picker_dialog.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permission_catalog.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the per-channel permission overwrites editor for [channel]. Lets an
/// operator grant or deny specific permissions to individual roles or members,
/// layered on top of the space-wide role permissions. The Accord analogue of
/// Discord's channel permission overrides; mirrors the reference client's
/// `scenes/admin/channel_permissions_dialog.gd`.
Future<void> showChannelPermissionsDialog(
  BuildContext context, {
  required String spaceId,
  required AccordChannel channel,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _ChannelPermissionsDialog(spaceId: spaceId, channel: channel),
  );
}

/// The tri-state of a single permission within an overwrite: explicitly allowed,
/// explicitly denied, or inherited (neither list contains it).
enum _OverwriteState { allow, neutral, deny }

/// Below this many logical pixels the dialog stacks the role/member selector
/// above a full-width editor instead of placing them side by side (#328). Used
/// both for the body layout (via [LayoutBuilder]) and, against the screen
/// width, to let the dialog fill a phone instead of keeping desktop insets.
const _compactBreakpoint = 560.0;

/// Permissions only meaningful on voice channels — hidden for text/forum/etc.
const _voiceOnlyPerms = <String>{
  'connect',
  'speak',
  'mute_members',
  'deafen_members',
  'move_members',
  'use_vad',
  'priority_speaker',
  'stream',
};

/// Permissions only meaningful on text-like channels — hidden for voice.
const _textOnlyPerms = <String>{
  'send_messages',
  'send_tts',
  'manage_messages',
  'embed_links',
  'attach_files',
  'read_history',
  'mention_everyone',
  'use_external_emojis',
  'manage_threads',
  'create_threads',
  'use_external_stickers',
  'send_in_threads',
};

class _ChannelPermissionsDialog extends ConsumerStatefulWidget {
  const _ChannelPermissionsDialog({
    required this.spaceId,
    required this.channel,
  });

  final String spaceId;
  final AccordChannel channel;

  @override
  ConsumerState<_ChannelPermissionsDialog> createState() =>
      _ChannelPermissionsDialogState();
}

class _ChannelPermissionsDialogState
    extends ConsumerState<_ChannelPermissionsDialog> {
  /// entityId → (perm → state). Holds both role and member overwrites.
  final Map<String, Map<String, _OverwriteState>> _data = {};

  /// entityId → 'role' | 'user'.
  final Map<String, String> _types = {};

  /// IDs that carried an overwrite when the dialog opened (for delete-on-save).
  final List<String> _originalIds = [];

  /// Snapshot of [_data] at load time, for dirty tracking.
  Map<String, Map<String, _OverwriteState>> _originalData = {};

  String? _selectedId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.accordClient;

  List<AccordRole> get _roles {
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == widget.spaceId);
    final roles = [...?space?.roles];
    roles.sort((a, b) => b.position.compareTo(a.position));
    return roles;
  }

  Map<String, AccordMember> get _members =>
      ref.read(
        accordMembersControllerProvider(
          ref.readActiveServerKey() ?? '',
          widget.spaceId,
        ),
      ) ??
      const <String, AccordMember>{};

  Future<void> _load() async {
    final client = _client;
    if (client == null) {
      setState(() => _loading = false);
      return;
    }
    final result = await client.channels.listOverwrites(widget.channel.id);
    if (!mounted) return;
    final raw = result.data;
    final list = raw is List ? raw : const [];
    for (final item in list) {
      final overwrite = item is AccordPermissionOverwrite
          ? item
          : item is Map
          ? AccordPermissionOverwrite.fromJson(item.cast<String, dynamic>())
          : null;
      if (overwrite == null || overwrite.id.isEmpty) continue;
      _originalIds.add(overwrite.id);
      _types[overwrite.id] = overwrite.type; // fromJson normalizes member→user
      final perms = <String, _OverwriteState>{};
      for (final p in AccordPermission.all()) {
        if (overwrite.allow.contains(p)) {
          perms[p] = _OverwriteState.allow;
        } else if (overwrite.deny.contains(p)) {
          perms[p] = _OverwriteState.deny;
        } else {
          perms[p] = _OverwriteState.neutral;
        }
      }
      _data[overwrite.id] = perms;
    }
    _originalData = _deepCopy(_data);
    setState(() {
      _loading = false;
      _selectedId ??= _roles.firstOrNull?.id;
      _ensureEntity(_selectedId);
    });
  }

  static Map<String, Map<String, _OverwriteState>> _deepCopy(
    Map<String, Map<String, _OverwriteState>> src,
  ) => {for (final e in src.entries) e.key: Map.of(e.value)};

  /// Materializes an all-inherit entry for [id] if it has none yet, so the
  /// editor can show rows for a role/member with no existing overwrite.
  void _ensureEntity(String? id, {String type = 'role'}) {
    if (id == null) return;
    _types.putIfAbsent(id, () => type);
    _data.putIfAbsent(
      id,
      () => {
        for (final p in AccordPermission.all()) p: _OverwriteState.neutral,
      },
    );
  }

  void _select(String id, String type) {
    setState(() {
      _selectedId = id;
      _error = null;
      _ensureEntity(id, type: type);
    });
  }

  List<String> get _memberOverwriteIds =>
      _types.entries.where((e) => e.value == 'user').map((e) => e.key).toList();

  void _setPermission(String perm, _OverwriteState state) {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _ensureEntity(id, type: _types[id] ?? 'role');
      _data[id]![perm] = state;
    });
  }

  /// Resets the selected entity back to all-inherit (in memory; persisted on
  /// save, which deletes it server-side when it was an existing overwrite).
  void _resetSelected() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _data[id] = {
        for (final p in AccordPermission.all()) p: _OverwriteState.neutral,
      };
    });
  }

  List<String> _visiblePerms() {
    final all = AccordPermission.all();
    switch (widget.channel.type) {
      case 'voice':
        return all.where((p) => !_textOnlyPerms.contains(p)).toList();
      case 'text':
      case 'announcement':
      case 'forum':
        return all.where((p) => !_voiceOnlyPerms.contains(p)).toList();
      default:
        return all;
    }
  }

  bool _isDirty() {
    final ids = {..._data.keys, ..._originalData.keys};
    for (final id in ids) {
      for (final p in AccordPermission.all()) {
        final cur = _data[id]?[p] ?? _OverwriteState.neutral;
        final orig = _originalData[id]?[p] ?? _OverwriteState.neutral;
        if (cur != orig) return true;
      }
    }
    return false;
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    // Entities that still carry at least one allow/deny survive; the rest that
    // were originally present are deleted.
    final active = <String>[];
    final payloads =
        <(String id, String type, List<String> allow, List<String> deny)>[];
    for (final entry in _data.entries) {
      final allow = <String>[];
      final deny = <String>[];
      entry.value.forEach((perm, state) {
        if (state == _OverwriteState.allow) {
          allow.add(perm);
        } else if (state == _OverwriteState.deny) {
          deny.add(perm);
        }
      });
      if (allow.isEmpty && deny.isEmpty) continue;
      active.add(entry.key);
      // Server expects "member" for user overwrites.
      final type = _types[entry.key] == 'user' ? 'member' : 'role';
      payloads.add((entry.key, type, allow, deny));
    }

    String? err;
    // Delete overwrites that were reset to all-inherit.
    for (final id in _originalIds) {
      if (active.contains(id)) continue;
      final res = await client.channels.deleteOverwrite(widget.channel.id, id);
      if (!res.ok) {
        err = res.errorOr('Failed to update permissions');
        break;
      }
    }
    if (err == null) {
      for (final p in payloads) {
        final res = await client.channels.upsertOverwrite(
          widget.channel.id,
          p.$1,
          {'type': p.$2, 'allow': p.$3, 'deny': p.$4},
        );
        if (!res.ok) {
          err = res.errorOr('Failed to update permissions');
          break;
        }
      }
    }

    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = err;
      });
    }
  }

  Future<void> _tryClose() async {
    if (!_isDirty()) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showConfirmDialog(
      context,
      title: 'Unsaved Changes',
      message: 'You have unsaved permission changes. Discard them?',
      confirmLabel: 'Discard',
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Color? _roleColor(String id) {
    final role = _roles.firstWhereOrNull((r) => r.id == id);
    return role == null ? null : accordRoleColor(role.color);
  }

  String _memberName(String id) => accordMemberName(_members[id], fallback: id);

  Future<void> _addMemberOverwrite() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => ChannelMemberPickerDialog(
        members: _members.values
            .where((m) => _types[m.userId] != 'user')
            .toList(),
      ),
    );
    if (picked == null || !mounted) return;
    _select(picked, 'user');
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when this space's roles change — every role mutation assigns a
    // fresh `roles` list to the space (see SpacesController._mutateRoles), so
    // selecting the list identity catches all role changes without rebuilding
    // for unrelated spaces.
    ref.watch(
      spacesControllerProvider.select(
        (spaces) =>
            spaces?.firstWhereOrNull((s) => s.id == widget.spaceId)?.roles,
      ),
    );
    // Rebuild when a rendered member-overwrite name changes (member update or
    // user backfill), joined so select() compares by value. The build reads
    // nothing else from the cache; the watch also keeps the self-loading
    // member controller alive for the read-at-tap member picker.
    final memberIds = _memberOverwriteIds;
    ref.watch(
      accordMembersControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.spaceId,
      ).select(
        (members) => memberIds
            .map((id) => accordMemberName(members?[id], fallback: id))
            .join('\u0000'),
      ),
    );
    final colors = BonfireThemeExtension.of(context);
    // On a phone the default 40px dialog insets and the 560px height cap would
    // leave the stacked layout cramped; let it use (nearly) the whole screen.
    final phone = MediaQuery.sizeOf(context).width < _compactBreakpoint;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tryClose();
      },
      child: Dialog(
        backgroundColor: colors.foreground,
        insetPadding: phone ? const EdgeInsets.all(12) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: phone ? double.infinity : 560,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title:
                    'Permissions: #${widget.channel.name ?? widget.channel.id}',
                onClose: _tryClose,
              ),
              Expanded(
                child: _loading
                    ? const LoadingView()
                    : LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth < _compactBreakpoint
                            ? _buildCompactBody(colors)
                            : _buildWideBody(colors),
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: InlineError(_error!, centered: false),
                ),
              _Footer(
                colors: colors,
                saving: _saving,
                canReset: _selectedId != null,
                onReset: _resetSelected,
                onSave: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Desktop/tablet: fixed-width selector list beside the editor.
  Widget _buildWideBody(BonfireThemeExtension colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 200, child: _buildEntityPane(compact: false)),
        VerticalDivider(width: 1, color: colors.background),
        Expanded(child: _buildEditorPane(compact: false)),
      ],
    );
  }

  /// Phones: a horizontally scrolling strip of role/member chips above a
  /// full-width editor, so permission labels keep their room to wrap (#328).
  Widget _buildCompactBody(BonfireThemeExtension colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEntityPane(compact: true),
        Divider(height: 1, color: colors.background),
        Expanded(child: _buildEditorPane(compact: true)),
      ],
    );
  }

  Widget _buildEntityPane({required bool compact}) {
    return _EntityListPane(
      compact: compact,
      roles: _roles,
      memberIds: _memberOverwriteIds,
      selectedId: _selectedId,
      roleColor: _roleColor,
      memberName: _memberName,
      onSelectRole: (id) => _select(id, 'role'),
      onSelectMember: (id) => _select(id, 'user'),
      onAddMember: _addMemberOverwrite,
    );
  }

  Widget _buildEditorPane({required bool compact}) {
    if (_selectedId == null) {
      return Center(
        child: Text(
          'Select a role or member',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return _OverwriteEditorPane(
      key: ValueKey(_selectedId),
      data: _data[_selectedId] ?? const {},
      visiblePerms: _visiblePerms().toSet(),
      enabled: !_saving,
      compact: compact,
      onSet: _setPermission,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.background, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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

class _Footer extends StatelessWidget {
  const _Footer({
    required this.colors,
    required this.saving,
    required this.canReset,
    required this.onReset,
    required this.onSave,
  });

  final BonfireThemeExtension colors;
  final bool saving;
  final bool canReset;
  final VoidCallback onReset;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.background, width: 1)),
      ),
      // OverflowBar wraps Reset/Save onto two lines when large text scale
      // makes them too wide for a phone, instead of overflowing.
      child: OverflowBar(
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        overflowSpacing: 8,
        children: [
          TextButton(
            onPressed: (saving || !canReset) ? null : onReset,
            child: const Text('Reset'),
          ),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: Text(saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _EntityListPane extends StatelessWidget {
  const _EntityListPane({
    required this.compact,
    required this.roles,
    required this.memberIds,
    required this.selectedId,
    required this.roleColor,
    required this.memberName,
    required this.onSelectRole,
    required this.onSelectMember,
    required this.onAddMember,
  });

  /// Horizontal chip strip (narrow screens) instead of a vertical list.
  final bool compact;
  final List<AccordRole> roles;
  final List<String> memberIds;
  final String? selectedId;
  final Color? Function(String) roleColor;
  final String Function(String) memberName;
  final ValueChanged<String> onSelectRole;
  final ValueChanged<String> onSelectMember;
  final VoidCallback onAddMember;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final children = [
      for (final role in roles)
        _EntityRow(
          key: ValueKey('role-${role.id}'),
          compact: compact,
          label: role.name,
          color: roleColor(role.id) ?? colors.dirtyWhite,
          icon: Icons.shield_outlined,
          selected: role.id == selectedId,
          onTap: () => onSelectRole(role.id),
        ),
      if (compact)
        // The strip has no room for a section header; a thin rule separates
        // roles from members (the chip icons already tell them apart).
        Container(
          width: 1,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: colors.darkGray,
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
          child: Text(
            'MEMBERS',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              letterSpacing: 0.6,
            ),
          ),
        ),
      for (final id in memberIds)
        _EntityRow(
          key: ValueKey('member-$id'),
          compact: compact,
          label: memberName(id),
          color: colors.dirtyWhite,
          icon: Icons.person_outline,
          selected: id == selectedId,
          onTap: () => onSelectMember(id),
        ),
      _EntityRow(
        key: const ValueKey('add-member'),
        compact: compact,
        label: '+ Add Member',
        color: colors.primary,
        icon: Icons.add,
        selected: false,
        onTap: onAddMember,
      ),
    ];
    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              children[i],
            ],
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      children: children,
    );
  }
}

class _EntityRow extends StatefulWidget {
  const _EntityRow({
    super.key,
    this.compact = false,
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  /// Renders as a self-sized chip (for the horizontal strip) instead of a
  /// full-width list row.
  final bool compact;
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_EntityRow> createState() => _EntityRowState();
}

class _EntityRowState extends State<_EntityRow> {
  @override
  void initState() {
    super.initState();
    if (widget.selected) _reveal();
  }

  @override
  void didUpdateWidget(_EntityRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  /// Scrolls this row into view once it becomes the selection — matters for
  /// the compact strip, where "+ Add Member" appends the new chip off-screen.
  /// Only on selection change, so it never fights the user's own scrolling.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 150),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final compact = widget.compact;
    final selected = widget.selected;
    final color = widget.color;
    final radius = BorderRadius.circular(compact ? 20 : 8);
    final text = Text(
      widget.label,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium!.copyWith(color: color),
    );
    return Material(
      color: selected ? colors.darkGray : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        // Unselected chips need an outline to read as tappable in the strip.
        side: compact
            ? BorderSide(color: selected ? color : colors.darkGray)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: widget.onTap,
        child: Padding(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Icon(widget.icon, size: 16, color: color),
              SizedBox(width: compact ? 8 : 10),
              if (compact)
                // Long role names must not stretch the strip; cap the chip.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: text,
                )
              else
                Expanded(child: text),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverwriteEditorPane extends StatelessWidget {
  const _OverwriteEditorPane({
    super.key,
    required this.data,
    required this.visiblePerms,
    required this.enabled,
    this.compact = false,
    required this.onSet,
  });

  final Map<String, _OverwriteState> data;
  final Set<String> visiblePerms;
  final bool enabled;

  /// Tighter margins and finger-sized tri-state buttons (narrow screens).
  final bool compact;
  final void Function(String perm, _OverwriteState state) onSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return SingleChildScrollView(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 8, 12, 16)
          : const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in accordPermissionGroups)
            ..._buildGroup(context, theme, colors, group),
        ],
      ),
    );
  }

  List<Widget> _buildGroup(
    BuildContext context,
    ThemeData theme,
    BonfireThemeExtension colors,
    ({String label, List<String> permissions}) group,
  ) {
    final perms = group.permissions.where(visiblePerms.contains).toList();
    if (perms.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          group.label.toUpperCase(),
          style: theme.textTheme.labelSmall!.copyWith(
            color: colors.gray,
            letterSpacing: 0.6,
          ),
        ),
      ),
      for (final perm in perms)
        _PermissionRow(
          label: accordPermissionLabel(perm),
          description: AccordPermission.description(perm),
          state: data[perm] ?? _OverwriteState.neutral,
          enabled: enabled,
          compact: compact,
          onChanged: (s) => onSet(perm, s),
        ),
    ];
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.description,
    required this.state,
    required this.enabled,
    this.compact = false,
    required this.onChanged,
  });

  final String label;
  final String description;
  final _OverwriteState state;
  final bool enabled;

  /// Finger-sized (40px) tri-state buttons for touch screens.
  final bool compact;
  final ValueChanged<_OverwriteState> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final gap = SizedBox(width: compact ? 6 : 4);
    // The label wraps freely while the three buttons keep their fixed size;
    // the pane is full-width on phones so the text is never squeezed into a
    // letter-per-line column (#328).
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 6 : 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          SizedBox(width: compact ? 12 : 8),
          _TriButton(
            icon: Icons.check,
            color: colors.green,
            compact: compact,
            selected: state == _OverwriteState.allow,
            onTap: enabled
                ? () => onChanged(
                    state == _OverwriteState.allow
                        ? _OverwriteState.neutral
                        : _OverwriteState.allow,
                  )
                : null,
          ),
          gap,
          _TriButton(
            icon: Icons.remove,
            color: colors.gray,
            compact: compact,
            selected: state == _OverwriteState.neutral,
            onTap: enabled ? () => onChanged(_OverwriteState.neutral) : null,
          ),
          gap,
          _TriButton(
            icon: Icons.close,
            color: colors.red,
            compact: compact,
            selected: state == _OverwriteState.deny,
            onTap: enabled
                ? () => onChanged(
                    state == _OverwriteState.deny
                        ? _OverwriteState.neutral
                        : _OverwriteState.deny,
                  )
                : null,
          ),
        ],
      ),
    );
    return description.isEmpty
        ? row
        : Tooltip(message: description, child: row);
  }
}

class _TriButton extends StatelessWidget {
  const _TriButton({
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  /// 40px touch target instead of the 30x28 desktop button.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: compact ? 40 : 30,
        height: compact ? 40 : 28,
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
