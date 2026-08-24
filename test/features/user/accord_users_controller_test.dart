import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AccordClient _client(
  Future<http.Response> Function(http.Request request) responder, {
  String baseUrl = 'https://accord.example.test',
}) {
  final server = AccordServer.fromBaseUrl(baseUrl);
  return AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient(responder),
  );
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

http.Response _userResponse(String id) =>
    http.Response(jsonEncode({'id': id, 'username': id}), 200);

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'shares an in-flight request and serves later callers from cache',
    () async {
      var calls = 0;
      final release = Completer<void>();
      final client = _client((request) async {
        calls++;
        await release.future;
        return _userResponse(request.url.pathSegments.last);
      });
      addTearDown(client.dispose);
      final container = _container();
      final users = container.read(accordUsersControllerProvider.notifier);

      final first = users.resolve('u1', client: client);
      final second = users.resolve('u1', client: client);

      expect(identical(first, second), isTrue);
      await _waitUntil(() => calls == 1);
      release.complete();

      expect((await first)?.id, 'u1');
      expect((await second)?.id, 'u1');
      expect(container.read(accordUsersControllerProvider)['u1']?.id, 'u1');

      expect((await users.resolve('u1', client: client))?.id, 'u1');
      expect(calls, 1);
    },
  );

  test('bounds concurrent requests across distinct user ids', () async {
    var started = 0;
    var active = 0;
    var peak = 0;
    final release = Completer<void>();
    final client = _client((request) async {
      started++;
      active++;
      if (active > peak) peak = active;
      await release.future;
      active--;
      return _userResponse(request.url.pathSegments.last);
    });
    addTearDown(client.dispose);
    final container = _container();
    final users = container.read(accordUsersControllerProvider.notifier);
    final total = AccordUsersController.maxConcurrentFetches + 4;

    final resolutions = [
      for (var i = 0; i < total; i++) users.resolve('u$i', client: client),
    ];

    await _waitUntil(
      () => started == AccordUsersController.maxConcurrentFetches,
    );
    expect(peak, AccordUsersController.maxConcurrentFetches);
    release.complete();

    final resolved = await Future.wait(resolutions);
    expect(started, total);
    expect(peak, lessThanOrEqualTo(AccordUsersController.maxConcurrentFetches));
    expect(resolved.whereType<AccordUser>(), hasLength(total));
    expect(container.read(accordUsersControllerProvider), hasLength(total));
  });

  test('scopes cache and in-flight requests to each server', () async {
    var firstCalls = 0;
    var secondCalls = 0;
    final first = _client((request) async {
      firstCalls++;
      return http.Response(
        jsonEncode({'id': 'same', 'username': 'first'}),
        200,
      );
    });
    final second = _client((request) async {
      secondCalls++;
      return http.Response(
        jsonEncode({'id': 'same', 'username': 'second'}),
        200,
      );
    }, baseUrl: 'https://second.example.test');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final users = _container().read(accordUsersControllerProvider.notifier);

    final results = await Future.wait([
      users.resolve('same', client: first),
      users.resolve('same', client: second),
    ]);

    expect(results[0]?.username, 'first');
    expect(results[1]?.username, 'second');
    expect(users.cached('same', client: first)?.username, 'first');
    expect(users.cached('same', client: second)?.username, 'second');
    expect(firstCalls, 1);
    expect(secondCalls, 1);
  });
}
