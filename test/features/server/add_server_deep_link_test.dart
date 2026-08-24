import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/services/deep_link_navigation.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExistingServerAuth extends AccordAuth {
  _ExistingServerAuth(this.loggedIn);

  final AccordAuthLoggedIn loggedIn;
  String? activatedKey;

  @override
  AccordAuthState build() => loggedIn;

  @override
  AccordClient? get client => loggedIn.client;

  @override
  String? keyForBaseUrl(String baseUrl) =>
      baseUrl == loggedIn.session.server.baseUrl ? loggedIn.session.key : null;

  @override
  void setActiveServer(String key) => activatedKey = key;
}

void main() {
  testWidgets('add-server connect preserves its space and channel destination', (
    tester,
  ) async {
    final server = AccordServer.fromBaseUrl('https://chat.example');
    final session = AccordSession(
      server: server,
      token: 'token',
      userId: 'user',
      username: 'User',
    );
    final client = AccordClient();
    addTearDown(client.dispose);
    late _ExistingServerAuth auth;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accordAuthProvider.overrideWith(() {
            auth = _ExistingServerAuth(
              AccordAuthLoggedIn(client: client, session: session),
            );
            return auth;
          }),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddServerDialog(
                  context,
                  initialUrl:
                      'daccord://connect/chat.example/team-news?channel=release%20notes',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Add a Server'), findsNothing);
    expect(auth.activatedKey, session.key);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Open')),
    );
    final pending = container.read(pendingDeepLinkProvider);
    expect(pending?.serverBaseUrl, server.baseUrl);
    expect(pending?.spaceName, 'team-news');
    expect(pending?.channelName, 'release notes');
  });
}
