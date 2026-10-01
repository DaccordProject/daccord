import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/leave_space.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AccordAuth {
  _Auth(this.client);
  @override
  final AccordClient client;

  @override
  AccordAuthState build() => const AccordAuthLoggedOut();

  @override
  AccordClient? clientForKey(String key) => client;
}

void main() {
  for (final leavingActive in [true, false]) {
    for (final closeWhileLeaving in [true, false]) {
      testWidgets(
        'leaving ${leavingActive ? 'active' : 'background'} space removes only its connection cache${closeWhileLeaving ? ' after its widget closes' : ''}',
        (tester) async {
          final requests = <http.Request>[];
          final response = Completer<http.Response>();
          final busy = <bool>[];
          final client = AccordClient(
            baseUrl: 'https://background.test',
            httpClient: MockClient((request) async {
              requests.add(request);
              return response.future;
            }),
          );
          final container = ProviderContainer(
            overrides: [accordAuthProvider.overrideWith(() => _Auth(client))],
          );
          addTearDown(container.dispose);
          addTearDown(client.dispose);
          AccordSession session(String url) => AccordSession(
            server: AccordServer.fromBaseUrl(url),
            token: 'test',
            userId: 'operator',
            username: 'operator',
          );
          final active = session('https://active.test');
          final background = session('https://background.test');
          final space = AccordSpace(id: 'same-id', name: 'Space');
          final connections = container.read(
            connectionsControllerProvider.notifier,
          );
          connections.register(active);
          connections.register(background);
          connections.setActive(active.key);
          connections.setSpaces(active.key, [space]);
          connections.setSpaces(background.key, [space]);
          container.read(spacesControllerProvider.notifier).setSpaces([space]);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: buildAppTheme(AppThemePreset.dark),
                home: Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) => TextButton(
                      onPressed: () => leaveSpace(
                        context,
                        ref,
                        space,
                        leavingActive ? active.key : background.key,
                        deleteData: true,
                        onBusy: busy.add,
                      ),
                      child: const Text('Leave'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Leave'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Leave & delete'));
          await tester.pumpAndSettle();
          if (closeWhileLeaving) {
            await tester.pumpWidget(const SizedBox());
          }
          response.complete(http.Response('{}', 204));
          await tester.pumpAndSettle();
          expect(busy, closeWhileLeaving ? [true] : [true, false]);
          expect(tester.takeException(), isNull);
          expect(requests.single.method, 'DELETE');
          expect(
            container
                .read(connectionsControllerProvider)
                .connectionFor(leavingActive ? active.key : background.key)!
                .spaces,
            isEmpty,
          );
          expect(
            container
                .read(connectionsControllerProvider)
                .connectionFor(leavingActive ? background.key : active.key)!
                .spaces,
            hasLength(1),
          );
          expect(
            container.read(spacesControllerProvider),
            leavingActive ? isEmpty : hasLength(1),
          );
        },
      );
    }
  }
}
