import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the Updates page (current version, manual check, and the available
/// release with a link to download). Ports the reference client's
/// `app_settings_updates_page.gd`. The client doesn't self-install, so the
/// download action opens the release page in the browser.
Future<void> showUpdatesSettings(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const UpdatesScreen()));
}

class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final update = ref.watch(updateControllerProvider);
    final notifier = ref.read(updateControllerProvider.notifier);
    final autoCheck = ref.watch(
      settingsControllerProvider.select((s) => s.autoUpdateCheck),
    );
    final settings = ref.read(settingsControllerProvider.notifier);

    final release = update.latest;
    final available = update.updateAvailable;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.foreground,
        title: const Text('Updates'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            title: const Text('Current version'),
            trailing: Text(
              'v$kAppVersion',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SwitchListTile(
            title: const Text('Check for updates on startup'),
            value: autoCheck,
            onChanged: settings.setAutoUpdateCheck,
          ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: update.checking
                      ? null
                      : () => notifier.check(manual: true),
                  icon: update.checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    update.checking ? 'Checking…' : 'Check for updates',
                  ),
                ),
              ],
            ),
          ),
          if (update.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                update.error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: colors.red),
              ),
            )
          else if (update.checkedOnce && !available)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: colors.green),
                  const SizedBox(width: 6),
                  Text(
                    "You're up to date.",
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(color: colors.green),
                  ),
                ],
              ),
            ),
          if (available && release != null) ...[
            const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Update available: ${release.name}',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall!.copyWith(color: colors.primary),
              ),
            ),
            if (release.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  release.notes,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Builder(
                    builder: (context) {
                      // Prefer the matching platform asset (one-click download
                      // of the right file); fall back to the release page.
                      final assetUrl = notifier.platformAssetUrl();
                      final target = assetUrl ?? release.url;
                      return FilledButton.icon(
                        onPressed: target.isEmpty
                            ? null
                            : () => launchUrl(
                                Uri.parse(target),
                                mode: LaunchMode.externalApplication,
                              ),
                        icon: const Icon(Icons.download),
                        label: Text(
                          assetUrl != null ? 'Download' : 'View release',
                        ),
                      );
                    },
                  ),
                  TextButton(
                    onPressed: () {
                      notifier.skipCurrent();
                      Navigator.of(context).maybePop();
                    },
                    child: const Text('Skip this version'),
                  ),
                ],
              ),
            ),
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'On the web, refresh the page to load the latest version.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: colors.gray),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
