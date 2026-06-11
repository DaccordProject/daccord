import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/features/updates/views/update_banner.dart';
import 'package:bonfire/features/updates/views/web_update_prompt.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUpdateController extends UpdateController {
  _FakeUpdateController(this._state);
  final UpdateState _state;
  @override
  UpdateState build() => _state;
}

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this._settings);
  final AccordSettings _settings;
  @override
  AccordSettings build() => _settings;
}

// Version well ahead of kAppVersion (0.2.1) so updateAvailable == true.
const _newerRelease = AppRelease(
  version: '99.0.0',
  name: 'v99.0.0',
  notes: '',
  url: '',
  publishedAt: '',
);

Widget _host({required UpdateState update, AccordSettings? settings}) =>
    ProviderScope(
      overrides: [
        updateControllerProvider.overrideWith(
          () => _FakeUpdateController(update),
        ),
        settingsControllerProvider.overrideWith(
          () => _FakeSettingsController(settings ?? const AccordSettings()),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: const Scaffold(body: UpdateBanner()),
      ),
    );

void main() {
  group('UpdateBanner', () {
    testWidgets('collapses to zero height when no update is available',
        (tester) async {
      await tester.pumpWidget(_host(update: const UpdateState()));
      await tester.pump();

      expect(tester.getSize(find.byType(UpdateBanner)).height, 0);
    });

    testWidgets('renders banner text when update is available', (tester) async {
      await tester.pumpWidget(
        _host(update: const UpdateState(latest: _newerRelease)),
      );
      await tester.pump();

      expect(
        find.textContaining('Update available'),
        findsOneWidget,
      );
    });

    testWidgets('wraps content in SafeArea(bottom: false) when visible',
        (tester) async {
      await tester.pumpWidget(
        _host(update: const UpdateState(latest: _newerRelease)),
      );
      await tester.pump();

      final safeArea = tester.widget<SafeArea>(find.byType(SafeArea));
      expect(safeArea.bottom, isFalse);
      expect(safeArea.top, isTrue);
    });

    testWidgets('collapses when dismissedVersion matches release version',
        (tester) async {
      await tester.pumpWidget(
        _host(
          update: const UpdateState(
            latest: _newerRelease,
            dismissedVersion: '99.0.0',
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(UpdateBanner)).height, 0);
    });

    testWidgets('collapses when skippedUpdateVersion matches release version',
        (tester) async {
      await tester.pumpWidget(
        _host(
          update: const UpdateState(latest: _newerRelease),
          settings: const AccordSettings(skippedUpdateVersion: '99.0.0'),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(UpdateBanner)).height, 0);
    });
  });

  group('WebUpdatePrompt', () {
    testWidgets('renders nothing on non-web platforms', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: WebUpdatePrompt())),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(WebUpdatePrompt)).height, 0);
    });
  });
}
