import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_members.g.dart';

/// Spaces that currently have a live member controller. The gateway handler
/// consults this so member join/update/leave events only mutate caches the UI
/// has actually opened, rather than history-loading the full member list for
/// every space that happens to emit an event.
final Set<String> activeMemberSpaces = <String>{};

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

    final client = ref.watch(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.client : null),
    );
    if (client != null) {
      _load(client, spaceId);
    }
    return null;
  }

  Future<void> _load(AccordClient client, String spaceId) async {
    final result =
        await client.members.list(spaceId, query: {'limit': 100});
    if (!result.ok) {
      debugPrint('Failed to load members for $spaceId: ${result.error}');
      return;
    }
    final data = result.data;
    if (data is! List) return;
    final members = {
      for (final member in data.whereType<AccordMember>())
        member.userId: member,
    };
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

    await Future.wait(missing.map((userId) async {
      final result = await client.users.fetch(userId);
      final user = result.data;
      if (result.ok && user is AccordUser) {
        members[userId]?.user = user;
        usersController.upsert(user);
      } else if (!result.ok) {
        debugPrint('Failed to fetch user $userId: ${result.error}');
      }
    }));

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
