import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'role_preview.g.dart';

/// An active "preview as role" session: the admin/owner is viewing the UI with
/// the permission set of [roleId] in [spaceId], as a plain member would. Ports
/// the reference client's imposter mode (`AppState.imposter_*`).
class RolePreview {
  const RolePreview({
    required this.spaceId,
    required this.roleId,
    required this.roleName,
  });

  final String spaceId;
  final String roleId;
  final String roleName;
}

/// Holds the active role preview (null when not previewing). Permission checks
/// read this to gate the UI as the previewed role, and the preview banner reads
/// it to show the exit control. App-wide (keepAlive) so it survives navigation.
@Riverpod(keepAlive: true)
class RolePreviewController extends _$RolePreviewController {
  @override
  RolePreview? build() => null;

  void enter(RolePreview preview) => state = preview;

  void exit() => state = null;

  /// The role id being previewed for [spaceId], or null when not previewing
  /// that space. Passed to `accordEffectivePermissions` / `…HighestRolePosition`.
  String? roleIdFor(String? spaceId) =>
      (state != null && spaceId != null && state!.spaceId == spaceId)
      ? state!.roleId
      : null;
}
