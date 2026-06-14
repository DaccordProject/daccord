import 'package:bonfire/shared/utils/confirm_dialog.dart';
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

/// Pumps a simple scaffold with a button that opens [showConfirmDialog] and
/// stores the result in [result].
Future<void> _pumpDialog(
  WidgetTester tester, {
  String title = 'Title',
  String message = 'Message',
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool danger = false,
  required ValueNotifier<bool?> result,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [_theme]),
      home: Builder(builder: (ctx) {
        return Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result.value = await showConfirmDialog(
                ctx,
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                cancelLabel: cancelLabel,
                danger: danger,
              );
            },
            child: const Text('open'),
          ),
        );
      }),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('showConfirmDialog', () {
    testWidgets('shows title and message', (tester) async {
      final result = ValueNotifier<bool?>(null);
      await _pumpDialog(tester,
          title: 'Delete?', message: 'This is permanent.', result: result);

      expect(find.text('Delete?'), findsOneWidget);
      expect(find.text('This is permanent.'), findsOneWidget);
    });

    testWidgets('confirm button resolves to true', (tester) async {
      final result = ValueNotifier<bool?>(null);
      await _pumpDialog(tester, confirmLabel: 'Yes', result: result);

      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(result.value, isTrue);
    });

    testWidgets('cancel button resolves to false', (tester) async {
      final result = ValueNotifier<bool?>(null);
      await _pumpDialog(tester, cancelLabel: 'No', result: result);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(result.value, isFalse);
    });

    testWidgets('uses custom confirm and cancel labels', (tester) async {
      final result = ValueNotifier<bool?>(null);
      await _pumpDialog(tester,
          confirmLabel: 'Leave', cancelLabel: 'Stay', result: result);

      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('Stay'), findsOneWidget);
    });

    testWidgets('danger mode sets explicit backgroundColor on confirm button',
        (tester) async {
      final result = ValueNotifier<bool?>(null);
      await _pumpDialog(tester,
          danger: true, confirmLabel: 'Delete', result: result);

      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete'),
      );
      // FilledButton.styleFrom(backgroundColor: ...) sets a non-null property.
      expect(btn.style?.backgroundColor, isNotNull);
    });

    testWidgets('non-danger confirm button has no custom backgroundColor',
        (tester) async {
      final result = ValueNotifier<bool?>(null);
      await _pumpDialog(tester, confirmLabel: 'OK', result: result);

      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'OK'),
      );
      expect(btn.style?.backgroundColor, isNull);
    });
  });
}
