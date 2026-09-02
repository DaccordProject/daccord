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

  testWidgets('a tablet canvas gets the pitch and a self-hosting CTA', (
    tester,
  ) async {
    // iPad Air 11" landscape — the device App Review rejected 0.2.16 on (#292).
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var connected = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: WelcomeView(
                    onBrowse: () {},
                    onManualConnect: () => connected = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Every value prop is on screen, not just the logo and one sentence.
    for (final highlight in kWelcomeHighlights) {
      expect(find.text(highlight.title), findsOneWidget);
      expect(find.text(highlight.body), findsOneWidget);
    }

    // The self-hosting CTA carries comparable weight to "Browse Servers": same
    // height, sitting beside it rather than buried in a text link.
    final browse = find.widgetWithText(ElevatedButton, 'Browse Servers');
    final selfHost = find.widgetWithText(OutlinedButton, 'Run your own server');
    expect(browse, findsOneWidget);
    expect(selfHost, findsOneWidget);
    expect(tester.getSize(selfHost).height, tester.getSize(browse).height);
    expect(tester.getCenter(selfHost).dy, tester.getCenter(browse).dy);

    await tester.tap(selfHost);
    await tester.pumpAndSettle();
    expect(find.text('The Accord desktop app'), findsOneWidget);
    expect(find.text('A server deployment'), findsOneWidget);

    await tester.tap(find.text('Connect by URL'));
    await tester.pumpAndSettle();
    expect(connected, isTrue);
    expect(tester.takeException(), isNull);
  });
}
