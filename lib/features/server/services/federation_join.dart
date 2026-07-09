import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Outcome of a federated-space join: the mirrored (qualified) space id on
/// success, or a human-readable [error] on failure.
typedef FederatedJoinResult = ({String? spaceId, String? error});

/// Joins a space homed on a remote federated server through the connected
/// [client], then hydrates the returned replica into the space list so it
/// appears in the rail immediately (its channels/members/roles then load
/// lazily through the existing per-space controllers and stay live via gateway
/// fanout).
///
/// Federation is server-to-server: [client] is the user's *own* connected
/// server, which runs the signed handshake against [domain] and returns the
/// mirrored qualified id. Errors (federation disabled, space not
/// federation-enabled, banned, peer untrusted) surface via the result's
/// [error]. Reused by the add-server dialog and `daccord://` deep-link handling.
Future<FederatedJoinResult> joinFederatedSpace(
  WidgetRef ref,
  AccordClient client,
  String domain,
  String spaceId,
) async {
  final result = await client.federation.joinSpace(domain, spaceId);
  if (!result.ok) {
    return (
      spaceId: null,
      error: result.errorOr('Failed to join federated space'),
    );
  }
  final data = result.data;
  final mirrored = data is Map ? data['space_id']?.toString() : null;
  if (mirrored == null || mirrored.isEmpty) {
    return (spaceId: null, error: 'Server returned no space id');
  }

  // The server already applied the join snapshot as a local replica; fetch the
  // mirrored space so the rail shows it without waiting for a reconnect.
  final fetched = await client.spaces.fetch(mirrored);
  final space = fetched.data;
  if (fetched.ok && space is AccordSpace) {
    ref.read(spacesControllerProvider.notifier).upsertSpace(space);
  }
  return (spaceId: mirrored, error: null);
}

/// Splits a federated space address into `(spaceId, domain)`. Accepts either a
/// single `spaceId@domain` token or returns null when no `@` is present.
({String spaceId, String domain})? parseFederatedAddress(String raw) {
  final text = raw.trim();
  final at = text.lastIndexOf('@');
  if (at <= 0 || at == text.length - 1) return null;
  return (spaceId: text.substring(0, at), domain: text.substring(at + 1));
}
