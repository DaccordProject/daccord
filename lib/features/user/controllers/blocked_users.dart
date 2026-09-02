import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'blocked_users.g.dart';

/// Relationship type for a blocked account, mirrored from the server (1 =
/// friend, 2 = blocked, 3 = pending incoming, 4 = pending outgoing).
const int accordBlockedRelationship = 2;

/// The accounts this connection has blocked, by user id.
///
/// Blocking is what the report dialog offers where no moderator will see the
/// report, and it promises the blocked account's messages stop being shown.
/// Nothing enforced that client-side, so the message surfaces filter on this set
/// (App Review 1.2, #290).
///
/// The server's relationship list is the source of truth: [refresh] seeds the
/// set on gateway READY and the relationship events re-run it. The local
/// [block]/[unblock] mutators exist so the block a user just performed takes
/// effect in the panes immediately rather than on the next fetch.
@Riverpod(keepAlive: true)
class BlockedUsersController extends _$BlockedUsersController {
  @override
  Set<String> build(String serverKey) {
    ref.watchAccordClientFor(serverKey);
    return const {};
  }

  /// Re-reads `GET /users/@me/relationships` and replaces the set. Silently
  /// does nothing when the request fails — a stale set is better than dropping
  /// a block the user made locally.
  Future<void> refresh(AccordClient client) async {
    final result = await client.users.listRelationships();
    if (!ref.isCurrentAccordClient(serverKey, client)) return;
    final data = result.data;
    if (!result.ok || data is! List) return;
    sync(data.whereType<AccordRelationship>());
  }

  /// Replaces the set from a full relationship list (the Friends tab already
  /// holds one, so it re-uses this rather than fetching again).
  void sync(Iterable<AccordRelationship> relationships) {
    final next = <String>{
      for (final relationship in relationships)
        if (relationship.type == accordBlockedRelationship)
          if ((relationship.user?.id ?? '').isNotEmpty) relationship.user!.id,
    };
    if (next.length == state.length && next.every(state.contains)) return;
    state = next;
  }

  void block(String userId) {
    if (userId.isEmpty || state.contains(userId)) return;
    state = {...state, userId};
  }

  void unblock(String userId) {
    if (!state.contains(userId)) return;
    state = {...state}..remove(userId);
  }
}

/// The blocked set of the active connection, for the block/unblock actions
/// scattered across the DM, member and report surfaces.
extension BlockedUsersRef on WidgetRef {
  BlockedUsersController get blockedUsers => read(
    blockedUsersControllerProvider(readActiveServerKey() ?? '').notifier,
  );
}
