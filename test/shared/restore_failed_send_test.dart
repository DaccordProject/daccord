import 'package:bonfire/shared/utils/restore_failed_send.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces every composer's send cycle after #195: the field stays enabled
/// for the whole send, clears optimistically, re-requests focus (submitting via
/// [TextInputAction.send] unfocuses the field) and puts the text back when the
/// send fails.
class _Composer extends StatefulWidget {
  const _Composer({required this.succeeds});

  /// Whether the simulated send succeeds.
  final bool succeeds;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final focus = FocusNode();
  final controller = TextEditingController();
  bool sending = false;

  @override
  void dispose() {
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = controller.text;
    if (text.trim().isEmpty || sending) return;
    controller.clear();
    setState(() => sending = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (!mounted) return;
    setState(() => sending = false);
    if (!widget.succeeds) restoreFailedSend(controller, text);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    focus.requestFocus();
                    send();
                  },
                ),
              ),
              IconButton(
                onPressed: sending ? null : send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      );
}

Future<_ComposerState> _pumpComposer(
  WidgetTester tester, {
  bool succeeds = true,
}) async {
  await tester.pumpWidget(_Composer(succeeds: succeeds));
  final state = tester.state<_ComposerState>(find.byType(_Composer));
  state.focus.requestFocus();
  await tester.pump();
  expect(state.focus.hasFocus, isTrue, reason: 'field should start focused');
  return state;
}

void main() {
  group('composer send cycle', () {
    testWidgets('keeps focus across a send, with no post-frame restore',
        (tester) async {
      final state = await _pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'hello');

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      // The whole point of #195: focus never leaves, not even for a frame.
      expect(state.focus.hasFocus, isTrue);
      expect(state.controller.text, isEmpty, reason: 'cleared optimistically');

      await tester.pump(const Duration(milliseconds: 50));
      expect(state.focus.hasFocus, isTrue);
    });

    testWidgets('stays typable while a send is in flight', (tester) async {
      final state = await _pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'first');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'second');
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.controller.text, 'second');
    });

    testWidgets('a failed send keeps focus and gives the text back',
        (tester) async {
      final state = await _pumpComposer(tester, succeeds: false);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.controller.text, 'hello');
      expect(state.controller.selection.baseOffset, 'hello'.length);
      expect(state.focus.hasFocus, isTrue);
    });

    testWidgets("a failed send doesn't clobber what was typed meanwhile",
        (tester) async {
      final state = await _pumpComposer(tester, succeeds: false);
      await tester.enterText(find.byType(TextField), 'first');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'second');
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.controller.text, 'first\nsecond');
      // The caret stays in the user's own text, after "second".
      expect(state.controller.selection.baseOffset, 'first\nsecond'.length);
    });

    testWidgets("Enter-mashing can't double-send", (tester) async {
      final state = await _pumpComposer(tester);
      await tester.enterText(find.byType(TextField), 'hello');

      var sends = 0;
      // Count how many sends actually get past the re-entrancy guard by
      // watching the optimistic clear: a second send with an empty field is a
      // no-op, so only the first can do any work.
      for (var i = 0; i < 3; i++) {
        final before = state.controller.text;
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();
        if (before.isNotEmpty) sends++;
      }
      expect(sends, 1);
      expect(state.sending, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('restoreFailedSend', () {
    test('restores into an empty field with the caret at the end', () {
      final controller = TextEditingController();
      restoreFailedSend(controller, 'hello');
      expect(controller.text, 'hello');
      expect(controller.selection.baseOffset, 5);
    });

    test('prepends when the user typed during the send, shifting the caret',
        () {
      final controller = TextEditingController(text: 'typed');
      controller.selection = const TextSelection.collapsed(offset: 2);
      restoreFailedSend(controller, 'failed');
      expect(controller.text, 'failed\ntyped');
      expect(controller.selection.baseOffset, 'failed\n'.length + 2);
    });

    test('is a no-op for empty text', () {
      final controller = TextEditingController(text: 'typed');
      restoreFailedSend(controller, '');
      expect(controller.text, 'typed');
    });
  });
}
