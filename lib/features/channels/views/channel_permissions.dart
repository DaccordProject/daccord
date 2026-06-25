import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
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
    builder: (_) => _ChannelPermissionsDialog(spaceId: spaceId, channel: channel),
  );
}

/// The tri-state of a single permission within an overwrite: explicitly allowed,
/// explicitly denied, or inherited (neither list contains it).
enum _OverwriteState { allow, neutral, deny }

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

/// Permissions grouped into visual sections, matching the reference dialog.
const _permGroups = <({String label, List<String> perms})>[
  (
    label: 'General',
    perms: [
      'view_channel',
      'create_invites',
      'change_nickname',
      'manage_nicknames',
      'use_commands',
    ],
  ),
  (
    label: 'Text',
    perms: [
      'send_messages',
      'send_tts',
      'embed_links',
      'attach_files',
      'read_history',
      'mention_everyone',
      'use_external_emojis',
      'use_external_stickers',
      'add_reactions',
    ],
  ),
  (
    label: 'Threads',
    perms: ['manage_threads', 'create_threads', 'send_in_threads'],
  ),
  (
    label: 'Voice',
    perms: [
      'connect',
      'speak',
      'stream',
      'use_vad',
      'priority_speaker',
      'mute_members',
      'deafen_members',
      'move_members',
      'use_soundboard',
      'manage_soundboard',
    ],
  ),
  (
    label: 'Moderation',
    perms: [
      'kick_members',
      'ban_members',
      'moderate_members',
      'manage_messages',
      'manage_automod',
      'view_audit_log',
    ],
  ),
  (
    label: 'Administration',
    perms: [
      'administrator',
      'manage_channels',
      'manage_space',
      'manage_roles',
      'manage_webhooks',
      'manage_emojis',
      'manage_events',
    ],
  ),
];

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
      ref.read(accordMembersControllerProvider(widget.spaceId)) ??
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
              ? AccordPermissionOverwrite.fromJson(
                  item.cast<String, dynamic>())
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
          Map<String, Map<String, _OverwriteState>> src) =>
      {for (final e in src.entries) e.key: Map.of(e.value)};

  /// Materializes an all-inherit entry for [id] if it has none yet, so the
  /// editor can show rows for a role/member with no existing overwrite.
  void _ensureEntity(String? id, {String type = 'role'}) {
    if (id == null) return;
    _types.putIfAbsent(id, () => type);
    _data.putIfAbsent(id, () => {
          for (final p in AccordPermission.all()) p: _OverwriteState.neutral,
        });
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
    final payloads = <(String id, String type, List<String> allow, List<String> deny)>[];
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
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content:
            const Text('You have unsaved permission changes. Discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Color? _roleColor(String id) {
    final role = _roles.firstWhereOrNull((r) => r.id == id);
    return role == null ? null : accordRoleColor(role.color);
  }

  String _memberName(String id) =>
      accordMemberName(_members[id], fallback: id);

  Future<void> _addMemberOverwrite() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _MemberPickerDialog(
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
    // Rebuild when roles/members change.
    ref.watch(spacesControllerProvider);
    ref.watch(accordMembersControllerProvider(widget.spaceId));
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tryClose();
      },
      child: Dialog(
        backgroundColor: colors.foreground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title: 'Permissions: #${widget.channel.name ?? widget.channel.id}',
                onClose: _tryClose,
              ),
              Expanded(
                child: _loading
                    ? const LoadingView()
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 200,
                            child: _EntityListPane(
                              roles: _roles,
                              memberIds: _memberOverwriteIds,
                              selectedId: _selectedId,
                              roleColor: _roleColor,
                              memberName: _memberName,
                              onSelectRole: (id) => _select(id, 'role'),
                              onSelectMember: (id) => _select(id, 'user'),
                              onAddMember: _addMemberOverwrite,
                            ),
                          ),
                          VerticalDivider(width: 1, color: colors.background),
                          Expanded(
                            child: _selectedId == null
                                ? Center(
                                    child: Text(
                                      'Select a role or member',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  )
                                : _OverwriteEditorPane(
                                    key: ValueKey(_selectedId),
                                    data: _data[_selectedId] ?? const {},
                                    visiblePerms: _visiblePerms().toSet(),
                                    enabled: !_saving,
                                    onSet: _setPermission,
                                  ),
                          ),
                        ],
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: (saving || !canReset) ? null : onReset,
            child: const Text('Reset'),
          ),
          const SizedBox(width: 8),
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
    required this.roles,
    required this.memberIds,
    required this.selectedId,
    required this.roleColor,
    required this.memberName,
    required this.onSelectRole,
    required this.onSelectMember,
    required this.onAddMember,
  });

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
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      children: [
        for (final role in roles)
          _EntityRow(
            label: role.name,
            color: roleColor(role.id) ?? colors.dirtyWhite,
            icon: Icons.shield_outlined,
            selected: role.id == selectedId,
            onTap: () => onSelectRole(role.id),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
          child: Text(
            'MEMBERS',
            style: theme.textTheme.labelSmall!
                .copyWith(color: colors.gray, letterSpacing: 0.6),
          ),
        ),
        for (final id in memberIds)
          _EntityRow(
            label: memberName(id),
            color: colors.dirtyWhite,
            icon: Icons.person_outline,
            selected: id == selectedId,
            onTap: () => onSelectMember(id),
          ),
        _EntityRow(
          label: '+ Add Member',
          color: colors.primary,
          icon: Icons.add,
          selected: false,
          onTap: onAddMember,
        ),
      ],
    );
  }
}

class _EntityRow extends StatelessWidget {
  const _EntityRow({
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    return Material(
      color: selected ? colors.darkGray : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium!.copyWith(color: color),
                ),
              ),
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
    required this.onSet,
  });

  final Map<String, _OverwriteState> data;
  final Set<String> visiblePerms;
  final bool enabled;
  final void Function(String perm, _OverwriteState state) onSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in _permGroups)
            ..._buildGroup(context, theme, colors, group),
        ],
      ),
    );
  }

  List<Widget> _buildGroup(
    BuildContext context,
    ThemeData theme,
    BonfireThemeExtension colors,
    ({String label, List<String> perms}) group,
  ) {
    final perms = group.perms.where(visiblePerms.contains).toList();
    if (perms.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          group.label.toUpperCase(),
          style: theme.textTheme.labelSmall!
              .copyWith(color: colors.gray, letterSpacing: 0.6),
        ),
      ),
      for (final perm in perms)
        _PermissionRow(
          label: _label(perm),
          description: AccordPermission.description(perm),
          state: data[perm] ?? _OverwriteState.neutral,
          enabled: enabled,
          onChanged: (s) => onSet(perm, s),
        ),
    ];
  }

  static String _label(String perm) => perm
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.description,
    required this.state,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String description;
  final _OverwriteState state;
  final bool enabled;
  final ValueChanged<_OverwriteState> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
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
          const SizedBox(width: 4),
          _TriButton(
            icon: Icons.remove,
            color: colors.gray,
            selected: state == _OverwriteState.neutral,
            onTap: enabled ? () => onChanged(_OverwriteState.neutral) : null,
          ),
          const SizedBox(width: 4),
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

class _MemberPickerDialog extends StatefulWidget {
  const _MemberPickerDialog({required this.members});

  final List<AccordMember> members;

  @override
  State<_MemberPickerDialog> createState() => _MemberPickerDialogState();
}

class _MemberPickerDialogState extends State<_MemberPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final matches = widget.members
        .where((m) =>
            q.isEmpty || accordMemberName(m).toLowerCase().contains(q))
        .sortedBy((m) => accordMemberName(m).toLowerCase());

    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search members',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('No members',
                          style: theme.textTheme.bodyMedium),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final m in matches)
                          ListTile(
                            dense: true,
                            leading:
                                Icon(Icons.person_outline, color: colors.gray),
                            title: Text(accordMemberName(m)),
                            onTap: () => Navigator.of(context).pop(m.userId),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
