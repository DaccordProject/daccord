import 'package:bonfire/features/onboarding/models/onboarding_step.dart';
import 'package:bonfire/features/onboarding/views/onboarding_help.dart';
import 'package:bonfire/features/onboarding/views/onboarding_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('onboardingSteps', () {
    test('both layouts cover spaces, channels, messaging and voice', () {
      for (final wide in [true, false]) {
        final ids = onboardingSteps(wide: wide).map((s) => s.id).toList();
        expect(
          ids,
          containsAll(<String>['spaces', 'channels', 'messaging', 'voice']),
          reason: 'wide=$wide',
        );
        expect(ids.first, 'welcome', reason: 'wide=$wide');
        expect(ids.last, 'help', reason: 'wide=$wide');
      }
    });

    test('the wide script points at the rail and channel list directly', () {
      final steps = onboardingSteps(wide: true);
      final spaces = steps.firstWhere((s) => s.id == 'spaces');
      final channels = steps.firstWhere((s) => s.id == 'channels');
      expect(spaces.anchors, contains(OnboardingAnchorId.spaceRail));
      expect(channels.anchors.first, OnboardingAnchorId.channelList);
    });

    test(
      'the narrow script never points at the rail first — it is in a drawer',
      () {
        for (final step in onboardingSteps(wide: false)) {
          if (step.anchors.isEmpty) continue;
          expect(
            step.anchors.first,
            isNot(OnboardingAnchorId.spaceRail),
            reason: 'step ${step.id} would point off screen on a phone',
          );
        }
        final spaces = onboardingSteps(
          wide: false,
        ).firstWhere((s) => s.id == 'spaces');
        expect(spaces.anchors.first, OnboardingAnchorId.navMenu);
      },
    );

    test('every anchored step has a fallback or a self-evident target', () {
      for (final wide in [true, false]) {
        for (final step in onboardingSteps(wide: wide)) {
          expect(step.isCentered, step.anchors.isEmpty);
        }
      }
    });

    test('width picks the variant at the home screen breakpoint', () {
      expect(
        onboardingStepsForWidth(kOnboardingWideBreakpoint),
        onboardingSteps(wide: true),
      );
      expect(
        onboardingStepsForWidth(kOnboardingWideBreakpoint - 1),
        onboardingSteps(wide: false),
      );
    });
  });

  group('onboardingCalloutOffset', () {
    const overlay = Size(1200, 800);
    const card = Size(360, 200);

    test('centres the card when there is nothing to point at', () {
      expect(
        onboardingCalloutOffset(overlay: overlay, card: card),
        const Offset(420, 300),
      );
    });

    test('prefers directly below a small target', () {
      const target = Rect.fromLTWH(20, 20, 48, 48);
      final offset = onboardingCalloutOffset(
        overlay: overlay,
        card: card,
        target: target,
      );
      expect(offset.dy, target.bottom + kOnboardingCalloutGap);
      // Centred on the target, but never past the screen edge.
      expect(offset.dx, kOnboardingCalloutMargin);
    });

    test('flips above when there is no room below', () {
      const target = Rect.fromLTWH(400, 700, 400, 90);
      final offset = onboardingCalloutOffset(
        overlay: overlay,
        card: card,
        target: target,
      );
      expect(offset.dy, target.top - kOnboardingCalloutGap - card.height);
    });

    test('sits beside a full-height target like the space rail', () {
      const rail = Rect.fromLTWH(0, 0, 72, 800);
      final offset = onboardingCalloutOffset(
        overlay: overlay,
        card: card,
        target: rail,
      );
      expect(offset.dx, rail.right + kOnboardingCalloutGap);
      expect(offset.dy, (overlay.height - card.height) / 2);
    });

    test('sits to the left when a full-height target hugs the right edge', () {
      const pane = Rect.fromLTWH(900, 0, 300, 800);
      final offset = onboardingCalloutOffset(
        overlay: overlay,
        card: card,
        target: pane,
      );
      expect(offset.dx, pane.left - kOnboardingCalloutGap - card.width);
    });

    test('falls back to centred when the target fills the screen', () {
      final offset = onboardingCalloutOffset(
        overlay: overlay,
        card: card,
        target: Offset.zero & overlay,
      );
      expect(offset, const Offset(420, 300));
    });

    test('never places the card off screen on a tiny viewport', () {
      const tiny = Size(320, 480);
      const bigCard = Size(300, 460);
      for (final target in <Rect?>[
        null,
        const Rect.fromLTWH(0, 0, 320, 480),
        const Rect.fromLTWH(10, 400, 40, 40),
      ]) {
        final offset = onboardingCalloutOffset(
          overlay: tiny,
          card: bigCard,
          target: target,
        );
        expect(offset.dx, greaterThanOrEqualTo(0));
        expect(offset.dy, greaterThanOrEqualTo(0));
        expect(offset.dx + bigCard.width, lessThanOrEqualTo(tiny.width));
        expect(offset.dy + bigCard.height, lessThanOrEqualTo(tiny.height));
      }
    });
  });

  group('help links', () {
    test('every destination is an absolute https URL', () {
      expect(kOnboardingHelpLinks, isNotEmpty);
      for (final link in kOnboardingHelpLinks) {
        final uri = Uri.parse(link.url);
        expect(uri.scheme, 'https', reason: link.url);
        expect(uri.host, isNotEmpty, reason: link.url);
        expect(link.label, isNotEmpty);
      }
    });

    test('includes a route to the issue tracker', () {
      expect(
        kOnboardingHelpLinks.any((l) => l.url.contains('/issues')),
        isTrue,
      );
    });
  });
}
