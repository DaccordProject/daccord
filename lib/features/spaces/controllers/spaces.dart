import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/list_ext.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'spaces.g.dart';

/// Holds the current user's space list — the left rail. Populated on gateway
/// ready (via `users.listSpaces()`) and kept in sync by space
/// create/update/delete gateway events. The Accord analogue of Bonfire's
/// `GuildsController`.
@Riverpod(keepAlive: true)
class SpacesController extends _$SpacesController {
  @override
  List<AccordSpace>? build() => null;

  void setSpaces(List<AccordSpace> spaces) => state = spaces;

  /// Inserts [space], or replaces it in place if already present.
  void upsertSpace(AccordSpace space) {
    state = (state ?? const <AccordSpace>[]).upsertById(space, (s) => s.id);
  }

  void removeSpace(String spaceId) {
    final current = state;
    if (current == null) return;
    state = current.removeById(spaceId, (s) => s.id);
  }

  /// Inserts or replaces a role within [spaceId]'s role list. Assigns a fresh
  /// `roles` list to the space so `select((s) => space.roles)` watchers rebuild.
  void upsertRole(String spaceId, AccordRole role) =>
      _mutateRoles(spaceId, (roles) {
        final index = roles.indexWhere((r) => r.id == role.id);
        if (index >= 0) {
          roles[index] = role;
        } else {
          roles.add(role);
        }
      });

  void removeRole(String spaceId, String roleId) =>
      _mutateRoles(spaceId, (roles) => roles.removeWhere((r) => r.id == roleId));

  /// Replaces [spaceId]'s entire role list (e.g. after a reorder).
  void setRoles(String spaceId, List<AccordRole> roles) =>
      _mutateRoles(spaceId, (current) {
        current
          ..clear()
          ..addAll(roles);
      });

  void _mutateRoles(String spaceId, void Function(List<AccordRole>) mutate) {
    final current = state;
    if (current == null) return;
    final index = current.indexWhere((s) => s.id == spaceId);
    if (index < 0) return;
    final space = current[index];
    final roles = [...space.roles];
    mutate(roles);
    space.roles = roles;
    state = [...current];
  }
}
