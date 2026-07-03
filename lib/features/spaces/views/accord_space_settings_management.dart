part of 'accord_space_settings.dart';

/// "Membership" section: the change-your-nickname tile.
class _MembershipSection extends StatelessWidget {
  const _MembershipSection({required this.onEditNickname});

  final VoidCallback onEditNickname;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Membership'),
        ListTile(
          leading: Icon(Icons.badge_outlined, color: colors.dirtyWhite),
          title: const Text('Change your nickname'),
          subtitle: const Text('How you appear in this space'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onEditNickname,
        ),
      ],
    );
  }
}

/// "Management" section: permission-gated tiles that open the roles, audit
/// log, ban list, reports, emoji, and soundboard screens.
class _ManagementSection extends StatelessWidget {
  const _ManagementSection({
    required this.spaceId,
    required this.canManageRoles,
    required this.canViewAuditLog,
    required this.canModerate,
    required this.canManageEmojis,
    required this.canUseSoundboard,
    required this.canManageSoundboard,
  });

  final String spaceId;
  final bool canManageRoles;
  final bool canViewAuditLog;
  final bool canModerate;
  final bool canManageEmojis;
  final bool canUseSoundboard;
  final bool canManageSoundboard;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Management'),
        if (canManageRoles)
          ListTile(
            leading: Icon(Icons.shield_outlined, color: colors.dirtyWhite),
            title: const Text('Roles'),
            subtitle: const Text('Create, edit, and order roles'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccordRoleManagement(context, spaceId: spaceId),
          ),
        if (canViewAuditLog)
          ListTile(
            leading: Icon(Icons.history, color: colors.dirtyWhite),
            title: const Text('Audit log'),
            subtitle: const Text('Recent moderation and admin actions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccordAuditLog(context, spaceId: spaceId),
          ),
        if (canModerate) ...[
          ListTile(
            leading: Icon(Icons.gavel, color: colors.dirtyWhite),
            title: const Text('Banned members'),
            subtitle: const Text('Review and unban members'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccordBanList(context, spaceId: spaceId),
          ),
          ListTile(
            leading: Icon(Icons.flag_outlined, color: colors.dirtyWhite),
            title: const Text('Reports'),
            subtitle: const Text('Review and resolve member reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showReportsPanel(context, spaceId: spaceId),
          ),
        ],
        if (canManageEmojis)
          ListTile(
            leading: Icon(
              Icons.emoji_emotions_outlined,
              color: colors.dirtyWhite,
            ),
            title: const Text('Custom emoji'),
            subtitle: const Text('Upload, rename, and delete emoji'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccordEmojiManagement(context, spaceId: spaceId),
          ),
        if (canUseSoundboard)
          ListTile(
            leading: Icon(Icons.graphic_eq, color: colors.dirtyWhite),
            title: const Text('Soundboard'),
            subtitle: const Text('Play and manage soundboard clips'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAccordSoundboard(
              context,
              spaceId: spaceId,
              canManage: canManageSoundboard,
            ),
          ),
      ],
    );
  }
}

/// "Danger zone" section (owner only): transfer ownership and delete space.
class _DangerZoneSection extends StatelessWidget {
  const _DangerZoneSection({
    required this.spaceId,
    required this.busy,
    required this.onDeleteSpace,
  });

  final String spaceId;
  final bool busy;
  final VoidCallback onDeleteSpace;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Danger zone'),
        ListTile(
          leading: Icon(Icons.swap_horiz, color: colors.dirtyWhite),
          title: const Text('Transfer ownership'),
          subtitle: const Text('Hand this space to another member'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showTransferOwnership(context, spaceId: spaceId),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever, color: colors.red),
          title: Text('Delete space', style: TextStyle(color: colors.red)),
          subtitle: const Text('Permanently remove this space'),
          onTap: busy ? null : onDeleteSpace,
        ),
      ],
    );
  }
}
