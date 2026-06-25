import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_members.g.dart';

/// Spaces that currently have a live member controller. The gateway handler
/// consults this so member join/update/leave events only mutate caches the UI
/// has actually opened, rather than history-loading the full member list for
/// every space that happens to emit an event.
final Set<String> activeMemberSpaces = <String>{};

/// Upper bound on simultaneous `users.fetch` calls when backfilling the user
/// objects a member page omits. The members endpoint returns only `user_id`, so
/// a 100-member space would otherwise fan out 100 parallel requests on the first
/// space switch, collide with the REST rate limiter (each then 429-retried with
/// backoff), and stall the roster. A small pool keeps the requests flowing
/// without tripping the limiter.
const int _maxConcurrentUserFetches = 8;

/// A space's members, keyed by space ID and indexed by user ID for O(1) author
/// resolution. Self-loads via `members.list` the first time it's watched (once
/// logged in) and is kept in sync by member join/update/leave gateway events.
/// `null` means "not loaded yet".
@Riverpod(keepAlive: true)
class AccordMembersController extends _$AccordMembersController {
  @override
  Map<String, AccordMember>? build(String spaceId) {
    activeMemberSpaces.add(spaceId);
    ref.onDispose(() => activeMemberSpaces.remove(spaceId));

    final client = ref.watchAccordClient();
    if (client != null) {
      _load(client, spaceId);
    }
    return null;
  }

  Future<void> _load(AccordClient client, String spaceId) async {
    // `withUser` asks the server to embed each member's user object, so
    // `_resolveUsers` finds them already populated and skips the per-member
    // fetch. Older servers ignore the flag; the fallback fetch still runs then.
    final list = (await client.members
            .list(spaceId, query: {'limit': 100}, withUser: true))
        .listOrLog<AccordMember>('members for $spaceId');
    if (list == null) return;
    final members = {for (final member in list) member.userId: member};
    state = members;
    await _resolveUsers(client, members);
  }

  /// The members endpoint returns only `user_id` per member — no embedded user
  /// object — so names/avatars resolve to "Unknown" until the user is fetched.
  /// Mirror the reference client: fill each member's [AccordMember.user] from
  /// the global user cache, fetching any still-missing users, then refresh state
  /// so the roster and message authors rebuild with real identities.
  Future<void> _resolveUsers(
      AccordClient client, Map<String, AccordMember> members) async {
    final usersController = ref.read(accordUsersControllerProvider.notifier);
    final cached = ref.read(accordUsersControllerProvider);
    final missing = <String>[];
    for (final member in members.values) {
      if (member.user != null) continue;
      final known = cached[member.userId];
      if (known != null) {
        member.user = known;
      } else if (member.userId.isNotEmpty) {
        missing.add(member.userId);
      }
    }

    // Drain the missing IDs through a bounded worker pool rather than firing
    // them all at once. Dart's single isolate means `removeLast` and the member
    // mutations below never race; the cap only limits in-flight requests.
    final queue = List<String>.of(missing);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final userId = queue.removeLast();
        final result = await client.users.fetch(userId);
        final user = result.data;
        if (result.ok && user is AccordUser) {
          members[userId]?.user = user;
          usersController.upsert(user);
        } else if (!result.ok) {
          debugPrint('Failed to fetch user $userId: ${result.error}');
        }
      }
    }

    final workerCount = missing.length < _maxConcurrentUserFetches
        ? missing.length
        : _maxConcurrentUserFetches;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);

    // Replace the map identity so watchers rebuild with enriched members.
    if (state != null) state = {...members};
  }

  /// Refreshes the cached [AccordMember.user] for [user] when that user is a
  /// member of this space, so the roster and message authors reflect a profile
  /// change (e.g. the current user edits their own profile, or a USER_UPDATE
  /// arrives) without reloading. No-op when the user isn't in the cache.
  void applyUserUpdate(AccordUser user) {
    final current = state;
    final member = current?[user.id];
    if (member == null) return;
    member.user = user;
    state = {...current!};
  }

  /// Inserts [member], or replaces it in place if already present.
  void upsertMember(AccordMember member) {
    final current = {...(state ?? const <String, AccordMember>{})};
    current[member.userId] = member;
    state = current;
  }

  void removeMember(String userId) {
    final current = state;
    if (current == null || !current.containsKey(userId)) return;
    final copy = {...current}..remove(userId);
    state = copy;
  }
}
