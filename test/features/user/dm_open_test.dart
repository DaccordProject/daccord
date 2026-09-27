import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AccordAuth {
  _Auth(this.auth);
  final AccordAuthLoggedIn auth;
  @override
  AccordAuthState build() => auth;
  @override
  AccordClient? clientForKey(String key) =>
      key == auth.session.key ? auth.client : null;
}

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

void main() {
  for (final cached in [true, false]) {
    testWidgets(
      cached
          ? 'opening a qualified local user reuses the cached DM without a POST'
          : 'opening an uncached qualified local user sends the normalized ID',
      (tester) async {
        final creates = <Map<String, dynamic>>[];
        final messageChannels = <String>[];
        final server = AccordServer.fromBaseUrl('https://a.example');
        final client = AccordClient(
          baseUrl: server.baseUrl,
          httpClient: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path.endsWith('/users/@me/channels')) {
              creates.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response(
                jsonEncode({
                  'data': {
                    'id': 'created',
                    'type': 'dm',
                    'recipients': [
                      {'id': '7', 'username': 'Other'},
                    ],
                  },
                }),
                200,
              );
            }
            if (request.url.path.endsWith('/messages')) {
              messageChannels.add(request.url.path);
            }
            return http.Response('{"data":[]}', 200);
          }),
        );
        final session = AccordSession(
          server: server,
          token: 'test',
          userId: '1',
          username: 'Self',
        );
        final container = ProviderContainer(
          overrides: [
            accordAuthProvider.overrideWith(
              () => _Auth(AccordAuthLoggedIn(client: client, session: session)),
            ),
            settingsControllerProvider.overrideWith(_Settings.new),
          ],
        );
        addTearDown(() {
          container.dispose();
          client.dispose();
        });
        container.read(connectionsControllerProvider.notifier)
          ..register(session)
          ..setActive(session.key);
        container
            .read(dmChannelsControllerProvider(session.key).notifier)
            .setChannels(
              cached
                  ? [
                      AccordChannel(
                        id: 'existing',
                        type: 'dm',
                        recipients: [
                          AccordUser(id: '1'),
                          AccordUser(id: '7', username: 'Other'),
                        ],
                      ),
                    ]
                  : [],
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildAppTheme(AppThemePreset.dark),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    return TextButton(
                      onPressed: () => openAccordDirectMessage(
                        context,
                        ref,
                        ' 7@A.EXAMPLE ',
                      ),
                      child: const Text('Open DM'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open DM'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          creates,
          cached
              ? isEmpty
              : [
                  {
                    'recipients': ['7'],
                  },
                ],
        );
        expect(
          messageChannels,
          contains(
            '/api/v1/channels/${cached ? 'existing' : 'created'}/messages',
          ),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
