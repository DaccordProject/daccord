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

  // --- Linux / GTK --------------------------------------------------------

  testWidgets(
    'Linux: Shift+Enter is passed to the input method, even with no Dart '
    'composing range',
    (tester) async {
      // The review's reproduction: Ctrl+Shift+U, 3042, Shift+Enter. GTK is
      // composing but the controller reports no composing range at all.
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
      );
      expect(field.controller!.value.composing, TextRange.empty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(handled, isFalse, reason: 'the embedder/IM must see the key');
      expect(field.controller!.text, isEmpty);

      // GTK's IM consumes the key and commits the character, with no action.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'あ',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await _tick(tester);
      expect(field.controller!.text, 'あ');
      expect(harness.sends, isEmpty);

      // The recorded chord must not outlive the key the IM consumed: a later
      // plain Enter still sends.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _tick(tester);
      expect(field.controller!.text, isNot(contains('\n')));
      expect(harness.sends, hasLength(1));
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: the send action after an unconsumed Shift+Enter inserts a newline',
    (tester) async {
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hello world',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      // Released before the embedder's action arrives: the chord was
      // recorded at key-down, so this must not matter.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.testTextInput.receiveAction(TextInputAction.send);
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
    variant: _linux,
  );

  testWidgets(
    'Linux: plain Enter sends',
    (tester) async {
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _tick(tester);

      expect(harness.sends, hasLength(1));
      expect(field.controller!.text, isNot(contains('\n')));
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: a key buffered before the send action does not turn the newline '
    'into a send',
    (tester) async {
      // Review of #384 (r4054068830): `xdotool key --delay 0 shift+Return a`.
      // The framework sees `a` before GTK's action for the Enter comes back.
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      // Only now does the embedder's action for the Shift+Enter arrive...
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _tick(tester);
      expect(harness.sends, isEmpty);
      expect(field.controller!.text, 'hi\n');

      // ...followed by the `a` the embedder inserted after it.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hi\na',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await _tick(tester);
      expect(field.controller!.text, 'hi\na');
      expect(harness.sends, isEmpty);
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: a plain Enter the IM consumed does not make a later Shift+Enter '
    'send',
    (tester) async {
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
      );

      // Plain Enter commits a composition; the IM consumes it (no action).
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'あ',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await _tick(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _tick(tester);

      expect(field.controller!.text, 'あ\n');
      expect(harness.sends, isEmpty);
    },
    skip: kIsWeb,
    variant: _linux,
  );

  testWidgets(
    'Linux: two Shift+Enters whose actions arrive back to back give two '
    'newlines',
    (tester) async {
      final (harness, field) = await _pumpWithText(
        tester,
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _tick(tester);

      expect(field.controller!.text, 'hi\n\n');
      expect(harness.sends, isEmpty);
    },
    skip: kIsWeb,
    variant: _linux,
  );
}
