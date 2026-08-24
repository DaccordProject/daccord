import 'dart:async';
import 'dart:collection';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_users.g.dart';

/// Per-server user cache for users not covered by a space's loaded member page.
///
/// The member cache (`AccordMembersController`) only holds the first 100 members
/// of a space, so message authors and typers outside that page resolve to a raw
/// ID. This controller backfills them: [ensure] lazily fetches a user via
/// `users.fetch` (deduped against in-flight and already-cached IDs) and stores
/// the result, after which watchers rebuild with the resolved name/avatar.
@Riverpod(keepAlive: true)
class AccordUsersController extends _$AccordUsersController {
  static const int maxConcurrentFetches = 8;

  final Map<String, Map<String, AccordUser>> _cacheByServer = {};
  final Map<({String server, String userId}), Future<AccordUser?>> _inFlight =
      {};
  final Queue<_UserResolutionRequest> _pending = Queue();
  int _activeFetches = 0;

  @override
  Map<String, AccordUser> build() => const {};

  /// Schedules a one-time background fetch for [userId] if it isn't already
  /// cached or in flight. Safe to call during a widget build: the cache is
  /// mutated only after the request completes, never synchronously.
  void ensure(String userId) {
    unawaited(resolve(userId));
  }

  /// Returns the cached [AccordUser] for [userId], or fetches it through the
  /// shared bounded queue. Concurrent callers for the same id await the same
  /// request. [client] lets controller-to-controller callers keep using the
  /// client that initiated their load even if the active account changes.
  Future<AccordUser?> resolve(String userId, {AccordClient? client}) {
    if (userId.isEmpty) return Future.value();
    final requestClient = client ?? ref.accordClient;
    if (requestClient == null) return Future.value();
    final server = requestClient.config.baseUrl;
    final cached = _cacheByServer[server]?[userId];
    if (cached != null) return Future.value(cached);
    final key = (server: server, userId: userId);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final completer = Completer<AccordUser?>();
    final request = _UserResolutionRequest(
      userId,
      server,
      requestClient,
      completer,
    );
    _inFlight[key] = completer.future;
    _pending.add(request);
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_activeFetches < maxConcurrentFetches && _pending.isNotEmpty) {
      final request = _pending.removeFirst();
      _activeFetches += 1;
      unawaited(_resolveRequest(request));
    }
  }

  Future<void> _resolveRequest(_UserResolutionRequest request) async {
    AccordUser? user;
    try {
      user = (await request.client.users.fetch(
        request.userId,
      )).dataOrLog<AccordUser>('fetch user ${request.userId}');
      if (user != null) {
        final cache = _cacheByServer.putIfAbsent(request.server, () => {});
        cache[request.userId] = user;
        final activeServer = ref.accordClient?.config.baseUrl;
        if (activeServer == null || activeServer == request.server) {
          state = {...cache};
        }
      }
    } catch (error) {
      debugPrint('Failed to fetch user ${request.userId}: $error');
    } finally {
      _inFlight.remove((server: request.server, userId: request.userId));
      _activeFetches -= 1;
      request.completer.complete(user);
      _drain();
    }
  }

  /// Inserts or replaces [user] in the cache. Used after `users.updateMe` so
  /// the self profile changes are visible everywhere it's rendered without
  /// waiting for an `ensure` round-trip.
  void upsert(AccordUser user, {AccordClient? client}) {
    final target = client ?? ref.accordClient;
    if (target == null) return;
    final server = target.config.baseUrl;
    final cache = _cacheByServer.putIfAbsent(server, () => {});
    cache[user.id] = user;
    if (ref.accordClient?.config.baseUrl == server) state = {...cache};
  }

  /// Returns a cached user from the same server as [client].
  AccordUser? cached(String userId, {required AccordClient client}) =>
      _cacheByServer[client.config.baseUrl]?[userId];

  /// Publishes the cache belonging to the newly active connection.
  void activate(AccordClient? client) {
    state = client == null
        ? const {}
        : {...?_cacheByServer[client.config.baseUrl]};
  }
}

class _UserResolutionRequest {
  const _UserResolutionRequest(
    this.userId,
    this.server,
    this.client,
    this.completer,
  );

  final String userId;
  final String server;
  final AccordClient client;
  final Completer<AccordUser?> completer;
}
