import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/features/updates/views/updates_page.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUpdateController extends UpdateController {
  _FakeUpdateController(
    this._state, {
    bool canInstallInPlace = false,
    bool requiresPrivilegedInstall = false,
  })  : _canInstallInPlace = canInstallInPlace,
        _requiresPrivilegedInstall = requiresPrivilegedInstall;
  final UpdateState _state;
  final bool _canInstallInPlace;
  final bool _requiresPrivilegedInstall;
  @override
  UpdateState build() => _state;
  @override
  bool get canInstallInPlace => _canInstallInPlace;
  @override
  bool get requiresPrivilegedInstall => _requiresPrivilegedInstall;
}

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

// Version well ahead of kAppVersion so updateAvailable == true.
const _newerRelease = AppRelease(
  version: '99.0.0',
  name: 'v99.0.0',
  notes: '',
  url: '',
  publishedAt: '',
);

Widget _host({
  required UpdateState update,
  bool canInstallInPlace = false,
  bool requiresPrivilegedInstall = false,
}) =>
    ProviderScope(
      overrides: [
        updateControllerProvider.overrideWith(
          () => _FakeUpdateController(
            update,
            canInstallInPlace: canInstallInPlace,
            requiresPrivilegedInstall: requiresPrivilegedInstall,
          ),
        ),
        settingsControllerProvider.overrideWith(() => _FakeSettingsController()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: const UpdatesScreen(),
      ),
    );

void main() {
  group('UpdatesScreen install button label', () {
    testWidgets(
        'reads "Install (admin)" when ready and requiresPrivilegedInstall '
        '(Linux system-package reinstall via pkexec)', (tester) async {
      await tester.pumpWidget(
        _host(
          update: const UpdateState(
            latest: _newerRelease,
            phase: UpdatePhase.ready,
            stagedArchivePath: '/tmp/daccord.deb',
          ),
          canInstallInPlace: true,
          requiresPrivilegedInstall: true,
        ),
      );
      await tester.pump();

      expect(find.text('Install (admin)'), findsOneWidget);
      expect(find.text('Restart & install'), findsNothing);
    });

    testWidgets('reads "Restart & install" when ready and no admin is needed',
        (tester) async {
      await tester.pumpWidget(
        _host(
          update: const UpdateState(
            latest: _newerRelease,
            phase: UpdatePhase.ready,
            stagedArchivePath: '/tmp/daccord.tar.gz',
          ),
          canInstallInPlace: true,
        ),
      );
      await tester.pump();

      expect(find.text('Restart & install'), findsOneWidget);
      expect(find.text('Install (admin)'), findsNothing);
    });

    testWidgets(
        'reads "Download & install (admin)" when idle and requiresPrivilegedInstall',
        (tester) async {
      await tester.pumpWidget(
        _host(
          update: const UpdateState(latest: _newerRelease),
          canInstallInPlace: true,
          requiresPrivilegedInstall: true,
        ),
      );
      await tester.pump();

      expect(find.text('Download & install (admin)'), findsOneWidget);
    });
  });

  group('UpdatesScreen on an app store build', () {
    setUp(() => debugAppStoreBuild = true);
    tearDown(() => debugAppStoreBuild = null);

    testWidgets('offers no check, no download and no GitHub release link', (
      tester,
    ) async {
      // The Settings entry point is hidden on store builds, but even if the
      // page were reached it must not advertise a GitHub release (#292).
      await tester.pumpWidget(
        _host(update: const UpdateState(latest: _newerRelease)),
      );
      await tester.pump();

      expect(find.text('Check for updates'), findsNothing);
      expect(find.text('Check for updates on startup'), findsNothing);
      expect(find.text('View release'), findsNothing);
      expect(find.text('Download'), findsNothing);
      expect(find.text('Skip this version'), findsNothing);
      expect(find.textContaining('Update available'), findsNothing);
      expect(
        find.text('Updates are delivered through the app store.'),
        findsOneWidget,
      );
      // The running build's own version and notes stay available.
      expect(find.text('Current version'), findsOneWidget);
      expect(find.text("What's new in this version"), findsOneWidget);
    });
  });
}
