part of 'accord_home.dart';

/// The mute / invite / settings / leave entries shared by the standalone-space
/// menu and the folder-member menu. Gated on the space's own connection session,
/// so actions hit the right server even when it isn't the active one.
List<AccordMenuEntry> _serverActionEntries(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey,
) {
  final conn = ref.read(connectionsControllerProvider).connectionFor(serverKey);
  final session = conn?.session;
  final userId = session?.userId;
  final members = ref.read(accordMembersControllerProvider(space.id));
  final preview = ref.read(rolePreviewControllerProvider);
  final perms = accordEffectivePermissions(
    space: space,
    selfMember: userId == null ? null : members?[userId],
    roles: space.roles,
    currentUserId: userId ?? '',
    currentUserIsAdmin: session?.isAdmin ?? false,
    previewRoleId: preview?.spaceId == space.id ? preview?.roleId : null,
  );
  final canInvite = accordHasPermission(perms, AccordPermission.createInvites);
  final canManage = canManageSpaceSettings(perms);
  final isOwner = userId != null && space.ownerId == userId;
  final settingsCtl = ref.read(settingsControllerProvider.notifier);
  final muted = ref.read(settingsControllerProvider).isSpaceMuted(space.id);
  return [
    AccordMenuEntry(
      label: muted ? 'Unmute server' : 'Mute server',
      icon: muted
          ? Icons.notifications_active_outlined
          : Icons.notifications_off_outlined,
      subtitle: muted ? null : 'Silence notifications from this server',
      onSelected: () => settingsCtl.toggleSpaceMuted(space.id),
    ),
    if (canInvite)
      AccordMenuEntry(
        label: 'Copy server link',
        icon: Icons.link_outlined,
        onSelected: () => _copyServerLink(context, ref, space, serverKey),
      ),
    if (canInvite)
      AccordMenuEntry(
        label: 'Invite people',
        icon: Icons.person_add_outlined,
        onSelected: () => showAccordInvites(context, spaceId: space.id),
      ),
    if (canManage)
      AccordMenuEntry(
        label: 'Space settings',
        icon: Icons.settings_outlined,
        onSelected: () => showAccordSpaceSettings(context, spaceId: space.id),
      ),
    AccordMenuEntry(
      label: 'Hide from list',
      icon: Icons.visibility_off_outlined,
      subtitle: 'Remove from your rail without leaving',
      onSelected: () => settingsCtl.setSpaceHidden(space.id, true),
    ),
    AccordMenuEntry(
      label: 'Leave server',
      icon: Icons.logout,
      destructive: !isOwner,
      enabled: !isOwner,
      subtitle: isOwner ? 'Transfer ownership before leaving.' : null,
      onSelected: isOwner ? null : () => _leaveSpace(context, ref, space, serverKey),
    ),
    AccordMenuEntry(
      label: 'Leave & delete data',
      icon: Icons.delete_forever_outlined,
      destructive: !isOwner,
      enabled: !isOwner,
      subtitle:
          isOwner ? null : 'Permanently delete your messages & data here',
      onSelected:
          isOwner ? null : () => _leaveAndDeleteSpace(context, ref, space, serverKey),
    ),
    AccordMenuEntry(
      label: 'Remove server',
      icon: Icons.link_off,
      destructive: true,
      subtitle: 'Disconnect & remove from this app — works even when offline',
      onSelected: () => _removeServer(context, ref, serverKey),
    ),
    const AccordMenuEntry.divider(),
  ];
}

/// Removes the whole server *connection* that hosts a space from this app,
/// purely locally: it disposes the client and clears the saved credentials,
/// the rail entry, open tabs, unread state and the cached space list. Unlike
/// [_leaveSpace] it makes no network call, so it works for a server you can no
/// longer reach. A connection can host several spaces, so this removes all of
/// them on that host; nothing is deleted server-side.
Future<void> _removeServer(
  BuildContext context,
  WidgetRef ref,
  String serverKey,
) async {
  final conn = ref.read(connectionsControllerProvider).connectionFor(serverKey);
  if (conn == null) return;
  final server = conn.session.server;
  final label =
      (server.name?.isNotEmpty ?? false) ? server.name! : server.homeDomain;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("Remove '$label'?"),
      content: const Text(
        'This disconnects your account and removes the server from this app, '
        'including any of its spaces. Nothing is deleted on the server, and you '
        'can add it back later with its address or an invite.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(accordAuthProvider.notifier).removeAccount(conn.session);
  messenger?.showSnackBar(SnackBar(content: Text("Removed '$label'")));
}

/// Copies a shareable invite link for [space] to the clipboard, reusing an
/// existing invite when one exists or minting a default 7-day one otherwise.
/// Gated on `createInvites` by the caller. The quick equivalent of opening the
/// full invite dialog just to copy a link.
Future<void> _copyServerLink(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey,
) async {
  final conn = ref.read(connectionsControllerProvider).connectionFor(serverKey);
  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  final baseUrl = conn?.session.server.baseUrl;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (client == null) return;

  String? code;
  final existing = await client.invites.listSpace(space.id);
  final existingData = existing.data;
  if (existing.ok && existingData is List) {
    final invites = existingData.whereType<AccordInvite>().toList();
    if (invites.isNotEmpty) code = invites.first.code;
  }
  if (code == null) {
    final created = await client.invites.createSpace(
      space.id,
      data: {'max_age': 604800, 'max_uses': 0, 'temporary': false},
    );
    final createdData = created.data;
    if (created.ok && createdData is AccordInvite) {
      code = createdData.code;
    } else if (created.ok) {
      // Some servers return no body on create; refetch to recover the code.
      final refetch = await client.invites.listSpace(space.id);
      final refetchData = refetch.data;
      if (refetch.ok && refetchData is List) {
        final invites = refetchData.whereType<AccordInvite>().toList();
        if (invites.isNotEmpty) code = invites.first.code;
      }
    }
  }
  if (code == null) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not create an invite link')),
    );
    return;
  }
  final link = baseUrl == null ? code : '$baseUrl/invite/$code';
  await Clipboard.setData(ClipboardData(text: link));
  messenger?.showSnackBar(
    const SnackBar(content: Text('Server link copied')),
  );
}

/// Confirms then leaves [space] *and deletes all the user's data* on its own
/// connection (`deleteData: true`). The destructive sibling of [_leaveSpace],
/// surfaced from the space menu as well as Privacy & Data. Owner-guarded by the
/// caller (the tile is disabled for owners).
Future<void> _leaveAndDeleteSpace(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Leave & delete data'),
      content: Text(
        "This will permanently leave '${space.name}' and delete all your "
        'messages, reactions, and data from this server. Your account stays '
        'active. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Leave & delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  if (client == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await client.members.leaveMe(space.id, deleteData: true);
  if (!result.ok) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Failed to leave: ${result.errorOr('unknown error')}')),
    );
    return;
  }
  ref
      .read(connectionsControllerProvider.notifier)
      .removeSpace(serverKey, space.id);
  ref.read(spacesControllerProvider.notifier).removeSpace(space.id);
  messenger?.showSnackBar(
    SnackBar(content: Text("Left '${space.name}' and deleted your data")),
  );
}

/// Confirms then leaves [space] on its own connection, without deleting any
/// data. Drops the space from both the connection cache and the active list on
/// success.
Future<void> _leaveSpace(
  BuildContext context,
  WidgetRef ref,
  AccordSpace space,
  String serverKey,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("Leave '${space.name}'?"),
      content: const Text(
        'You will lose access to this server until you rejoin with an '
        'invite. Your messages stay on the server.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  if (client == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await client.members.leaveMe(space.id);
  if (!result.ok) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Failed to leave: ${result.errorOr('unknown error')}')),
    );
    return;
  }
  ref
      .read(connectionsControllerProvider.notifier)
      .removeSpace(serverKey, space.id);
  ref.read(spacesControllerProvider.notifier).removeSpace(space.id);
  messenger?.showSnackBar(SnackBar(content: Text("Left '${space.name}'")));
}
