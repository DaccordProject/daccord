import 'package:bonfire/shared/utils/ban_dialog.dart';
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

/// Pumps a scaffold whose button opens [showBanDialog] and stores the outcome
/// in [result].
Future<void> _pumpDialog(
  WidgetTester tester, {
  required ValueNotifier<BanRequest?> result,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [_theme]),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result.value = await showBanDialog(ctx, memberName: 'Bob');
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('names the member being banned', (tester) async {
    final result = ValueNotifier<BanRequest?>(null);
    await _pumpDialog(tester, result: result);
    expect(
      find.text('Bob will be banned from the space and removed.'),
      findsOneWidget,
    );
  });

  testWidgets('keeps message history by default', (tester) async {
    final result = ValueNotifier<BanRequest?>(null);
    await _pumpDialog(tester, result: result);
    expect(find.text("Don't delete any"), findsOneWidget);

    await tester.tap(find.text('Ban'));
    await tester.pumpAndSettle();
    expect(result.value?.deleteMessageSeconds, 0);
    // Nothing to purge means the field is left off the request entirely, so a
    // ban still looks the way it always did to an older server.
    expect(result.value?.toJson(), isEmpty);
  });

  testWidgets('returns the chosen purge window', (tester) async {
    final result = ValueNotifier<BanRequest?>(null);
    await _pumpDialog(tester, result: result);

    await tester.tap(find.text("Don't delete any"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous 24 hours').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ban'));
    await tester.pumpAndSettle();

    expect(result.value?.deleteMessageSeconds, 86400);
    expect(result.value?.toJson(), {'delete_message_seconds': 86400});
  });

  testWidgets('cancelling resolves to null', (tester) async {
    final result = ValueNotifier<BanRequest?>(null);
    await _pumpDialog(tester, result: result);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
  });
}
