import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/spaces/controllers/role_preview.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Computes the current user's effective space-level permissions, mirroring the
/// reference client's `client_permissions.gd`:
///
/// - instance admins and the space owner get everything;
/// - otherwise permissions are the union of the `@everyone` role (position 0)
///   and the user's assigned roles;
/// - the `administrator` permission implies all others (see [accordHasPermission]).
///
/// Channel-level permission overwrites are not modeled here (space-level checks
/// are all the moderation UI needs).
/// When [previewRoleId] is set, permissions are computed as a plain member who
/// holds only that role (plus `@everyone`), ignoring the admin/owner bypass —
/// this drives the "preview as role" (imposter) mode.
Set<String> accordEffectivePermissions({
  required AccordSpace? space,
  required AccordMember? selfMember,
  required List<AccordRole> roles,
  required String currentUserId,
  bool currentUserIsAdmin = false,
  String? previewRoleId,
}) {
  final previewing = previewRoleId != null;
  if (!previewing) {
    if (currentUserIsAdmin) return {AccordPermission.administrator};
    if (space != null &&
        currentUserId.isNotEmpty &&
        space.ownerId == currentUserId) {
      return {AccordPermission.administrator};
    }
  }

  final myRoleIds = previewing
      ? <String>{previewRoleId}
      : (selfMember?.roles.toSet() ?? const <String>{});
  final perms = <String>{};
  for (final role in roles) {
    final isEveryone = role.position == 0;
    if (isEveryone || myRoleIds.contains(role.id)) {
      for (final p in role.permissions) {
        perms.add(p.toString());
      }
    }
  }
  return perms;
}

/// Builds the active user's permission context from its authoritative
/// providers. Keeping admin and role-preview handling here prevents UI
/// call-sites from drifting as new permission gates are added.
extension AccordPermissionWidgetRef on WidgetRef {
  Set<String> watchAccordPermissions(AccordSpace? space, String spaceId) {
    final currentUserId = watchUserId();
    final members = watch(accordMembersControllerProvider(spaceId));
    final preview = watch(rolePreviewControllerProvider);
    return accordEffectivePermissions(
      space: space,
      selfMember: currentUserId == null ? null : members?[currentUserId],
      roles: space?.roles ?? const <AccordRole>[],
      currentUserId: currentUserId ?? '',
      currentUserIsAdmin: watchIsAdmin(),
      previewRoleId: preview?.spaceId == spaceId ? preview?.roleId : null,
    );
  }

  Set<String> readAccordPermissions(AccordSpace? space, String spaceId) {
    final currentUserId = readUserId();
    final members = read(accordMembersControllerProvider(spaceId));
    final preview = read(rolePreviewControllerProvider);
    return accordEffectivePermissions(
      space: space,
      selfMember: currentUserId == null ? null : members?[currentUserId],
      roles: space?.roles ?? const <AccordRole>[],
      currentUserId: currentUserId ?? '',
      currentUserIsAdmin: readIsAdmin(),
      previewRoleId: preview?.spaceId == spaceId ? preview?.roleId : null,
    );
  }
}

/// Whether [perms] grants [perm], honoring the `administrator` override.
bool accordHasPermission(Set<String> perms, String perm) =>
    perms.contains(AccordPermission.administrator) || perms.contains(perm);

/// Whether [perms] should reveal the space settings affordance: any of
/// manage-space, manage-roles or view-audit-log. The gate shared by the space
/// header menu and the channel list's settings gear.
bool canManageSpaceSettings(Set<String> perms) =>
    accordHasPermission(perms, AccordPermission.manageSpace) ||
    accordHasPermission(perms, AccordPermission.manageRoles) ||
    accordHasPermission(perms, AccordPermission.viewAuditLog);

/// A sentinel "above everyone" position returned for instance admins and the
/// space owner, so hierarchy checks treat them as outranking every real role.
const int kAccordMaxRolePosition = 999999;

/// The current user's highest role position in [space], used for role/member
/// hierarchy enforcement (a user may only act on roles strictly below this).
/// Instance admins, the space owner, and holders of an `administrator` role all
/// return [kAccordMaxRolePosition].
int accordMyHighestRolePosition({
  required AccordSpace? space,
  required AccordMember? selfMember,
  required List<AccordRole> roles,
  required String currentUserId,
  bool currentUserIsAdmin = false,
  String? previewRoleId,
}) {
  final previewing = previewRoleId != null;
  if (!previewing) {
    if (currentUserIsAdmin) return kAccordMaxRolePosition;
    if (space != null &&
        currentUserId.isNotEmpty &&
        space.ownerId == currentUserId) {
      return kAccordMaxRolePosition;
    }
  }
  final myRoleIds = previewing
      ? <String>{previewRoleId}
      : (selfMember?.roles.toSet() ?? const <String>{});
  var highest = 0;
  var hasAdmin = false;
  for (final role in roles) {
    if (!myRoleIds.contains(role.id)) continue;
    if (role.position > highest) highest = role.position;
    if (role.permissions
        .map((p) => p.toString())
        .contains(AccordPermission.administrator)) {
      hasAdmin = true;
    }
  }
  return hasAdmin ? kAccordMaxRolePosition : highest;
}
