import 'dart:async';
import 'dart:math' as math;

import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/views/box/accord_markdown_box.dart';
import 'package:bonfire/features/updates/controllers/release_notes_controller.dart';
import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/router/controller.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows the "What's new" notes for [release]. Returns when the user dismisses
/// it.
Future<void> showReleaseNotesDialog(
  BuildContext context,
  AppRelease release,
) => showDialog<void>(
  context: context,
  builder: (_) => ReleaseNotesDialog(release: release),
);

/// A one-shot `What's new in v<x.y.z>` dialog rendering a release's markdown
/// notes (#183). Purely informational — it can't install anything, so it is the
/// same on every platform and flavour, including store builds where the in-app
/// updater is disabled.
class ReleaseNotesDialog extends StatelessWidget {
  const ReleaseNotesDialog({super.key, required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Cap the body so long changelogs scroll instead of pushing the actions
    // off-screen, and stay within a narrow (phone) window.
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      icon: Icon(Icons.auto_awesome, color: colors.primary),
      title: Text("What's new in v${release.version}"),
      // AlertDialog gives its content bounded height, so the scroll view keeps
      // a long changelog from pushing the actions off-screen.
      content: SizedBox(
        width: math.min(460, size.width),
        child: SingleChildScrollView(
          child: AccordMarkdownBox(content: release.notes),
        ),
      ),
      actions: [
        if (release.url.isNotEmpty)
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(release.url),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('View on GitHub'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

/// Startup hook (#183): if this launch is the first on a newer build, fetch that
/// release's notes and show them once.
///
/// Waits for a signed-in session first so the notes never land on top of the
/// sign-in flow, and bails out entirely (without stamping the seen-marker) when
/// the user doesn't sign in this launch — the notes are then offered again next
/// time. Fetch failures, missing releases and empty bodies all fail silent, so
/// there is never an empty sheet; on store/Play builds (no in-app updater) the
/// same version-changed detection drives it.
///
/// Call once from a post-frame callback at startup. Never throws.
Future<void> maybeShowReleaseNotesOnStartup(WidgetRef ref) async {
  try {
    if (!await _waitForSignIn(ref)) return;
    // Let the router mount its navigator (and any first-launch consent dialog
    // settle) before stacking a dialog on top.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final notifier = ref.read(releaseNotesControllerProvider.notifier);
    final release = await notifier.maybeLoadOnStartup();
    if (release == null) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showReleaseNotesDialog(ctx, release);
  } catch (e) {
    debugPrint('Release notes startup check failed: $e');
  }
}

/// Completes with true once the session is logged in (immediately when it
/// already is), or false if that hasn't happened within [timeout].
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

/// Opens the notes for the running version on demand (the Updates page's
/// "What's new" row). Fetches them if they aren't cached yet and reports the
/// miss inline rather than opening an empty dialog.
Future<void> openCurrentReleaseNotes(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(releaseNotesControllerProvider.notifier);
  final release = await notifier.loadNotesForCurrentVersion();
  if (!context.mounted) return;
  if (release == null || release.notes.trim().isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('No release notes published for v$kAppVersion.')),
    );
    return;
  }
  await showReleaseNotesDialog(context, release);
}
