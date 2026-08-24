import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
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

/// Regression tests for #198: a message row's [State] must stay bound to *its*
/// message while an async action (delete confirmation, emoji picker, inline
/// editor) is open.
///
/// The message list is `reverse: true`, so every index shifts when a message
/// arrives. Unkeyed rows are matched by list position, so the live State of the
/// row that opened a dialog gets re-bound to a *different* message — and the
/// handler, which read `widget.message` after its `await`, then acted on that
/// message. `mounted` doesn't catch it: the State really is still mounted.
///
/// Each test drives the real [MessagePane] against a mocked HTTP client and
/// asserts on the request that actually goes over the wire, so the message the
/// user targeted is checked end to end. The action is started from the
/// long-press menu, found by the message's own text rather than by row key, so
/// these tests describe user-visible behaviour rather than the shape of the fix.

const _channelId = 'c1';
const _selfId = 'u1';

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

/// A logged-in [MessagePane] backed by [MockClient], plus the request log and
/// the live message controller so tests can inject a "new message arrived"
/// gateway event mid-await.
class _Harness {
  /// [failDeleteOf] makes the DELETE request for that message id come back
  /// as a server error instead of succeeding, to exercise the failure path.
  _Harness(List<Map<String, String>> seed, {String? failDeleteOf}) {
    final responder = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET' &&
          request.url.path.endsWith('/channels/$_channelId/messages')) {
        return http.Response(
          jsonEncode(seed.reversed.toList()), // REST returns newest-first
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'DELETE' &&
          failDeleteOf != null &&
          request.url.path.endsWith('/messages/$failDeleteOf')) {
        return http.Response('', 500);
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
              userId: _selfId,
              username: 'self',
            ),
          ),
        ),
        // Keeps the row/composer off the (unopened) `accord-settings` Hive box.
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
      ],
    );
  }

  final List<String> requests = [];
  late final AccordClient client;
  late final ProviderContainer container;

  AccordMessagesController get messages =>
      container.read(accordMessagesControllerProvider('', _channelId).notifier);

  /// Requests against [messageId]'s own sub-resources — i.e. everything except
  /// the channel-level message list. The suffix after the id is kept so the
  /// verb/endpoint can be asserted too.
  List<String> requestsFor(String messageId) => [
    for (final r in requests)
      if (r.contains('/messages/$messageId')) r,
  ];

  Widget get app => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      // spaceId: null keeps the pane off the member/role/emoji caches; the row
      // behaviour under test doesn't depend on them.
      home: const Scaffold(
        body: MessagePane(channel: null, channelId: _channelId, spaceId: null),
      ),
    ),
  );

  /// Only the HTTP client is torn down here: the [ProviderContainer] has to
  /// outlive the widget tree, which is finalized after the test's tear-downs
  /// run (the composer saves its draft through the settings provider on
  /// dispose).
  void dispose() => client.dispose();
}

Map<String, String> _msgJson(String id, String content) => {
  'id': id,
  'channel_id': _channelId,
  'author_id': _selfId,
  'content': content,
  'timestamp': '2026-01-01T10:00:00Z',
};

AccordMessage _msg(String id, String content) =>
    AccordMessage.fromJson(_msgJson(id, content));

/// Message bodies render as markdown, so they're [RichText], not [Text].
Finder _body(String text) => find.text(text, findRichText: true);

/// Pumps enough frames for a mocked request or a route transition to complete.
/// `pumpAndSettle` can't be used: the pane shows an indeterminate spinner while
/// the first page loads, which never settles.
Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<_Harness> _pumpPane(WidgetTester tester, {String? failDeleteOf}) async {
  final harness = _Harness([
    _msgJson('m1', 'first message'),
    _msgJson('m2', 'second message'),
  ], failDeleteOf: failDeleteOf);
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.app);
  await _tick(tester);
  expect(_body('first message'), findsOneWidget);
  expect(_body('second message'), findsOneWidget);
  return harness;
}

/// The row rendering [messageId], asserting on the way that the row really is
/// the one showing [body] — the tests' finders are keyed, so this ties the key
/// back to the message the user would be looking at.
///
/// A regression that drops the row keys surfaces here as "no widget found",
/// which is the first half of #198: without keys there is no stable handle on
/// a row at all, because rows are matched by list position.
Finder _row(String messageId, String body) {
  final row = find.byKey(ValueKey(messageId));
  expect(
    find.descendant(of: row, matching: _body(body)),
    findsOneWidget,
    reason: 'row $messageId should be the one showing "$body"',
  );
  return row;
}

/// Opens [messageId]'s overflow menu and picks [action] from it.
Future<void> _menuAction(
  WidgetTester tester,
  Finder row,
  String action,
) async {
  await tester.tap(
    find.descendant(of: row, matching: find.byTooltip('Message actions')),
  );
  await _tick(tester);
  await tester.tap(find.widgetWithText(PopupMenuItem<String>, action));
  await _tick(tester);
}

/// Simulates the gateway delivering a new message while a dialog is open. This
/// is what shifts every index in the `reverse: true` list.
Future<void> _newMessageArrives(WidgetTester tester, _Harness harness) async {
  harness.messages.addMessage(_msg('m3', 'brand new message'));
  await tester.pump();
  await tester.pump();
  expect(_body('brand new message'), findsOneWidget);
}

void main() {
  testWidgets('delete targets the message it was opened on, even when a new '
      'message arrives while the confirm dialog is up', (tester) async {
    final harness = await _pumpPane(tester);

    await _menuAction(tester, _row('m1', 'first message'), 'Delete');

    // The confirm dialog is up and nothing has been deleted yet.
    expect(
      find.text('This message will be permanently deleted.'),
      findsOneWidget,
    );
    expect(harness.requestsFor('m1'), isEmpty);

    // …and now a new message lands, shifting every row's index.
    await _newMessageArrives(tester, harness);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _tick(tester);

    expect(
      harness.requestsFor('m1'),
      ['DELETE /api/v1/channels/$_channelId/messages/m1'],
      reason: 'the confirmed delete must hit the message the user chose',
    );
    expect(
      harness.requestsFor('m2'),
      isEmpty,
      reason: "the row that shifted into m1's old slot must be untouched",
    );
    expect(harness.requestsFor('m3'), isEmpty);
    // And the right row actually went away.
    expect(_body('first message'), findsNothing);
    expect(_body('second message'), findsOneWidget);
  });

  testWidgets(
    'a failed delete leaves the message and reports the failure',
    (tester) async {
      final harness = await _pumpPane(tester, failDeleteOf: 'm1');

      await _menuAction(tester, _row('m1', 'first message'), 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _tick(tester);

      expect(
        harness.requestsFor('m1'),
        ['DELETE /api/v1/channels/$_channelId/messages/m1'],
      );
      // The row is still there rather than having been optimistically removed…
      expect(_body('first message'), findsOneWidget);
      // …and the failure is surfaced rather than silently swallowed, which is
      // what made this indistinguishable from the dead voice-chat menu (#229).
      expect(find.text('Failed to delete message'), findsOneWidget);
    },
  );

  testWidgets('reaction lands on the message the picker was opened on, even '
      'when a new message arrives while it is open', (tester) async {
    final harness = await _pumpPane(tester);

    // Open the emoji picker from the first message's hover actions.
    await tester.tap(
      find.descendant(
        of: _row('m1', 'first message'),
        matching: find.byTooltip('Add reaction'),
      ),
    );
    await _tick(tester);
    expect(find.byTooltip('grinning'), findsOneWidget);

    await _newMessageArrives(tester, harness);

    await tester.tap(find.byTooltip('grinning'));
    await _tick(tester);

    expect(
      harness.requestsFor('m1'),
      [
        'PUT /api/v1/channels/$_channelId/messages/m1'
            '/reactions/%F0%9F%98%80/@me',
      ],
      reason: 'the reaction must land on the message the picker was opened on',
    );
    expect(harness.requestsFor('m2'), isEmpty);
    expect(harness.requestsFor('m3'), isEmpty);
  });

  testWidgets('an in-progress edit stays with its message and saves onto it', (
    tester,
  ) async {
    final harness = await _pumpPane(tester);

    await _menuAction(tester, _row('m1', 'first message'), 'Edit');

    // The editor opened on the first message, seeded with its content.
    final editor = find.widgetWithText(TextField, 'first message');
    expect(editor, findsOneWidget);

    await _newMessageArrives(tester, harness);

    // Still editing the same message, in the same row, after the list shifted.
    expect(editor, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('m1')),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('m2')),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await tester.enterText(editor, 'edited text');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await _tick(tester);

    expect(
      harness.requestsFor('m1'),
      ['PATCH /api/v1/channels/$_channelId/messages/m1'],
      reason: 'the edit must be saved onto the message being edited',
    );
    expect(harness.requestsFor('m2'), isEmpty);
    expect(harness.requestsFor('m3'), isEmpty);
  });

  testWidgets('rows are keyed by message id and keep their State when the '
      'list shifts underneath them', (tester) async {
    final harness = await _pumpPane(tester);

    expect(find.byKey(const ValueKey('m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('m2')), findsOneWidget);

    // Row-local state (hover, in-progress edit, busy flag) lives on the State,
    // so it has to follow the message rather than the list slot.
    final first = tester.state<State>(find.byKey(const ValueKey('m1')));
    final second = tester.state<State>(find.byKey(const ValueKey('m2')));

    await _newMessageArrives(tester, harness);

    expect(
      identical(tester.state<State>(find.byKey(const ValueKey('m1'))), first),
      isTrue,
      reason: 'm1 must keep its State after the list shifted',
    );
    expect(
      identical(tester.state<State>(find.byKey(const ValueKey('m2'))), second),
      isTrue,
      reason: 'm2 must keep its State after the list shifted',
    );
  });
}
