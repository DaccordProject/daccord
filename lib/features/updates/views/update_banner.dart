import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/features/updates/views/updates_page.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A slim banner shown across the top of the app when a newer release is
/// available and the user hasn't dismissed that version. Ports the reference
/// client's `update_banner.gd`. Tapping it opens the Updates page; the ✕
/// dismisses the current version until a newer one ships.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateControllerProvider);
    final skipped = ref.watch(
      settingsControllerProvider.select((s) => s.skippedUpdateVersion),
    );
    final release = update.latest;
    if (!update.updateAvailable ||
        release == null ||
        release.version == skipped ||
        release.version == update.dismissedVersion) {
      return const SizedBox.shrink();
    }

    final colors = BonfireThemeExtension.of(context);
    return Material(
      color: colors.primary,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => showUpdatesSettings(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.system_update, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Update available — ${release.name}. Tap to view.',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                InkWell(
                  onTap: () => ref
                      .read(updateControllerProvider.notifier)
                      .dismissCurrent(),
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
