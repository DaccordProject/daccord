import 'package:bonfire/features/onboarding/controllers/onboarding_controller.dart';
import 'package:bonfire/features/onboarding/views/onboarding_overlay.dart';
import 'package:bonfire/features/onboarding/views/onboarding_tour.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _theme = BonfireThemeExtension(
  foreground: Color(0xFF2b2d31),
  background: Color(0xFF1e1f22),
  dirtyWhite: Color(0xFFdcddde),
  gray: Color(0xFF949ba4),
  darkGray: Color(0xFF4e5058),
  primary: Color(0xFF5865f2),
  red: Color(0xFFed4245),
  green: Color(0xFF23a55a),
  yellow: Color(0xFFf0b232),
);

late ProviderContainer _container;

/// A screen with a button that launches the tour, so the real
/// `startOnboardingTour` push/pop/stamp cycle is exercised end to end.
Widget _app() => UncontrolledProviderScope(
  container: _container,
  child: MaterialApp(
    theme: ThemeData(extensions: const [_theme]),
    home: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: TextButton(
            onPressed: () => startOnboardingTour(context, ref),
            child: const Text('launch'),
          ),
        ),
      ),
    ),
  ),
);

OnboardingController get _notifier =>
    _container.read(onboardingControllerProvider.notifier);

void main() {
  // The marker is redirected to an in-memory map rather than Hive: a Hive write
  // issued inside a `testWidgets` body never completes (see
  // OnboardingController.debugStore), which would deadlock the box on teardown.
  setUp(() {
    OnboardingController.debugStore = <String, Object?>{};
    kAppVersion = '9.9.9';
    _container = ProviderContainer();
  });

  tearDown(() {
    _container.dispose();
    OnboardingController.debugStore = null;
    kAppVersion = '0.0.0';
  });

  group('startOnboardingTour', () {
    testWidgets('pushes the walkthrough and stamps the marker on skip', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      expect(_notifier.hasSeenTour, isFalse);

      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingOverlay), findsOneWidget);
      expect(_container.read(onboardingControllerProvider).active, isTrue);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingOverlay), findsNothing);
      expect(_notifier.hasSeenTour, isTrue);
      expect(_notifier.seenVersion, '9.9.9');
      expect(_container.read(onboardingControllerProvider).active, isFalse);
    });

    testWidgets('replay runs the tour again even once the marker is set', (
      tester,
    ) async {
      _notifier.markSeen('1.0.0');
      await tester.pumpWidget(_app());

      // The startup path would bail here...
      expect(_notifier.consumeStartupTrigger(), OnboardingTrigger.alreadySeen);

      // ...but an explicit launch (what the Settings row does) still shows it.
      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingOverlay), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      // Re-stamped with the running version.
      expect(_notifier.seenVersion, '9.9.9');
    });

    testWidgets('the system back gesture also ends (and stamps) the tour', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingOverlay), findsNothing);
      expect(_notifier.hasSeenTour, isTrue);
    });
  });

  group('OnboardingTourPage', () {
    Widget page(double width) => UncontrolledProviderScope(
      container: _container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [_theme]),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 560,
              child: const OnboardingTourPage(),
            ),
          ),
        ),
      ),
    );

    testWidgets('uses the three-pane script on a wide window', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(page(1200));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Spaces live here'), findsOneWidget);
    });

    testWidgets('lays out without overflow on a small phone viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container,
          child: MaterialApp(
            theme: ThemeData(extensions: const [_theme]),
            home: const Scaffold(body: OnboardingTourPage()),
          ),
        ),
      );
      // Walk the whole real script; any RenderFlex overflow fails the test.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('uses the drawer script on a narrow window', (tester) async {
      await tester.pumpWidget(page(400));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // The phone script never claims a rail is visible; it points at the
      // sidebar button instead.
      expect(find.text('Spaces and channels'), findsOneWidget);
      expect(find.text('Spaces live here'), findsNothing);
    });
  });

  group('OnboardingHelpSection', () {
    testWidgets('offers replay and help rows', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container,
          child: MaterialApp(
            theme: ThemeData(extensions: const [_theme]),
            home: const Scaffold(
              body: SingleChildScrollView(child: OnboardingHelpSection()),
            ),
          ),
        ),
      );
      expect(find.text('HELP & TOUR'), findsOneWidget);
      expect(find.text('Replay the app tour'), findsOneWidget);
      expect(find.text('Help & support'), findsOneWidget);
    });

    testWidgets('the help row opens the support sheet', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container,
          child: MaterialApp(
            theme: ThemeData(extensions: const [_theme]),
            home: const Scaffold(
              body: SingleChildScrollView(child: OnboardingHelpSection()),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Help & support'));
      await tester.pumpAndSettle();
      expect(find.text('Documentation'), findsOneWidget);
      expect(find.text('Report a problem'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });
}
