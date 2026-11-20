import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/new_space_permissions.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Longest space name the server accepts.
const maxSpaceNameLength = 100;

/// Whether the active account may create spaces. Any signed-in account can:
/// the server makes the creator the owner, with full control of the space.
/// Guest sessions are read-only.
bool canCreateSpaces(AccordAuthState state) =>
    state is AccordAuthLoggedIn && !state.session.isGuest;

/// Creates a space named [name] on the active connection and shows it in the
/// rail straight away. Returns the new space, or a human-readable error.
Future<({AccordSpace? space, String? error})> createOwnedSpace(
  WidgetRef ref,
  String name,
) async {
  final auth = ref.read(accordAuthProvider);
  if (!canCreateSpaces(auth)) {
    return (space: null, error: 'Sign in to a server to create a space');
  }
  final session = (auth as AccordAuthLoggedIn).session;
  final client = auth.client;
  final trimmed = name.trim();
  if (trimmed.isEmpty) return (space: null, error: 'Enter a space name');
  if (trimmed.length > maxSpaceNameLength) {
    return (
      space: null,
      error: 'Space names can be at most $maxSpaceNameLength characters',
    );
  }

  final result = await client.spaces.create({'name': trimmed});
  if (!result.ok) {
    return (
      space: null,
      error: result.errorMessageOr('Failed to create space'),
    );
  }
  final space = result.data;
  if (space is! AccordSpace || space.id.isEmpty) {
    return (space: null, error: 'Server returned no space');
  }
  final normalized = await normalizeNewSpaceEveryoneRole(client, space);
  if (normalized != null && !normalized.ok) {
    return (
      space: null,
      error: normalized.errorMessageOr(
        'Space created, but its default mention permission could not be secured',
      ),
    );
  }

  ref
      .read(connectionsControllerProvider.notifier)
      .upsertSpace(session.key, space);
  if (ref.read(connectionsControllerProvider).activeKey == session.key) {
    ref.read(spacesControllerProvider.notifier).upsertSpace(space);
  }
  return (space: space, error: null);
}
