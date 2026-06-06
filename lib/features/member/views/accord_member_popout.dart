import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the member profile popout for [userId] within [spaceId] as a modal.
Future<void> showAccordMemberPopout(
  BuildContext context, {
  required String spaceId,
  required String userId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MemberPopout(spaceId: spaceId, userId: userId),
  );
}

/// Available timeout durations (label → seconds), mirroring the reference
/// client's `moderate_member_dialog`.
const _timeoutDurations = <(String, int)>[
  ('60 seconds', 60),
  ('5 minutes', 300),
  ('10 minutes', 600),
  ('1 hour', 3600),
  ('1 day', 86400),
  ('1 week', 604800),
];

class _MemberPopout extends ConsumerStatefulWidget {
  const _MemberPopout({required this.spaceId, required this.userId});

  final String spaceId;
  final String userId;

  @override
  ConsumerState<_MemberPopout> createState() => _MemberPopoutState();
}

class _MemberPopoutState extends ConsumerState<_MemberPopout> {
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  Future<void> _run(
    Future<RestResult> Function(AccordClient client) action, {
    String failure = 'Action failed',
    bool closeOnSuccess = false,
    VoidCallback? onSuccess,
  }) async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action(client);
    if (!mounted) return;
    if (result.ok) {
      onSuccess?.call();
      if (closeOnSuccess) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _busy = false);
    } else {
      setState(() {
        _busy = false;
        _error = result.error?.toString() ?? failure;
      });
    }
  }

  void _kick() {
    _run(
      (c) => c.members.kick(widget.spaceId, widget.userId),
      failure: 'Failed to kick member',
      closeOnSuccess: true,
      onSuccess: () => ref
          .read(accordMembersControllerProvider(widget.spaceId).notifier)
          .removeMember(widget.userId),
    );
  }

  Future<void> _ban() async {
    final confirmed = await _confirm(
      title: 'Ban member',
      message:
          'This member will be banned from the space and removed. Continue?',
      action: 'Ban',
    );
    if (confirmed != true) return;
    _run(
      (c) => c.bans.create(widget.spaceId, widget.userId),
      failure: 'Failed to ban member',
      closeOnSuccess: true,
      onSuccess: () => ref
          .read(accordMembersControllerProvider(widget.spaceId).notifier)
          .removeMember(widget.userId),
    );
  }

  void _timeout(int seconds) {
    final until = DateTime.now().toUtc().add(Duration(seconds: seconds));
    final iso = '${until.toIso8601String().split('.').first}Z';
    _run(
      (c) => c.members.update(
        widget.spaceId,
        widget.userId,
        {'communication_disabled_until': iso},
      ),
      failure: 'Failed to time out member',
    );
  }

  void _removeTimeout() {
    _run(
      (c) => c.members.update(
        widget.spaceId,
        widget.userId,
        {'communication_disabled_until': null},
      ),
      failure: 'Failed to remove timeout',
    );
  }

  /// Sets or clears [member]'s nickname. An empty value resets to the display
  /// name. Optimistically mirrors the result into the member cache.
  Future<void> _editNickname(AccordMember member) async {
    final controller = TextEditingController(text: member.nickname ?? '');
    final next = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nickname',
            hintText: 'Leave empty to reset to their display name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          if ((member.nickname ?? '').isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text('Reset'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next == null || !mounted) return;
    _run(
      (c) => c.members.update(
        widget.spaceId,
        widget.userId,
        {'nickname': next.isEmpty ? null : next},
      ),
      failure: 'Failed to update nickname',
      onSuccess: () {
        member.nickname = next.isEmpty ? null : next;
        ref
            .read(accordMembersControllerProvider(widget.spaceId).notifier)
            .upsertMember(member);
      },
    );
  }

  void _toggleRole(AccordMember member, AccordRole role, bool add) {
    _run(
      (c) => add
          ? c.members.addRole(widget.spaceId, widget.userId, role.id)
          : c.members.removeRole(widget.spaceId, widget.userId, role.id),
      failure: 'Failed to update roles',
      onSuccess: () {
        final roles = [...member.roles];
        if (add) {
          if (!roles.contains(role.id)) roles.add(role.id);
        } else {
          roles.remove(role.id);
        }
        member.roles = roles;
        ref
            .read(accordMembersControllerProvider(widget.spaceId).notifier)
            .upsertMember(member);
      },
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);

    final members = ref.watch(accordMembersControllerProvider(widget.spaceId));
    final member = members?[widget.userId];
    // Backfill the target from the on-demand user cache when outside the page.
    final cachedUser = ref.watch(
      accordUsersControllerProvider.select((m) => m[widget.userId]),
    );
    if (member == null && cachedUser == null && members != null) {
      ref.read(accordUsersControllerProvider.notifier).ensure(widget.userId);
    }

    final space = ref.watch(
      spacesControllerProvider
          .select((s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId)),
    );
    final roles = space?.roles ?? const <AccordRole>[];
    final status = ref.watch(
      presenceControllerProvider
          .select((p) => accordPresenceStatus(p, widget.userId)),
    );
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
          (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null),
    );
    final currentUserId = ref.watch(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.session.userId : null),
    );

    final name = member != null
        ? accordMemberName(member)
        : accordUserName(cachedUser, fallback: widget.userId);
    final username = member?.user?.username ?? cachedUser?.username;
    final avatarUrl = member != null
        ? accordMemberAvatarUrl(member, cdnUrl)
        : accordAvatarUrl(cachedUser, cdnUrl);
    final colorRole = member == null ? null : memberColorRole(member, roles);
    final nameColor = colorRole == null ? null : accordRoleColor(colorRole.color);

    final perms = accordEffectivePermissions(
      space: space,
      selfMember: currentUserId == null ? null : members?[currentUserId],
      roles: roles,
      currentUserId: currentUserId ?? '',
    );
    final isSelf = currentUserId != null && currentUserId == widget.userId;
    final canKick =
        !isSelf && accordHasPermission(perms, AccordPermission.kickMembers);
    final canBan =
        !isSelf && accordHasPermission(perms, AccordPermission.banMembers);
    final canTimeout =
        !isSelf && accordHasPermission(perms, AccordPermission.moderateMembers);
    final canManageRoles =
        accordHasPermission(perms, AccordPermission.manageRoles);
    final canEditNickname = isSelf
        ? accordHasPermission(perms, AccordPermission.changeNickname)
        : accordHasPermission(perms, AccordPermission.manageNicknames);
    final timedOut = member?.timedOutUntil != null &&
        member!.timedOutUntil.toString().isNotEmpty;

    // Roles assignable in the popout: skip @everyone (position 0) and managed.
    final assignableRoles = roles
        .where((r) => r.position != 0 && !r.managed)
        .sortedBy<num>((r) => -r.position);
    final memberRoleIds = member?.roles ?? const <String>[];

    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AccordMemberAvatar(
                    avatarUrl: avatarUrl,
                    initial: name.isEmpty ? '?' : name[0].toUpperCase(),
                    status: status,
                    radius: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleMedium!
                              .copyWith(color: nameColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (username != null)
                          Text('@$username',
                              style: theme.textTheme.bodySmall!
                                  .copyWith(color: colors.gray)),
                        Text(
                          _statusLabel(status),
                          style: theme.textTheme.bodySmall!
                              .copyWith(color: colors.gray),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (timedOut) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAA81A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 16, color: Color(0xFFFAA81A)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('Timed out until ${member.timedOutUntil}',
                            style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ],
              if (member != null && member.joinedAt.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Member since ${_date(member.joinedAt)}',
                    style:
                        theme.textTheme.bodySmall!.copyWith(color: colors.gray)),
              ],
              if (member != null && memberRoleIds.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('ROLES',
                    style: theme.textTheme.labelSmall!.copyWith(
                        color: colors.gray, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final id in memberRoleIds)
                      if (roles.firstWhereOrNull((r) => r.id == id)
                          case final role?)
                        _RoleChip(role: role),
                  ],
                ),
              ],
              if (canManageRoles && member != null && assignableRoles.isNotEmpty)
                _RoleEditor(
                  roles: assignableRoles,
                  memberRoleIds: memberRoleIds,
                  enabled: !_busy,
                  onToggle: (role, add) => _toggleRole(member, role, add),
                ),
              if (canEditNickname && member != null) ...[
                const SizedBox(height: 8),
                _ActionTile(
                  icon: Icons.badge_outlined,
                  label: (member.nickname ?? '').isEmpty
                      ? 'Set nickname'
                      : 'Edit nickname',
                  color: colors.dirtyWhite,
                  onTap: _busy ? null : () => _editNickname(member),
                ),
              ],
              if (canKick || canBan || canTimeout) ...[
                const SizedBox(height: 16),
                Divider(color: colors.background, height: 1),
                const SizedBox(height: 12),
                _ModerationActions(
                  canKick: canKick,
                  canBan: canBan,
                  canTimeout: canTimeout,
                  timedOut: timedOut,
                  busy: _busy,
                  onKick: _kick,
                  onBan: _ban,
                  onTimeout: _timeout,
                  onRemoveTimeout: _removeTimeout,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'online':
        return 'Online';
      case 'idle':
        return 'Idle';
      case 'dnd':
        return 'Do Not Disturb';
      default:
        return 'Offline';
    }
  }

  String _date(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final AccordRole role;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final color = accordRoleColor(role.color) ?? colors.dirtyWhite;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(role.name,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: colors.dirtyWhite)),
        ],
      ),
    );
  }
}

class _RoleEditor extends StatelessWidget {
  const _RoleEditor({
    required this.roles,
    required this.memberRoleIds,
    required this.enabled,
    required this.onToggle,
  });

  final List<AccordRole> roles;
  final List<String> memberRoleIds;
  final bool enabled;
  final void Function(AccordRole role, bool add) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text('ASSIGN ROLES',
            style: theme.textTheme.labelSmall!.copyWith(
                color: colors.gray, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final role in roles)
              FilterChip(
                label: Text(role.name),
                selected: memberRoleIds.contains(role.id),
                onSelected:
                    enabled ? (value) => onToggle(role, value) : null,
                showCheckmark: true,
              ),
          ],
        ),
      ],
    );
  }
}

class _ModerationActions extends StatelessWidget {
  const _ModerationActions({
    required this.canKick,
    required this.canBan,
    required this.canTimeout,
    required this.timedOut,
    required this.busy,
    required this.onKick,
    required this.onBan,
    required this.onTimeout,
    required this.onRemoveTimeout,
  });

  final bool canKick;
  final bool canBan;
  final bool canTimeout;
  final bool timedOut;
  final bool busy;
  final VoidCallback onKick;
  final VoidCallback onBan;
  final ValueChanged<int> onTimeout;
  final VoidCallback onRemoveTimeout;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canTimeout)
          PopupMenuButton<int>(
            enabled: !busy,
            tooltip: 'Time out',
            onSelected: onTimeout,
            itemBuilder: (context) => [
              for (final (label, seconds) in _timeoutDurations)
                PopupMenuItem(value: seconds, child: Text(label)),
            ],
            child: _ActionRow(
              icon: Icons.timer_outlined,
              label: 'Time out…',
              color: const Color(0xFFFAA81A),
            ),
          ),
        if (canTimeout && timedOut)
          _ActionTile(
            icon: Icons.timer_off_outlined,
            label: 'Remove timeout',
            color: colors.dirtyWhite,
            onTap: busy ? null : onRemoveTimeout,
          ),
        if (canKick)
          _ActionTile(
            icon: Icons.exit_to_app,
            label: 'Kick member',
            color: const Color(0xFFFAA81A),
            onTap: busy ? null : onKick,
          ),
        if (canBan)
          _ActionTile(
            icon: Icons.gavel,
            label: 'Ban member',
            color: colors.red,
            onTap: busy ? null : onBan,
          ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: _ActionRow(icon: icon, label: label, color: color),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label,
              style:
                  Theme.of(context).textTheme.bodyMedium!.copyWith(color: color)),
        ],
      ),
    );
  }
}
