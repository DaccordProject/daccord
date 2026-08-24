import 'package:bonfire/features/authentication/views/welcome_view.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact welcome keeps server selection visible', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var browsed = false;
    var connected = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: WelcomeView(
                  onBrowse: () => browsed = true,
                  onManualConnect: () => connected = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final browse = find.widgetWithText(ElevatedButton, 'Browse Servers');
    expect(browse, findsOneWidget);
    expect(tester.getCenter(browse).dy, lessThan(400));
    expect(find.textContaining('Crystal-clear'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(browse);
    await tester.tap(find.text('Connect directly to a server'));
    expect(browsed, isTrue);
    expect(connected, isTrue);
  });
}
