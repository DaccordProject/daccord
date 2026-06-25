import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _theme = BonfireThemeExtension(
  foreground: Colors.white,
  background: Color(0xFF1e1f22),
  dirtyWhite: Color(0xFFdcddde),
  gray: Color(0xFF949ba4),
  darkGray: Color(0xFF4e5058),
  primary: Color(0xFF5865f2),
  red: Color(0xFFed4245),
  green: Color(0xFF23a55a),
  yellow: Color(0xFFf0b232),
);

RestResult _ok() => RestResult(ok: true, statusCode: 200);
RestResult _err(String msg) => RestResult(
      ok: false,
      statusCode: 500,
      error: AccordError(message: msg),
    );

void main() {
  group('RestResult.errorOr', () {
    test('returns fallback when error is null', () {
      expect(_ok().errorOr('default'), 'default');
    });

    test('returns error.toString() when error is non-null', () {
      final result = _err('boom');
      expect(result.errorOr('default'), result.error!.toString());
    });
  });

  group('showErrorSnack', () {
    testWidgets('shows snack bar with prefix and error', (tester) async {
      final err = AccordError(message: 'server error');
      final result = RestResult(ok: false, statusCode: 500, error: err);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [_theme]),
          home: Builder(builder: (ctx) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () =>
                    showErrorSnack(ctx, result, prefix: 'Failed'),
                child: const Text('trigger'),
              ),
            );
          }),
        ),
      );
      await tester.tap(find.text('trigger'));
      await tester.pump();

      expect(find.text('Failed: ${err.toString()}'), findsOneWidget);
    });

    testWidgets('falls back to "unknown error" when error is null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [_theme]),
          home: Builder(builder: (ctx) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () => showErrorSnack(ctx, _ok(), prefix: 'Oops'),
                child: const Text('trigger'),
              ),
            );
          }),
        ),
      );
      await tester.tap(find.text('trigger'));
      await tester.pump();

      expect(find.text('Oops: unknown error'), findsOneWidget);
    });
  });

  group('showInfoSnack', () {
    testWidgets('shows snack bar with the given message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [_theme]),
          home: Builder(builder: (ctx) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () => showInfoSnack(ctx, 'Settings saved'),
                child: const Text('trigger'),
              ),
            );
          }),
        ),
      );
      await tester.tap(find.text('trigger'));
      await tester.pump();

      expect(find.text('Settings saved'), findsOneWidget);
    });
  });
}
