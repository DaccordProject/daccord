import 'dart:async';

import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/onboarding/controllers/onboarding_controller.dart';
import 'package:bonfire/features/onboarding/models/onboarding_step.dart';
import 'package:bonfire/features/onboarding/views/onboarding_help.dart';
import 'package:bonfire/features/onboarding/views/onboarding_overlay.dart';
import 'package:bonfire/router/controller.dart';
import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Startup hook for the first-launch walkthrough (#175). Call once from a
/// post-frame callback in `main.dart`. Never throws.
///
/// **Precedence against the other startup dialog.**
///
/// The post-update release notes (#183) can never collide: they are shown only
/// for `ReleaseNotesTrigger.updated`, and the tour only for a first launch with
/// no marker at all. The two conditions are mutually exclusive by construction,
/// and a first install explicitly suppresses the notes.
///
/// Like the release-notes hook, this waits for a signed-in session first: the
/// tour points at the home screen's panes, which don't exist behind the sign-in
/// screen. If the user never signs in this launch nothing is shown and nothing
/// is stamped, so the tour is offered again next time.
Future<void> maybeShowOnboardingOnStartup(WidgetRef ref) async {
  try {
    final notifier = ref.read(onboardingControllerProvider.notifier);
    // Snapshot "is this an existing user?" *before* awaiting anything: signing
    // in persists a session and opening the first channel persists a
    // last-selection, either of which would make a brand-new user look old.
    notifier.captureLaunchState();

    final trigger = notifier.consumeStartupTrigger();
    switch (trigger) {
      case null: // already evaluated this launch
      case OnboardingTrigger.alreadySeen:
      case OnboardingTrigger.replay:
        return;
      case OnboardingTrigger.existingUser:
        // Stamp so the check is cheap forever after, and so the tour can't
        // surface later if their session is ever cleared.
        notifier.markSeen();
        return;
      case OnboardingTrigger.firstLaunch:
        break;
    }

    if (!await _waitForSignIn(ref)) return;
    // Let the home screen finish its first real layout (spaces load, the
    // default channel auto-opens) so the anchors resolve to their settled
    // positions rather than to an empty rail.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await startOnboardingTour(context, ref);
  } catch (e) {
    debugPrint('Onboarding startup check failed: $e');
  }
}

/// Pushes the walkthrough over whatever is on screen and completes when it is
/// dismissed. Stamps the seen-marker on the way out, whether the user finished
/// or skipped.
///
/// A transparent route rather than an `OverlayEntry` so the system back gesture
/// dismisses it for free and the home screen underneath keeps rendering (the
/// tour has to be able to point at it).
Future<void> startOnboardingTour(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final notifier = ref.read(onboardingControllerProvider.notifier);
  notifier.setActive(true);
  try {
    await navigator.push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        // The scrim is painted by the overlay itself (it needs the cut-out), so
        // the route contributes none of its own.
        barrierColor: null,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const OnboardingTourPage(),
      ),
    );
  } finally {
    notifier
      ..markSeen()
      ..setActive(false);
  }
}

/// Replays the walkthrough from Settings.
///
/// Settings is `push`ed over `/spaces`, so the panes the tour describes are
/// behind it — this returns home first, then starts the tour there. Without
/// that every step would fail to resolve an anchor and the tour would degrade
/// to the centred cards this feature exists to avoid.
Future<void> replayOnboardingTour(BuildContext context, WidgetRef ref) async {
  context.go('/spaces');
  // One frame is not enough: the home screen has to mount and lay out its panes
  // before the anchors exist.
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final home = rootNavigatorKey.currentContext;
  if (home == null || !home.mounted) return;
  await startOnboardingTour(home, ref);
}

/// The tour route's content: picks the wide or narrow script from the width the
/// home screen is actually using, and hosts the overlay.
class OnboardingTourPage extends ConsumerWidget {
  const OnboardingTourPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) => OnboardingOverlay(
        steps: onboardingStepsForWidth(constraints.maxWidth),
        searchRoot: rootNavigatorKey.currentContext,
        onFinish: (_) => Navigator.of(context).maybePop(),
      ),
    );
  }
}

/// Completes with true once the session is logged in (immediately when it
/// already is), or false if that hasn't happened within [timeout]. Mirrors the
/// release-notes hook's helper.
Future<bool> _waitForSignIn(
  WidgetRef ref, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  if (ref.read(accordAuthProvider) is AccordAuthLoggedIn) return true;
  final completer = Completer<bool>();
  final sub = ref.listenManual<AccordAuthState>(accordAuthProvider, (_, next) {
    if (next is AccordAuthLoggedIn && !completer.isCompleted) {
      completer.complete(true);
    }
  });
  try {
    return await completer.future.timeout(timeout, onTimeout: () => false);
  } finally {
    sub.close();
  }
}

/// Settings rows for the walkthrough: replay it, or jump straight to help.
///
/// A whole section (header included) so the Settings screen needs one line to
/// adopt it, in both the flat narrow list and the desktop category pane.
class OnboardingHelpSection extends ConsumerWidget {
  const OnboardingHelpSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Help & tour'),
        ListTile(
          leading: Icon(Icons.explore_outlined, color: colors.primary),
          title: const Text('Replay the app tour'),
          subtitle: const Text(
            'Walk through spaces, channels, messaging and voice again.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => replayOnboardingTour(context, ref),
        ),
        ListTile(
          leading: Icon(Icons.help_outline, color: colors.primary),
          title: const Text('Help & support'),
          subtitle: const Text('Documentation, issue tracker and the project.'),
          trailing: const Icon(Icons.open_in_new, size: 16),
          onTap: () => showOnboardingHelpDialog(context),
        ),
      ],
    );
  }
}
