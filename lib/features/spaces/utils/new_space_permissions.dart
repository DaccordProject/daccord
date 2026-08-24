import 'package:accordkit/accordkit.dart';

/// Defensive client-side normalization for servers that still seed
/// `mention_everyone` onto a newly-created space's position-0 role.
///
/// Only the just-created [space] is touched; existing spaces are never
/// migrated. Current Accord servers already omit this permission by default,
/// making this a no-op against up-to-date instances.
Future<RestResult?> normalizeNewSpaceEveryoneRole(
  AccordClient client,
  AccordSpace space,
) async {
  AccordRole? everyone;
  for (final role in space.roles) {
    if (role.position == 0) {
      everyone = role;
      break;
    }
  }
  if (everyone == null ||
      !everyone.permissions.contains(AccordPermission.mentionEveryone)) {
    return null;
  }
  final permissions = everyone.permissions
      .where((permission) => permission != AccordPermission.mentionEveryone)
      .toList();
  return client.roles.update(space.id, everyone.id, {
    'permissions': permissions,
  });
}
