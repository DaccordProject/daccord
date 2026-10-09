import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
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
  int _generation = 0;
  Map<String, AccordMember?>? _deltas;
  final _profileDeltas = <String, AccordUser>{};

  @override
  Map<String, AccordMember>? build(String serverKey, String spaceId) {
    final key = (serverKey: serverKey, spaceId: spaceId);
    activeMemberSpaces.add(key);
    ref.onDispose(() {
      activeMemberSpaces.remove(key);
      _generation++;
    });
    final client = ref.watchAccordClientFor(serverKey);
    if (client != null) unawaited(reload(client));
    return null;
  }

  bool _current(AccordClient client, int generation) =>
      ref.mounted &&
      generation == _generation &&
      ref.isCurrentAccordClient(serverKey, client);

  /// Loads all pages atomically, retaining gateway changes received while the
  /// snapshot is in flight. A fresh READY can supersede an older request.
  Future<void> reload(AccordClient client) async {
    final generation = ++_generation;
    final deltas = <String, AccordMember?>{};
    _deltas = deltas;
    _profileDeltas.clear();
    final members = <String, AccordMember>{};
    final cursors = <String>{};
    String? after;
    try {
      while (true) {
        RestResult? result;
        List<AccordMember>? page;
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            result = await client.members
                .list(
                  spaceId,
                  query: {'limit': 100, if (after != null) 'after': after},
                  withUser: true,
                )
                .timeout(const Duration(seconds: 20));
            page = result.listOrLog<AccordMember>('members for $spaceId');
          } catch (e) {
            debugPrint('Failed to load members for $spaceId: $e');
          }
          if (!_current(client, generation)) return;
          if (page != null) break;
          if (attempt < 2) {
            await Future<void>.delayed(Duration(seconds: attempt + 1));
            if (!_current(client, generation)) return;
          }
        }
        if (page == null) throw StateError('Member page failed');
        for (final member in page) {
          if (member.userId.isNotEmpty) members[member.userId] = member;
        }
        final cursor = result!.extras['cursor'];
        if (cursor is Map && cursor['has_more'] == false) break;
        if (page.isEmpty) {
          if (cursor is Map && cursor['has_more'] == true) {
            throw StateError('Empty member page with more results');
          }
          break;
        }
        // Older servers omit cursors: a full page still needs an after fetch.
        if (cursor is! Map && page.length < 100) break;
        final next = cursor is Map
            ? cursor['after']?.toString()
            : page.last.userId;
        if (next == null || next.isEmpty || !cursors.add(next)) {
          throw StateError('Member pagination did not advance');
        }
        after = next;
      }
      if (!_current(client, generation)) return;
      for (final entry in deltas.entries) {
        if (entry.value == null) {
          members.remove(entry.key);
        } else {
          members[entry.key] = entry.value!;
        }
      }
      for (final entry in _profileDeltas.entries) {
        members[entry.key]?.user = entry.value;
      }
      _deltas = null;
      state = members;
      ref
          .read(membersLoadFailedProvider(serverKey, spaceId).notifier)
          .set(false);
      await Future.wait([
        _resolveUsers(client, members, generation),
        _refreshPresences(client, generation),
      ]);
    } catch (e) {
      if (!_current(client, generation)) return;
      debugPrint('Failed to load complete roster for $spaceId: $e');
      _deltas = null;
      ref
          .read(membersLoadFailedProvider(serverKey, spaceId).notifier)
          .set(true);
    }
  }

  Future<void> _refreshPresences(AccordClient client, int generation) async {
    final notifier = ref.read(presenceControllerProvider(serverKey).notifier);
    final baseline = ref.read(presenceControllerProvider(serverKey));
    try {
      final result = await client.members
          .presences(spaceId)
          .timeout(const Duration(seconds: 15));
      if (!_current(client, generation) || !result.ok || result.data is! List) {
        return;
      }
      notifier.mergeSnapshot(
        (result.data as List).whereType<AccordPresence>(),
        baseline: baseline,
        homeDomain: Uri.parse(client.config.baseUrl).host,
      );
    } catch (e) {
      // Older servers may lack the endpoint; READY/live updates still work.
      debugPrint('Could not refresh presences for $spaceId: $e');
    }
  }

  /// Enrich only records still in the current roster. Never restore a captured
  /// map: a member may leave or be replaced while the user request is pending.
  Future<void> _resolveUsers(
    AccordClient client,
    Map<String, AccordMember> members,
    int generation,
  ) async {
    final users = ref.read(accordUsersControllerProvider(serverKey).notifier);
    await Future.wait([
      for (final member in members.values)
        if (member.user == null && member.userId.isNotEmpty)
          () async {
            final user =
                users.cached(member.userId) ??
                await users.resolve(member.userId, client: client);
            if (user == null || !_current(client, generation)) return;
            final current = state?[member.userId];
            if (!identical(current, member) || current?.user != null) return;
            current!.user = users.cached(member.userId) ?? user;
            state = {...state!};
          }(),
    ]);
  }

  /// Refreshes the cached [AccordMember.user] for [user] when that user is a
  /// member of this space, so the roster and message authors reflect a profile
  /// change (e.g. the current user edits their own profile, or a USER_UPDATE
  /// arrives) without reloading. No-op when the user isn't in the cache.
  void applyUserUpdate(AccordUser user) {
    if (_deltas != null) _profileDeltas[user.id] = user;
    final pending = _deltas?[user.id];
    if (pending != null) pending.user = user;
    final current = state;
    final member = current?[user.id];
    if (member == null) return;
    member.user = user;
    state = {...current!};
  }

  /// Inserts a gateway member without losing a resolved identity.
  void upsertMember(AccordMember member) {
    if (member.userId.isEmpty) return;
    member.user ??= state?[member.userId]?.user;
    _deltas?[member.userId] = member;
    if (state == null && _deltas != null) return;
    state = {...?state, member.userId: member};
    final client = ref.accordClient;
    if (client != null) {
      unawaited(_resolveUsers(client, {member.userId: member}, _generation));
    }
  }

  void removeMember(String userId) {
    _deltas?[userId] = null;
    final current = state;
    if (current == null || !current.containsKey(userId)) return;
    state = {...current}..remove(userId);
  }
}
