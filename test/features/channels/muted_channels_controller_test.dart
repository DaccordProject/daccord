import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAccordAuth extends AccordAuth {
  _FakeAccordAuth(this._client);

  final AccordClient _client;

  @override
  AccordAuthState build() => const AccordAuthLoggedOut();

  @override
  AccordClient? clientForKey(String key) => _client;
}

ProviderContainer _container(AccordClient client) {
  final container = ProviderContainer(
    overrides: [accordAuthProvider.overrideWith(() => _FakeAccordAuth(client))],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  return container;
}

void main() {
  test('loads channel ids from both mute response shapes', () async {
    final client = AccordClient(
      baseUrl: 'https://accord.example.test',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'channel_id': 'mapped'},
            'bare',
            {'channel_id': 42},
          ]),
          200,
        ),
      ),
    );
    final container = _container(client);

    final muted = await container.read(
      mutedChannelsControllerProvider('server').future,
    );

    expect(muted, {'mapped', 'bare', '42'});
  });

  test('rolls an optimistic mute back when the server rejects it', () async {
    final release = Completer<void>();
    final client = AccordClient(
      baseUrl: 'https://accord.example.test',
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(['existing']), 200);
        }
        await release.future;
        return http.Response('failed', 500);
      }),
    );
    final container = _container(client);
    final provider = mutedChannelsControllerProvider('server');
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);

    final update = notifier.setMuted('new', true);
    expect(container.read(provider).value, {'existing', 'new'});
    release.complete();

    expect(await update, MuteResult.failed);
    expect(container.read(provider).value, {'existing'});
  });

  test('suppresses a repeated update for the same channel', () async {
    var updateCalls = 0;
    final started = Completer<void>();
    final release = Completer<void>();
    final client = AccordClient(
      baseUrl: 'https://accord.example.test',
      httpClient: MockClient((request) async {
        if (request.method == 'GET') return http.Response('[]', 200);
        updateCalls++;
        started.complete();
        await release.future;
        return http.Response('{}', 200);
      }),
    );
    final container = _container(client);
    final provider = mutedChannelsControllerProvider('server');
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);

    final first = notifier.setMuted('channel', true);
    await started.future;
    expect(await notifier.setMuted('channel', true), MuteResult.busy);
    expect(updateCalls, 1);
    release.complete();

    expect(await first, MuteResult.ok);
  });
}
