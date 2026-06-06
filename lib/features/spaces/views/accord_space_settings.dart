import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/space.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_audit_log.dart';
import 'package:bonfire/features/spaces/views/accord_ban_list.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/features/spaces/views/accord_role_management.dart';
import 'package:bonfire/features/spaces/views/accord_soundboard.dart';
import 'package:bonfire/features/spaces/views/accord_transfer_ownership.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the space settings dialog for [spaceId] (banner + roles). Sections are
/// permission-gated: the banner editor needs `manage_space`, the roles entry
/// needs `manage_roles`.
Future<void> showAccordSpaceSettings(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SpaceSettings(spaceId: spaceId),
  );
}

/// Resolves a space's `banner` reference to an absolute CDN URL, or null when
/// unset. The field is either a bare asset hash or a server-relative/absolute
/// path; both are handled (mirrors [accordMemberAvatarUrl]).
String? accordSpaceBannerUrl(AccordSpace space, String? cdnUrl) {
  final banner = space.banner;
  if (banner is! String || banner.isEmpty) return null;
  final cdn = cdnUrl ?? '';
  if (banner.contains('/') || banner.startsWith('http')) {
    return AccordCDN.resolvePath(banner, cdnUrl: cdn);
  }
  return AccordCDN.spaceBanner(space.id, banner,
      format: AccordCDN.autoFormat(banner), cdnUrl: cdn);
}

class _SpaceSettings extends ConsumerStatefulWidget {
  const _SpaceSettings({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_SpaceSettings> createState() => _SpaceSettingsState();
}

class _SpaceSettingsState extends ConsumerState<_SpaceSettings> {
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  Set<String> _perms() {
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == widget.spaceId);
    final currentUserId = ref.read(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.session.userId : null),
    );
    final isAdmin = ref.read(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.session.isAdmin : false),
    );
    final members = ref.read(accordMembersControllerProvider(widget.spaceId));
    return accordEffectivePermissions(
      space: space,
      selfMember: currentUserId == null ? null : members?[currentUserId],
      roles: space?.roles ?? const <AccordRole>[],
      currentUserId: currentUserId ?? '',
      currentUserIsAdmin: isAdmin,
    );
  }

  Future<void> _update(Map<String, dynamic> body, String failure) async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.spaces.update(widget.spaceId, body);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) _error = result.error?.toString() ?? failure;
    });
    final space = result.data;
    if (result.ok && space is AccordSpace) {
      ref.read(spacesControllerProvider.notifier).upsertSpace(space);
      ref.read(spaceControllerProvider(space.id).notifier).setSpace(space);
    }
  }

  Future<void> _pickBanner() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null) return;
    final dataUri = AccordCDN.buildDataUri(file!.bytes!, file.name);
    await _update({'banner': dataUri}, 'Failed to update banner');
  }

  Future<void> _removeBanner() =>
      _update({'banner': null}, 'Failed to remove banner');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final space = ref.watch(
      spacesControllerProvider
          .select((s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId)),
    );
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
          (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null),
    );
    final perms = _perms();
    final canManageSpace =
        accordHasPermission(perms, AccordPermission.manageSpace);
    final canManageRoles =
        accordHasPermission(perms, AccordPermission.manageRoles);
    final canViewAuditLog =
        accordHasPermission(perms, AccordPermission.viewAuditLog);
    final currentUserId = ref.watch(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.session.userId : null));
    final isOwner = space != null &&
        currentUserId != null &&
        space.ownerId == currentUserId;
    final canModerate =
        accordHasPermission(perms, AccordPermission.banMembers);
    final canUseSoundboard =
        accordHasPermission(perms, AccordPermission.useSoundboard);
    final canManageSoundboard =
        accordHasPermission(perms, AccordPermission.manageSoundboard);
    final bannerUrl = space == null ? null : accordSpaceBannerUrl(space, cdnUrl);

    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(space?.name ?? 'Space settings',
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: colors.gray),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('BANNER',
                  style: theme.textTheme.labelSmall!.copyWith(
                      color: colors.gray, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 130,
                  width: double.infinity,
                  color: colors.darkGray,
                  child: bannerUrl == null
                      ? Center(
                          child: Icon(Icons.image_outlined,
                              color: colors.gray, size: 32),
                        )
                      : CachedNetworkImage(
                          imageUrl: bannerUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: colors.gray),
                          ),
                        ),
                ),
              ),
              if (canManageSpace) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _pickBanner,
                      icon: const Icon(Icons.upload, size: 18),
                      label: Text(bannerUrl == null ? 'Upload' : 'Change'),
                    ),
                    const SizedBox(width: 8),
                    if (bannerUrl != null)
                      TextButton(
                        onPressed: _busy ? null : _removeBanner,
                        style:
                            TextButton.styleFrom(foregroundColor: colors.red),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('You need Manage Space to edit the banner.',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.gray)),
                ),
              if (canManageRoles) ...[
                const SizedBox(height: 16),
                Divider(height: 1, color: colors.background),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.shield_outlined, color: colors.dirtyWhite),
                  title: const Text('Roles'),
                  subtitle: Text('Create, edit, and order roles',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.gray)),
                  trailing:
                      Icon(Icons.chevron_right, color: colors.gray),
                  onTap: () {
                    Navigator.of(context).pop();
                    showAccordRoleManagement(context, spaceId: widget.spaceId);
                  },
                ),
              ],
              if (canViewAuditLog) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history, color: colors.dirtyWhite),
                  title: const Text('Audit log'),
                  subtitle: Text('Recent moderation and admin actions',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.gray)),
                  trailing: Icon(Icons.chevron_right, color: colors.gray),
                  onTap: () {
                    Navigator.of(context).pop();
                    showAccordAuditLog(context, spaceId: widget.spaceId);
                  },
                ),
              ],
              if (canModerate) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.gavel, color: colors.dirtyWhite),
                  title: const Text('Banned members'),
                  subtitle: Text('Review and unban members',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.gray)),
                  trailing: Icon(Icons.chevron_right, color: colors.gray),
                  onTap: () {
                    Navigator.of(context).pop();
                    showAccordBanList(context, spaceId: widget.spaceId);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.flag_outlined, color: colors.dirtyWhite),
                  title: const Text('Reports'),
                  subtitle: Text('Review and resolve member reports',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.gray)),
                  trailing: Icon(Icons.chevron_right, color: colors.gray),
                  onTap: () {
                    Navigator.of(context).pop();
                    showReportsPanel(context, spaceId: widget.spaceId);
                  },
                ),
              ],
              if (isOwner) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.swap_horiz, color: colors.dirtyWhite),
                  title: const Text('Transfer ownership'),
                  subtitle: Text('Hand this space to another member',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.gray)),
                  trailing: Icon(Icons.chevron_right, color: colors.gray),
                  onTap: () {
                    Navigator.of(context).pop();
                    showTransferOwnership(context, spaceId: widget.spaceId);
                  },
                ),
              ],
              if (canUseSoundboard) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.graphic_eq, color: colors.dirtyWhite),
                  title: const Text('Soundboard'),
                  subtitle: Text('Play and manage soundboard clips',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: colors.gray)),
                  trailing: Icon(Icons.chevron_right, color: colors.gray),
                  onTap: () {
                    Navigator.of(context).pop();
                    showAccordSoundboard(context,
                        spaceId: widget.spaceId,
                        canManage: canManageSoundboard);
                  },
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
}
