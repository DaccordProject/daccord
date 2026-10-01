import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/shared/controllers/load_failed.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_members.g.dart';

/// Spaces that currently have a live member controller. The gateway handler
/// consults this so member join/update/leave events only mutate caches the UI
/// has actually opened, rather than history-loading the full member list for
/// every space that happens to emit an event.
typedef ServerSpaceKey = ({String serverKey, String spaceId});

final Set<ServerSpaceKey> activeMemberSpaces = <ServerSpaceKey>{};

/// The [LoadFailed] flag for a space's roster: set once the initial fetch has
/// exhausted its retries, so the roster offers Retry instead of spinning
/// forever. Cleared on a successful load and by the Retry button.
LoadFailedProvider membersLoadFailedProvider(
  String serverKey,
  String spaceId,
) => loadFailedProvider('members', serverKey, spaceId);

/// A space's members, keyed by space ID and indexed by user ID for O(1) author
/// resolution. Self-loads via `members.list` the first time it's watched (once
/// logged in) and is kept in sync by member join/update/leave gateway events.
/// `null` means "not loaded yet".
@Riverpod(keepAlive: false)
class AccordMembersController extends _$AccordMembersController {
  @override
  Map<String, AccordMember>? build(String serverKey, String spaceId) {
    final key = (serverKey: serverKey, spaceId: spaceId);
    activeMemberSpaces.add(key);
    ref.onDispose(() => activeMemberSpaces.remove(key));

    final client = ref.watchAccordClientFor(serverKey);
    if (client != null) {
      _load(client, spaceId);
    }
    return null;
  }

  Future<void> _load(AccordClient client, String spaceId) async {
    // Retry so a transient blip or a still-warming server doesn't strand the
    // roster on a spinner. The 20s timeout sits under AccordRest's own
    // per-attempt bound so a hung socket fails (and is reported) sooner.
    //
    // Writes to `membersLoadFailedProvider` must stay after the first `await`:
    // `build` calls `_load` synchronously, and Riverpod forbids a provider
    // mutating another during initialization.
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
      if (!ref.mounted) return;
      if (list != null) {
        if (!ref.isCurrentAccordClient(serverKey, client)) return;
        final members = {for (final member in list) member.userId: member};
        state = members;
        ref
            .read(membersLoadFailedProvider(serverKey, spaceId).notifier)
            .set(false);
        await _resolveUsers(client, members);
        return;
      }
      // Back off before retrying (1s, then 2s); no wait after the final try.
      if (attempt < 2) {
        await Future.delayed(Duration(seconds: attempt + 1));
        if (!ref.mounted) return;
      }
    }
    if (ref.mounted && ref.isCurrentAccordClient(serverKey, client)) {
      ref
          .read(membersLoadFailedProvider(serverKey, spaceId).notifier)
          .set(true);
    }
  }

  /// Fills each member's [AccordMember.user] the server didn't embed from the
  /// user cache, fetching any still-missing users, then refreshes state so the
  /// roster and message authors rebuild with real identities. Mirrors the
  /// reference client.
  Future<void> _resolveUsers(
    AccordClient client,
    Map<String, AccordMember> members,
  ) async {
    final usersController = ref.read(
      accordUsersControllerProvider(serverKey).notifier,
    );
    final missing = <String>[];
    for (final member in members.values) {
      if (member.user != null) continue;
      final known = usersController.cached(member.userId);
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
    if (!ref.mounted) return;

    // Replace the map identity so watchers rebuild with enriched members.
    if (state != null && ref.isCurrentAccordClient(serverKey, client)) {
      state = {...members};
    }
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
