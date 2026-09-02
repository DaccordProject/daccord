import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/features/updates/views/updates_page.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/shared/components/app_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A slim banner shown across the top of the app once a newer release is ready.
///
/// On platforms that self-install, the new build is downloaded and verified in
/// the background first — the banner stays hidden until then, and a single tap
/// applies it (the app restarts into the new version). Platforms that can't
/// self-install (web/iOS, or an older release with no installable asset) fall
/// back to the legacy "tap to view" banner that opens the Updates page. The ✕
/// dismisses the current version until a newer one ships.
///
/// Never shown on app-store builds — those update through the store, so there
/// is no GitHub check to surface (see [isAppStoreBuild]).
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isAppStoreBuild) return const SizedBox.shrink();
    final update = ref.watch(updateControllerProvider);
    final notifier = ref.read(updateControllerProvider.notifier);
    final skipped = ref.watch(
      settingsControllerProvider.select((s) => s.skippedUpdateVersion),
    );
    final release = update.latest;
    if (release == null ||
        release.version == skipped ||
        release.version == update.dismissedVersion) {
      return const SizedBox.shrink();
    }

    // A verified build is staged → offer the one-click apply. A system-package
    // install applies via pkexec, so warn that an admin prompt will appear.
    if (update.updateReady) {
      final tail = notifier.requiresPrivilegedInstall
          ? 'Tap to install (admin required).'
          : 'Tap to restart & install.';
      return AppBanner(
        icon: Icons.system_update,
        message: 'Update ready — ${release.name}. $tail',
        onTap: update.installing ? () {} : () => notifier.applyUpdate(),
        onDismiss: () => notifier.dismissCurrent(),
      );
    }

    // Installable platforms stay silent while the download runs in the
    // background; the banner only appears once it's ready (handled above).
    // Surface the legacy "view" banner only where there's nothing to stage, or
    // when a background download failed so the user can still act.
    final showViewBanner =
        update.updateAvailable &&
        (!notifier.canInstallInPlace || update.phase == UpdatePhase.failed);
    if (!showViewBanner) return const SizedBox.shrink();

    return AppBanner(
      icon: Icons.system_update,
      message: 'Update available — ${release.name}. Tap to view.',
      onTap: () => showUpdatesSettings(context),
      onDismiss: () => notifier.dismissCurrent(),
    );
  }
}
