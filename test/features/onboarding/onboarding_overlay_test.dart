import 'package:bonfire/features/onboarding/models/onboarding_step.dart';
import 'package:bonfire/features/onboarding/views/onboarding_anchors.dart';
import 'package:bonfire/features/onboarding/views/onboarding_overlay.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
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

const _steps = <OnboardingStep>[
  OnboardingStep(
    id: 'one',
    title: 'Step one',
    body: 'The first thing.',
    icon: Icons.looks_one,
  ),
  OnboardingStep(
    id: 'two',
    title: 'Step two',
    body: 'The second thing.',
    icon: Icons.looks_two,
    anchors: <OnboardingAnchorId>[OnboardingAnchorId.spaceRail],
  ),
  OnboardingStep(
    id: 'three',
    title: 'Step three',
    body: 'The last thing.',
    icon: Icons.looks_3,
  ),
];

/// Hosts the overlay above a stand-in "app" so anchors have something real to
/// resolve against, exactly as the tour route sits above the home screen.
Widget _wrap({
  required List<OnboardingStep> steps,
  required void Function(bool completed) onFinish,
  Widget? underlay,
  VoidCallback? onHelp,
  GlobalKey<OnboardingOverlayState>? overlayKey,
}) => MaterialApp(
  theme: ThemeData(extensions: const [_theme]),
  home: Scaffold(
    body: Stack(
      children: [
        if (underlay != null) Positioned.fill(child: underlay),
        Positioned.fill(
          child: OnboardingOverlay(
            key: overlayKey,
            steps: steps,
            onFinish: onFinish,
            onHelp: onHelp,
          ),
        ),
      ],
    ),
  ),
);

void main() {
  tearDown(onboardingAnchors.clear);

  group('step navigation', () {
    testWidgets('starts on the first step and shows progress', (tester) async {
      await tester.pumpWidget(_wrap(steps: _steps, onFinish: (_) {}));
      expect(find.text('Step one'), findsOneWidget);
      expect(find.text('The first thing.'), findsOneWidget);
      expect(find.text('Step two'), findsNothing);
      expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);
    });

    testWidgets('Next walks forward, Done finishes', (tester) async {
      bool? completed;
      await tester.pumpWidget(
        _wrap(steps: _steps, onFinish: (c) => completed = c),
      );

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step two'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step three'), findsOneWidget);
      // The last step swaps Next for Done and drops Skip.
      expect(find.text('Next'), findsNothing);
      expect(find.text('Skip'), findsNothing);

      expect(completed, isNull);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
    });

    testWidgets('Back returns to the previous step', (tester) async {
      await tester.pumpWidget(_wrap(steps: _steps, onFinish: (_) {}));
      // Back is hidden on the first step.
      expect(find.text('Back'), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step two'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Step one'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);
    });

    testWidgets('tapping the scrim advances', (tester) async {
      await tester.pumpWidget(_wrap(steps: _steps, onFinish: (_) {}));
      // Top-left corner: on the scrim, well clear of the centred card.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Step two'), findsOneWidget);
    });

    testWidgets('Skip ends the tour without completing it', (tester) async {
      bool? completed;
      await tester.pumpWidget(
        _wrap(steps: _steps, onFinish: (c) => completed = c),
      );
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(completed, isFalse);
    });

    testWidgets('onFinish fires at most once', (tester) async {
      var calls = 0;
      final key = GlobalKey<OnboardingOverlayState>();
      await tester.pumpWidget(
        _wrap(steps: _steps, onFinish: (_) => calls++, overlayKey: key),
      );
      key.currentState!
        ..skip()
        ..skip()
        ..next();
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('a single-step tour finishes immediately', (tester) async {
      bool? completed;
      await tester.pumpWidget(
        _wrap(
          steps: const [
            OnboardingStep(
              id: 'only',
              title: 'Only',
              body: 'One card.',
              icon: Icons.info,
            ),
          ],
          onFinish: (c) => completed = c,
        ),
      );
      expect(find.text('Done'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
    });
  });

  group('help', () {
    testWidgets('every step exposes a help action', (tester) async {
      var helped = 0;
      await tester.pumpWidget(
        _wrap(steps: _steps, onFinish: (_) {}, onHelp: () => helped++),
      );
      for (var i = 0; i < _steps.length; i++) {
        expect(find.byTooltip('Help & support'), findsOneWidget);
        await tester.tap(find.byTooltip('Help & support'));
        await tester.pumpAndSettle();
        if (i < _steps.length - 1) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }
      expect(helped, _steps.length);
    });
  });

  group('anchoring', () {
    testWidgets('spotlights a registered OnboardingAnchor', (tester) async {
      final key = GlobalKey<OnboardingOverlayState>();
      await tester.pumpWidget(
        _wrap(
          steps: _steps,
          onFinish: (_) {},
          overlayKey: key,
          underlay: Row(
            children: const [
              OnboardingAnchor(
                anchor: OnboardingAnchorId.spaceRail,
                child: SizedBox(width: 72, height: 400),
              ),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
      );

      // Step 1 is centred (no anchors) — the card should be roughly mid-screen.
      final centredCardX = tester.getTopLeft(find.text('Step one')).dx;

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step two'), findsOneWidget);

      // Step 2 anchors to the 72px-wide rail on the left edge, so its card is
      // pushed to the right of it rather than sitting on top.
      final anchoredCardX = tester.getTopLeft(find.text('Step two')).dx;
      expect(anchoredCardX, lessThan(centredCardX));
      expect(anchoredCardX, greaterThanOrEqualTo(72));
    });

    testWidgets(
      'a step whose anchor is not on screen degrades to a centred card',
      (tester) async {
        await tester.pumpWidget(_wrap(steps: _steps, onFinish: (_) {}));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        // Nothing registered spaceRail, and there is no home screen to probe:
        // the card renders anyway, centred, instead of throwing.
        expect(find.text('Step two'), findsOneWidget);
        final centreOne = tester.getCenter(find.byType(CustomSingleChildLayout));
        expect(centreOne.dx, closeTo(400, 1)); // 800x600 default test viewport
      },
    );

    testWidgets('anchors unregister when their widget leaves the tree', (
      tester,
    ) async {
      expect(onboardingAnchors.keysFor(OnboardingAnchorId.channelList), isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [_theme]),
          home: const OnboardingAnchor(
            anchor: OnboardingAnchorId.channelList,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      );
      expect(
        onboardingAnchors.keysFor(OnboardingAnchorId.channelList),
        hasLength(1),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [_theme]),
          home: const SizedBox.shrink(),
        ),
      );
      expect(onboardingAnchors.keysFor(OnboardingAnchorId.channelList), isEmpty);
      expect(onboardingAnchors.isEmpty, isTrue);
    });

    testWidgets('a zero-sized anchor is not spotlit', (tester) async {
      final key = GlobalKey<OnboardingOverlayState>();
      await tester.pumpWidget(
        _wrap(
          steps: _steps,
          onFinish: (_) {},
          overlayKey: key,
          underlay: const OnboardingAnchor(
            anchor: OnboardingAnchorId.spaceRail,
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // Falls through to the centred layout rather than punching a 0x0 hole.
      final centre = tester.getCenter(find.byType(CustomSingleChildLayout));
      expect(centre.dx, closeTo(400, 1));
    });
  });
}
