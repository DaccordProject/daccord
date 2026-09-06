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

  /// How long a failed fetch keeps [resolve] from retrying that id.
  static const Duration failedRetryWindow = Duration(minutes: 5);

  final Map<String, AccordUser> _cache = {};
  final Map<String, Future<AccordUser?>> _inFlight = {};

  /// Ids whose last fetch failed (deleted account, 404, network), by when.
  /// Without this every pane rebuild re-issued `GET /users/{id}` for an author
  /// that no longer exists, since a failure leaves nothing in [_cache].
  final Map<String, DateTime> _failedAt = {};
  final Queue<_UserResolutionRequest> _pending = Queue();
  int _activeFetches = 0;

  @override
  Map<String, AccordUser> build(String serverKey) {
    ref.watchAccordClientFor(serverKey);
    return {..._cache};
  }

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
    final cached = _cache[userId];
    if (cached != null) return Future.value(cached);
    final failedAt = _failedAt[userId];
    if (failedAt != null) {
      if (DateTime.now().difference(failedAt) < failedRetryWindow) {
        return Future.value();
      }
      _failedAt.remove(userId);
    }
    final existing = _inFlight[userId];
    if (existing != null) return existing;

    final completer = Completer<AccordUser?>();
    final request = _UserResolutionRequest(
      userId,
      requestClient,
      completer,
      requireCurrentClient: client == null,
    );
    _inFlight[userId] = completer.future;
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
    var definitiveMiss = false;
    try {
      final result = await request.client.users.fetch(request.userId);
      user = result.dataOrLog<AccordUser>('fetch user ${request.userId}');
      // Only remember a miss the server actually answered (404 for a deleted
      // account). A transport failure keeps statusCode 0 and must stay
      // retryable, or a brief outage would blank every author it touched for
      // the whole retry window.
      definitiveMiss =
          user == null && result.statusCode >= 400 && result.statusCode < 500;
      if (user != null &&
          (!request.requireCurrentClient ||
              ref.isCurrentAccordClient(serverKey, request.client))) {
        _cache[request.userId] = user;
        state = {..._cache};
      }
    } catch (error) {
      debugPrint('Failed to fetch user ${request.userId}: $error');
    } finally {
      if (definitiveMiss) _failedAt[request.userId] = DateTime.now();
      _inFlight.remove(request.userId);
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
    _failedAt.remove(user.id);
    _cache[user.id] = user;
    state = {..._cache};
  }

  /// Returns a cached user from the same server as [client].
  AccordUser? cached(String userId, {AccordClient? client}) => _cache[userId];
}

class _UserResolutionRequest {
  const _UserResolutionRequest(
    this.userId,
    this.client,
    this.completer, {
    required this.requireCurrentClient,
  });

  final String userId;
  final AccordClient client;
  final Completer<AccordUser?> completer;
  final bool requireCurrentClient;
}
