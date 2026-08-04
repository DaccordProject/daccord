import 'package:bonfire/shared/utils/refocus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces every composer's send cycle: the field is disabled while the send
/// is in flight, and [TextInputAction.send] unfocuses it on submit.
class _Composer extends StatefulWidget {
  const _Composer({required this.restoreFocus});

  /// How focus is restored once the send completes — the whole point of the
  /// test is that these two are not equivalent.
  final void Function(FocusNode node) restoreFocus;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _focus = FocusNode();
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (!mounted) return;
    setState(() => _sending = false);
    widget.restoreFocus(_focus);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: !_sending,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
          ),
        ),
      );
}

/// Focuses the field, submits it, and lets the send settle. Returns whether the
/// field ended up focused again.
Future<bool> _focusSurvivesSend(
  WidgetTester tester,
  void Function(FocusNode) restoreFocus,
) async {
  await tester.pumpWidget(_Composer(restoreFocus: restoreFocus));
  final node = tester.state<_ComposerState>(find.byType(_Composer))._focus;

  node.requestFocus();
  await tester.pump();
  expect(node.hasFocus, isTrue, reason: 'field should start focused');

  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
  expect(node.hasFocus, isFalse, reason: 'submitting unfocuses the field');

  await tester.pump(const Duration(milliseconds: 50)); // send completes
  await tester.pump(); // rebuild re-enables the field
  await tester.pump(); // post-frame callbacks run
  return node.hasFocus;
}

void main() {
  group('refocusAfterFrame', () {
    testWidgets('restores focus after a send that disabled the field',
        (tester) async {
      expect(await _focusSurvivesSend(tester, refocusAfterFrame), isTrue);
    });

    testWidgets('a bare requestFocus in the same turn is silently dropped',
        (tester) async {
      // Guards the reason this helper exists. `setState` only schedules the
      // rebuild that re-enables the field, so at this point the TextField still
      // has canRequestFocus == false and requestFocus returns without queueing.
      // If Flutter ever starts honouring the request, this test fails and the
      // helper can go.
      expect(
        await _focusSurvivesSend(tester, (node) => node.requestFocus()),
        isFalse,
      );
    });
  });
}
