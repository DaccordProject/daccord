import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A channel whose history fetch fails must read as *broken*, not as *loading*.
/// Before #306 the pane showed the same spinner either way, forever.

const _channelId = 'c1';

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

class _Harness {
  _Harness() {
    final responder = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/messages')) {
        historyRequests++;
        if (historyFails) return http.Response('', 500);
        return http.Response(
          jsonEncode(const []),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    client = AccordClient(
      token: 'test-token',
      tokenType: 'Bearer',
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
      httpClient: responder,
    );
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(
          AccordAuthLoggedIn(
            client: client,
            session: AccordSession(
              server: server,
              token: 'test-token',
              userId: 'u1',
              username: 'self',
            ),
          ),
        ),
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
      ],
    );
  }

  bool historyFails = true;
  int historyRequests = 0;
  late final AccordClient client;
  late final ProviderContainer container;

  Widget get app => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: const Scaffold(
        body: MessagePane(channel: null, channelId: _channelId, spaceId: null),
      ),
    ),
  );

  void dispose() {
    container.dispose();
    client.dispose();
  }
}

Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('a failed history load shows an error with a working retry', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.app);
    // Before the response lands the pane is legitimately loading.
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await _tick(tester);

    expect(find.text("Couldn't load messages"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.historyRequests, 1);

    // Retry re-runs the fetch; this time the server answers.
    harness.historyFails = false;
    await tester.tap(find.text('Retry'));
    await _tick(tester);

    expect(harness.historyRequests, 2);
    expect(find.text("Couldn't load messages"), findsNothing);
    expect(find.text('No messages yet'), findsOneWidget);
  });
}
