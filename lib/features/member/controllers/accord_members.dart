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

/// Whether the initial roster fetch for a space failed (a non-2xx response, a
/// network error, or a timeout). Lets the roster show a retry affordance instead
/// of spinning forever when `members.list` never yields a list. Cleared on a
/// successful load, and by the roster's Retry button before it re-triggers
/// `_load`; set true only after the retries are exhausted.
@Riverpod(keepAlive: true)
class MembersLoadFailed extends _$MembersLoadFailed {
  @override
  bool build(String spaceId) => false;

  // ignore: use_setters_to_change_properties
  void set(bool value) => state = value;
}

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
    // Retry a few times so a transient network blip or a still-warming server
    // doesn't strand the roster on a permanent spinner. The `timeout` guards a
    // hung socket, since the underlying HTTP client has no timeout of its own —
    // without it a stalled request would leave `state` null (a forever spinner)
    // that never recovers, even across navigation or an app restart.
    //
    // Every write to `membersLoadFailedProvider` happens after the first
    // `await` below: `build` calls `_load` synchronously, and Riverpod forbids
    // a provider mutating another during initialization.
    for (var attempt = 0; attempt < 3; attempt++) {
      List<AccordMember>? list;
      try {
        // `withUser` asks the server to embed each member's user object, so
        // `_resolveUsers` finds them already populated and skips the per-member
        // fetch. Older servers ignore the flag; the fallback fetch runs then.
        list =
            (await client.members
                    .list(spaceId, query: {'limit': 100}, withUser: true)
                    .timeout(const Duration(seconds: 20)))
                .listOrLog<AccordMember>('members for $spaceId');
      } catch (e) {
        debugPrint('Failed to load members for $spaceId: $e');
      }
      if (list != null) {
        final members = {for (final member in list) member.userId: member};
        state = members;
        ref.read(membersLoadFailedProvider(spaceId).notifier).set(false);
        await _resolveUsers(client, members);
        return;
      }
      // Back off before retrying (1s, then 2s); no wait after the final try.
      if (attempt < 2) {
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    ref.read(membersLoadFailedProvider(spaceId).notifier).set(true);
  }

  /// The members endpoint returns only `user_id` per member — no embedded user
  /// object — so names/avatars resolve to "Unknown" until the user is fetched.
  /// Mirror the reference client: fill each member's [AccordMember.user] from
  /// the global user cache, fetching any still-missing users, then refresh state
  /// so the roster and message authors rebuild with real identities.
  Future<void> _resolveUsers(
    AccordClient client,
    Map<String, AccordMember> members,
  ) async {
    final usersController = ref.read(accordUsersControllerProvider.notifier);
    final missing = <String>[];
    for (final member in members.values) {
      if (member.user != null) continue;
      final known = usersController.cached(member.userId, client: client);
      if (known != null) {
        member.user = known;
      } else if (member.userId.isNotEmpty) {
        missing.add(member.userId);
      }
    }

    await Future.wait([
      for (final userId in missing)
        usersController.resolve(userId, client: client).then((user) {
          if (user != null) members[userId]?.user = user;
        }),
    ]);

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
