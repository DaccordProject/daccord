import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/features/updates/views/updates_page.dart';
import 'package:bonfire/theme/theme.dart';
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
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    // A verified build is staged → offer the one-click apply.
    if (update.updateReady) {
      return _Banner(
        label: 'Update ready — ${release.name}. Tap to restart & install.',
        onTap: update.installing ? null : () => notifier.applyUpdate(),
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

    return _Banner(
      label: 'Update available — ${release.name}. Tap to view.',
      onTap: () => showUpdatesSettings(context),
      onDismiss: () => notifier.dismissCurrent(),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.label,
    required this.onTap,
    required this.onDismiss,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Material(
      color: colors.primary,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.system_update, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                InkWell(
                  onTap: onDismiss,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
