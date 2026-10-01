import 'dart:convert';
import 'dart:io';
import 'package:bonfire/features/experiences/views/experience_canvas.dart';
import 'package:experience_runtime/experience_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final package =
      jsonDecode(
            File('tools/experiences/packages/chess.json').readAsStringSync(),
          )
          as Map;
  final frame =
      ExperienceModule.decode(base64Decode(package['module'] as String)).invoke(
        'render',
        [],
        readState: (k, i) => i == 0 ? 4 : 0,
        grantValid: () => true,
      );
  testWidgets(
    'actual WASM frame fits mobile and desktop, with tap and keyboard input',
    (tester) async {
      final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final chosen = <int>[];
      for (final width in [320.0, 960.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: ExperienceCanvas(
                  drawings: frame.drawings,
                  onCell: chosen.add,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(ClipRect)).width,
          width.clamp(0, 640),
        );
        await tester.tap(find.bySemanticsLabel(RegExp('a1, white rook')));
        expect(chosen.last, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(chosen.last, 1);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets('spectator surface exposes pieces without action controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExperienceCanvas(drawings: frame.drawings)),
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel(RegExp('a1, white rook')));
    expect(node.getSemanticsData().flagsCollection.isButton, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(tester.takeException(), isNull);
  });
}
