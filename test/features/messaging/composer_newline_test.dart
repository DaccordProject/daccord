import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shift+Enter in the composer inserts a newline on desktop instead of
/// sending (#376).
///
/// The field keeps `TextInputAction.send` so mobile keyboards show a Send key,
/// but the desktop embedders ignore Shift and perform that action on any Enter.
/// The composer therefore claims Shift+Enter itself, and leaves plain Enter to
/// the embedder, which sends.
///
/// Windows and macOS: the composer handles the chord in its key handler.
/// Linux: the chord goes to GTK's input method first (it may be composing
/// with no composing range visible to Dart), and the embedder's `send` action
/// that follows becomes a newline.

final _interceptingDesktops = TargetPlatformVariant({
  TargetPlatform.windows,
  TargetPlatform.macOS,
});
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

const _channelId = 'c1';

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();

  @override
  void setDraft(String serverKey, String channelId, String text) {}
}

class _Harness {
  _Harness() {
    final responder = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
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

  final List<String> requests = [];
  late final AccordClient client;
  late final ProviderContainer container;

  /// Requests that would have sent a message.
  Iterable<String> get sends =>
      requests.where((r) => r.startsWith('POST') && r.contains('/messages'));

  Widget get app => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: const Scaffold(
        body: MessagePane(channel: null, channelId: _channelId, spaceId: null),
      ),
    ),
  );
}

Future<void> _tick(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<(_Harness, TextField)> _pumpWithText(
  WidgetTester tester,
  TextEditingValue value,
) async {
  final harness = _Harness();
  addTearDown(harness.client.dispose);
  await tester.pumpWidget(harness.app);
  await _tick(tester);
  final finder = find.byType(TextField).last;
  await tester.tap(finder);
  await tester.pump();
  final field = tester.widget<TextField>(finder);
  field.controller!.value = value;
  await tester.pump();
  return (harness, field);
}

KeyEventResult _dispatch(TextField field, LogicalKeyboardKey key) =>
    field.focusNode!.onKeyEvent!(
      field.focusNode!,
      KeyDownEvent(
        physicalKey: key == LogicalKeyboardKey.numpadEnter
            ? PhysicalKeyboardKey.numpadEnter
            : PhysicalKeyboardKey.enter,
        logicalKey: key,
        timeStamp: Duration.zero,
      ),
    );

void main() {
  testWidgets(
    'Shift+Enter inserts a newline at the caret and does not send',
    (tester) async {
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hello world',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await _tick(tester);

      expect(field.controller!.text, 'hello\n world');
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 6),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      expect(harness.sends, isEmpty);
    },
    skip: kIsWeb,
    variant: _interceptingDesktops,
  );

  testWidgets(
    'Shift+numpad Enter replaces the selection with a newline',
    (tester) async {
      final (_, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'one XX two',
          selection: TextSelection(baseOffset: 3, extentOffset: 7),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final result = _dispatch(field, LogicalKeyboardKey.numpadEnter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(result, KeyEventResult.handled);
      expect(field.controller!.text, 'one\ntwo');
    },
    skip: kIsWeb,
    variant: _interceptingDesktops,
  );

  testWidgets(
    'plain Enter is left to the embedder',
    (tester) async {
      final (_, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      // Not claimed by the composer, so the desktop text input plugin receives
      // it and performs the field's `send` action.
      expect(
        _dispatch(field, LogicalKeyboardKey.enter),
        KeyEventResult.ignored,
      );
      expect(field.textInputAction, TextInputAction.send);
      expect(field.controller!.text, 'hi');
    },
    skip: kIsWeb,
    variant: _interceptingDesktops,
  );

  testWidgets(
    'Shift+Enter is left to the IME while it is composing',
    (tester) async {
      final (_, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'nihon',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final result = _dispatch(field, LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(result, KeyEventResult.ignored);
      expect(field.controller!.text, 'nihon');
    },
    skip: kIsWeb,
    variant: _interceptingDesktops,
  );

  testWidgets(
    'Ctrl+Shift+Enter is not treated as a newline',
    (tester) async {
      final (_, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final result = _dispatch(field, LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(result, KeyEventResult.ignored);
      expect(field.controller!.text, 'hi');
    },
    skip: kIsWeb,
    variant: _interceptingDesktops,
  );

  testWidgets(
    'Windows/macOS: the field keeps the send action',
    (tester) async {
      await _pumpWithText(tester, TextEditingValue.empty);
      expect(
        tester.testTextInput.setClientArgs!['inputAction'],
        'TextInputAction.send',
      );
    },
    skip: kIsWeb,
    variant: _interceptingDesktops,
  );

  // --- Linux / GTK --------------------------------------------------------
  //
  // The field uses the `newline` action, so the GTK embedder inserts
  // Shift+Enter newlines itself, after its input method has had a look. Plain
  // Enter sends from the key handler. The embedder's messages are delivered to
  // the client ID the field registered *before* the key press, as a native
  // embedder would have queued them: a text-input connection restart would
  // make the framework drop them, which is how the review of #384
  // (r4054340430) lost typed characters.

  testWidgets(
    'Linux: the field uses the newline action',
    (tester) async {
      await _pumpWithText(tester, TextEditingValue.empty);
      expect(
        tester.testTextInput.setClientArgs!['inputAction'],
        'TextInputAction.newline',
      );
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: a key typed right after Shift+Enter is kept',
    (tester) async {
      // Review of #384 (r4054340430): `xdotool key --delay 0 shift+Return a`
      // on `hi` left `hi\n`, dropping the `a`.
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      final client = _Embedder.capture(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.enter), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      // Only now does GTK process the Enter and the `a`, in order.
      await client.enter(tester);
      await client.type(tester, 'a');
      await _tick(tester);

      expect(field.controller!.text, 'hi\na');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(harness.sends, isEmpty);
      client.expectNoRestart(tester);
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: two rapid Shift+Enters keep both newlines',
    (tester) async {
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      final client = _Embedder.capture(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await client.enter(tester);
      await client.enter(tester);
      await _tick(tester);

      expect(field.controller!.text, 'hi\n\n');
      expect(harness.sends, isEmpty);
      client.expectNoRestart(tester);
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: Shift+Enter is passed to the input method, even with no Dart '
    'composing range',
    (tester) async {
      // Review of #384 (r4054009936): Ctrl+Shift+U, 3042, Shift+Enter. GTK is
      // composing but the controller reports no composing range at all.
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
      );
      final client = _Embedder.capture(tester);
      expect(field.controller!.value.composing, TextRange.empty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      // The IM consumes the key and commits; the embedder adds no newline.
      await client.type(tester, 'あ');
      await _tick(tester);

      expect(field.controller!.text, 'あ');
      expect(harness.sends, isEmpty);
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: plain Enter sends once and keeps a key typed right after it',
    (tester) async {
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      final client = _Embedder.capture(tester);

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
      // The draft was cleared before the embedder saw the next key...
      expect(field.controller!.text, isEmpty);
      expect(
        tester.testTextInput.log.any(
          (c) =>
              c.method == 'TextInput.setEditingState' &&
              (c.arguments as Map)['text'] == '',
        ),
        isTrue,
      );
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyA), isFalse);
      // ...so the embedder's update for it carries just `a`.
      await client.type(tester, 'a');
      await _tick(tester);

      expect(harness.sends, hasLength(1));
      expect(field.controller!.text, 'a');
      expect(field.focusNode!.hasFocus, isTrue);
      client.expectNoRestart(tester);
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: holding Enter sends once and adds no newlines',
    (tester) async {
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.enter), isTrue);
      expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter), isTrue);
      expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await _tick(tester);

      expect(harness.sends, hasLength(1));
      expect(field.controller!.text, isEmpty);
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: plain Enter during a reported composition goes to the IM',
    (tester) async {
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'nihon',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      await _tick(tester);

      expect(harness.sends, isEmpty);
      expect(field.controller!.text, 'nihon');
    },
    skip: kIsWeb,
    variant: _linux,
  );
}

/// Plays the GTK embedder (`fl_text_input_handler.cc`) for the keys a test
/// passes through to it.
///
/// Like the real one, it keeps its own copy of the text, adopting whatever
/// the framework last sent with `TextInput.setEditingState`. It addresses
/// every message to the client ID the field registered when [capture] ran, as
/// a native embedder would have queued them. For an unconsumed Enter it
/// inserts `\n` only when the field's action is `newline`, then performs the
/// field's action, whatever that is.
class _Embedder {
  _Embedder._(this.clientId, this.setClientCalls, this._logSeen, this._text);

  factory _Embedder.capture(WidgetTester tester) {
    final log = tester.testTextInput.log;
    final setClients = log
        .where((c) => c.method == 'TextInput.setClient')
        .toList();
    final id = (setClients.last.arguments as List)[0] as int;
    final field = tester.widget<TextField>(find.byType(TextField).last);
    return _Embedder._(
      id,
      setClients.length,
      log.length,
      field.controller!.text,
    );
  }

  final int clientId;
  final int setClientCalls;
  int _logSeen;
  String _text;

  /// Adopts framework edits sent since the last call.
  void _sync(WidgetTester tester) {
    final log = tester.testTextInput.log;
    for (final call in log.skip(_logSeen)) {
      if (call.method == 'TextInput.setEditingState') {
        _text = (call.arguments as Map)['text'] as String;
      }
    }
    _logSeen = log.length;
  }

  Future<void> _call(WidgetTester tester, String method, Object arg) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(
        MethodCall(method, <Object?>[clientId, arg]),
      ),
      (_) {},
    );
  }

  Future<void> _update(WidgetTester tester) => _call(
    tester,
    'TextInputClient.updateEditingState',
    TextEditingValue(
      text: _text,
      selection: TextSelection.collapsed(offset: _text.length),
    ).toJSON(),
  );

  /// A printable key the IM passed through (or committed).
  Future<void> type(WidgetTester tester, String chars) async {
    _sync(tester);
    _text += chars;
    await _update(tester);
  }

  /// An Enter the IM didn't consume (`GDK_KEY_Return` branch).
  Future<void> enter(WidgetTester tester) async {
    _sync(tester);
    final action = tester.testTextInput.setClientArgs!['inputAction'] as String;
    if (action == 'TextInputAction.newline') {
      _text += '\n';
      await _update(tester);
    }
    await _call(tester, 'TextInputClient.performAction', action);
  }

  /// The field kept the same text-input connection: queued embedder messages
  /// would otherwise be dropped.
  void expectNoRestart(WidgetTester tester) {
    expect(
      tester.testTextInput.log
          .where((c) => c.method == 'TextInput.setClient')
          .length,
      setClientCalls,
      reason: 'a text-input connection restart drops queued GTK updates',
    );
  }
}
