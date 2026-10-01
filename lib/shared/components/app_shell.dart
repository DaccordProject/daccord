import 'package:bonfire/features/profiles/views/profile_gate.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/views/incoming_call_overlay.dart';
import 'package:flutter/material.dart';
import 'package:bonfire/features/experiences/views/turn_banner.dart';

/// Upper bound on the combined (system × in-app) text scale; past roughly 2×
/// the app's fixed-height rows clip instead of growing.
const double maxEffectiveTextScale = 2.0;

/// Everything the app's `MaterialApp.router` layers between its chrome (theme,
/// localizations, media query) and the router's Navigator — [child] — via
/// `MaterialApp.builder`:
///
/// 1. the accessibility overrides (UI scale composed with the platform text
///    scale, reduced motion), so they apply to every route;
/// 2. the device-profile PIN gate, which replaces the Navigator with the lock
///    screen until the active profile is unlocked;
/// 3. the incoming-call banner host, above every route so a ring stays
///    answerable from inside a dialog or the full-screen call view (#139).
///
/// This must be the *only* Navigator ancestry the app has: wrapping the router
/// app in another `MaterialApp` makes `rootNavigator: true` lookups (dialogs,
/// the full-screen call view) land in an unthemed Navigator above the ring
/// banner host (#324). Hosting the gate here keeps go_router's navigator root.
Widget buildAppShell(
  BuildContext context,
  Widget? child, {
  required double uiScale,
  required bool reducedMotion,
}) {
  // Compose with the platform text scale (iOS Dynamic Type, Android font
  // size) rather than replacing it.
  final systemScale = MediaQuery.textScalerOf(context).scale(1);
  final combined = (systemScale * uiScale).clamp(
    AccordSettings.minUiScale,
    maxEffectiveTextScale,
  );
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(combined),
      disableAnimations: reducedMotion,
    ),
    // The gate wraps the banner host too: a locked profile shows neither the
    // app nor who is calling it.
    child: ProfileGate(
      child: withIncomingCallOverlay(withExperienceTurns(child)),
    ),
  );
}
