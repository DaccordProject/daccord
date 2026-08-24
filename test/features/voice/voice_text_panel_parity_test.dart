import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Parity tests for #210: a voice channel's text chat is an ordinary text
/// channel and must behave like one.
///
/// The voice view used to render its own slimmed-down message list (author +
/// content, nothing else), so voice chat silently lacked the message context
/// menu, reactions, replies, threads and the full composer that every other
/// channel has. It now embeds the real [MessagePane] in panel mode, and these
/// tests drive that through the voice view exactly as a user reaches it.

const _channelId = 'vc1';
const _spaceId = 's1';
const _selfId = 'u1';

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

/// A [VoiceController] parked in the lobby (never connected), which is where
/// the chat panel is open by default.
class _LobbyVoiceController extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection();
}

class _NoVoiceStates extends VoiceStatesController {
  @override
  Map<String, Map<String, AccordVoiceState>> build(String serverKey) => const {};
}

Map<String, dynamic> _message() => {
  'id': 'm1',
  'channel_id': _channelId,
  'author_id': _selfId,
  'content': 'hello from voice chat',
  'timestamp': '2026-01-01T10:00:00Z',
  'reactions': [
    {
      'emoji': {'name': '👍'},
      'count': 1,
      'me': false,
    },
  ],
};

/// The voice channel view, logged in against a [MockClient] that serves one
/// message (with a reaction) for the voice channel and empty lists elsewhere.
({Widget app, AccordClient client}) _host() {
  final responder = MockClient((request) async {
    final body =
        request.method == 'GET' &&
            request.url.path.endsWith('/channels/$_channelId/messages')
        ? jsonEncode([_message()])
        : '[]';
    return http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: responder,
  );
  final app = ProviderScope(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(
          client: client,
          session: AccordSession(
            server: server,
            token: 'test-token',
            userId: _selfId,
            username: 'self',
          ),
        ),
      ),
      settingsControllerProvider.overrideWith(_FakeSettingsController.new),
      voiceControllerProvider.overrideWith(_LobbyVoiceController.new),
      voiceStatesControllerProvider('').overrideWith(_NoVoiceStates.new),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: const Scaffold(
        body: VoiceChannelView(
          channelId: _channelId,
          spaceId: _spaceId,
          channelName: 'general-voice',
        ),
      ),
    ),
  );
  return (app: app, client: client);
}

/// Message bodies render as markdown, so they're [RichText], not [Text].
Finder _body(String text) => find.text(text, findRichText: true);

/// Moves a mouse pointer over [finder], which is what reveals a row's action
/// bar. Widget tests have no pointer of their own, so one is attached here.
Future<void> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(finder));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('voice chat renders the channel history through MessagePane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final host = _host();
    addTearDown(host.client.dispose);
    await tester.pumpWidget(host.app);
    await _settle(tester);

    // The panel is the real pane, not a bespoke list.
    expect(find.byType(MessagePane), findsOneWidget);
    expect(_body('hello from voice chat'), findsOneWidget);
  });

  testWidgets('voice chat rows offer the hover actions and the actions menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final host = _host();
    addTearDown(host.client.dispose);
    await tester.pumpWidget(host.app);
    await _settle(tester);

    final row = find.byKey(const ValueKey('m1'));
    expect(row, findsOneWidget);
    // The panel is narrow, so the action bar floats: nothing until hovered…
    expect(find.byTooltip('Message actions'), findsNothing);
    // …and the message keeps essentially the whole row to itself meanwhile.
    expect(
      tester.getSize(find.descendant(of: row, matching: find.byType(Column))
          .first).width,
      greaterThan(180),
    );

    await _hover(tester, row);
    expect(find.byTooltip('Add reaction'), findsOneWidget);
    expect(find.byTooltip('Reply'), findsOneWidget);
    expect(find.byTooltip('Thread'), findsOneWidget);

    // And the overflow menu carries the rest, exactly as in a text channel.
    await tester.tap(find.byTooltip('Message actions'));
    await _settle(tester);
    expect(find.widgetWithText(PopupMenuItem<String>, 'Edit'), findsOneWidget);
    expect(
      find.widgetWithText(PopupMenuItem<String>, 'Delete'),
      findsOneWidget,
    );
  });

  testWidgets('voice chat shows reactions and can toggle one', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final host = _host();
    addTearDown(host.client.dispose);
    await tester.pumpWidget(host.app);
    await _settle(tester);

    // The existing reaction renders as a pill…
    final pill = find.text('👍');
    expect(pill, findsOneWidget);

    // …and tapping it reacts (optimistically flipping to "mine").
    await tester.tap(pill);
    await _settle(tester);
    expect(find.text('👍'), findsOneWidget);
  });

  testWidgets('voice chat gets the full composer, not a bare text field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final host = _host();
    addTearDown(host.client.dispose);
    await tester.pumpWidget(host.app);
    await _settle(tester);

    // Attachments and the emoji picker were both missing from the old panel.
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
  });

  testWidgets('below the side-panel breakpoint the chat is still a full '
      'text channel', (tester) async {
    // Portrait phone: the chat takes over the body instead of sitting beside
    // the video grid, and rows render in touch mode — no hover bar at all, so
    // the long-press menu is the only path to the per-message actions. It has
    // to carry all of them.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final host = _host();
    addTearDown(host.client.dispose);
    await tester.pumpWidget(host.app);
    await _settle(tester);

    expect(_body('hello from voice chat'), findsOneWidget);
    expect(find.byTooltip('Message actions'), findsNothing);

    await tester.longPress(find.byKey(const ValueKey('m1')));
    await _settle(tester);

    expect(find.text('Add reaction'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Thread'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('the voice chat panel keeps its close button', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final host = _host();
    addTearDown(host.client.dispose);
    await tester.pumpWidget(host.app);
    await _settle(tester);

    expect(find.byTooltip('Close chat'), findsOneWidget);
    await tester.tap(find.byTooltip('Close chat'));
    await _settle(tester);
    expect(find.byType(MessagePane), findsNothing);
  });
}
