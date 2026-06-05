import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
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
    if (data is List) {
      state = {
        for (final member in data.whereType<AccordMember>())
          member.userId: member,
      };
    }
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
