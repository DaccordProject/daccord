import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_users.g.dart';

/// Global per-user cache for users not covered by a space's loaded member page.
///
/// The member cache (`AccordMembersController`) only holds the first 100 members
/// of a space, so message authors and typers outside that page resolve to a raw
/// ID. This controller backfills them: [ensure] lazily fetches a user via
/// `users.fetch` (deduped against in-flight and already-cached IDs) and stores
/// the result, after which watchers rebuild with the resolved name/avatar.
@Riverpod(keepAlive: true)
class AccordUsersController extends _$AccordUsersController {
  final Set<String> _inFlight = <String>{};

  @override
  Map<String, AccordUser> build() => const {};

  /// Schedules a one-time background fetch for [userId] if it isn't already
  /// cached or in flight. Safe to call during a widget build: the cache is
  /// mutated only after the request completes, never synchronously.
  void ensure(String userId) {
    if (userId.isEmpty ||
        state.containsKey(userId) ||
        _inFlight.contains(userId)) {
      return;
    }
    final client = ref.accordClient;
    if (client == null) return;

    _inFlight.add(userId);
    Future(() async {
      final user = (await client.users.fetch(userId))
          .dataOrLog<AccordUser>('fetch user $userId');
      _inFlight.remove(userId);
      if (user != null) state = {...state, userId: user};
    });
  }

  /// Inserts or replaces [user] in the cache. Used after `users.updateMe` so
  /// the self profile changes are visible everywhere it's rendered without
  /// waiting for an `ensure` round-trip.
  void upsert(AccordUser user) {
    state = {...state, user.id: user};
  }
}
