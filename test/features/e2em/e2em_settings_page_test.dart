import 'dart:async';

import 'package:bonfire/features/e2em/models/e2em_preferences.dart';
import 'package:bonfire/features/e2em/services/e2em_runtime.dart';
import 'package:bonfire/features/e2em/views/e2em_settings_page.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class PageSettings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
  @override
  void setE2em(E2emPreferences preferences) {
    preferences.validate();
    state = state.copyWith(e2em: preferences);
  }
}

class PageRuntime implements E2emRuntime {
  @override
  bool supported = true;
  int checks = 0;
  Completer<E2emRuntimeStatus>? pending;
  @override
  Future<E2emRuntimeStatus> check(Map<String, dynamic> policy) async {
    checks++;
    return pending == null
        ? const E2emRuntimeStatus(true, 'Connected for this policy')
        : await pending!.future;
  }

  @override
  Future<E2emReport> assess(Map<String, dynamic> request) =>
      throw UnimplementedError();
  @override
  Future<void> connectApp() async {}
  @override
  void close() {}
}

void main() {
  late ProviderContainer container;
  late PageRuntime runtime;

  Future<void> host(
    WidgetTester tester, {
    Size size = const Size(600, 900),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    runtime = PageRuntime();
    container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(PageSettings.new),
        e2emRuntimeProvider.overrideWithValue(runtime),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const E2emSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'enabling checks persists personal settings and strict preset holds matches',
    (tester) async {
      await host(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(container.read(settingsControllerProvider).e2em.enabled, isTrue);
      await tester.ensureVisible(find.text('Strict'));
      await tester.tap(find.text('Strict'));
      await tester.pumpAndSettle();
      final selected = container.read(settingsControllerProvider).e2em;
      expect(selected.categories, e2emCategories.keys);
      expect(selected.response, E2emResponse.review);
      expect(selected.threshold, 0.5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'connection result cannot claim validity after rules changed while checking',
    (tester) async {
      await host(tester);
      runtime.pending = Completer<E2emRuntimeStatus>();
      await tester.tap(find.text('Check connection and rules'));
      await tester.pump();
      container
          .read(settingsControllerProvider.notifier)
          .setE2em(const E2emPreferences(categories: ['abuse.threat']));
      runtime.pending!.complete(
        const E2emRuntimeStatus(true, 'Old policy was valid'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old policy was valid'), findsNothing);
      expect(runtime.checks, 1);
    },
  );

  testWidgets('custom-rule editor validates UTF-8 length and stores the rule', (
    tester,
  ) async {
    await host(tester);
    await tester.scrollUntilVisible(find.text('Add a custom rule'), 500);
    await tester.tap(find.text('Add a custom rule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '🙂' * 129);
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    expect(find.text('Use at most 512 UTF-8 bytes.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      'Keep launch dates private.',
    );
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    expect(container.read(settingsControllerProvider).e2em.customRules, [
      'Keep launch dates private.',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings remain usable at phone width and large text scale', (
    tester,
  ) async {
    await host(tester, size: const Size(320, 900), scale: 1.5);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Add a custom rule'), 300);
    expect(tester.takeException(), isNull);
  });
}
