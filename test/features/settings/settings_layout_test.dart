import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/settings/views/accord_settings_screen.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps the screen off Hive (the real controller reads the `accord-settings`
/// box in `build`).
class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

Widget _host({double textScale = 1.0}) => ProviderScope(
  overrides: [
    settingsControllerProvider.overrideWith(_FakeSettingsController.new),
  ],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const AccordSettingsScreen(),
  ),
);

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(textScale: textScale));
  await tester.pump();
}

Finder _sidebar() => find.byKey(const ValueKey('settings-sidebar'));
Finder _column(int i) => find.byKey(ValueKey('settings-column-$i'));

/// `SectionHeader` uppercases its label, so section headings never collide with
/// the sidebar's mixed-case category labels.
Finder _section(String title) => find.text(title.toUpperCase());

Future<void> _selectCategory(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: _sidebar(), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  group('settingsColumnCount', () {
    test('is width-only and steps at 1200 / 1700', () {
      expect(settingsColumnCount(600), 1);
      expect(settingsColumnCount(999), 1);
      expect(settingsColumnCount(kSettingsWideBreakpoint), 1);
      expect(settingsColumnCount(1199), 1);
      expect(settingsColumnCount(kSettingsTwoColumnBreakpoint), 2);
      expect(settingsColumnCount(1699), 2);
      expect(settingsColumnCount(kSettingsThreeColumnBreakpoint), 3);
      expect(settingsColumnCount(3440), 3);
    });
  });

  group('narrow layout', () {
    testWidgets('stays the single flat ListView with no sidebar', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(600, 900));

      expect(_sidebar(), findsNothing);
      expect(_column(0), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('still shows all ten sections and Log out in one scroll', (
      tester,
    ) async {
      // Tall viewport so the whole (lazy) list is laid out at once.
      await _pumpAt(tester, const Size(600, 8000));

      for (final title in const [
        'Appearance',
        'Notifications',
        'Sounds',
        'Voice & Video',
        'Account',
        'Server Directory',
        'Updates',
        'Backup',
        'Developer',
        'About',
      ]) {
        expect(_section(title), findsOneWidget, reason: title);
      }
      // The sub-page tiles are still tiles on narrow layouts.
      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('Privacy & Data'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    });
  });

  group('wide layout', () {
    testWidgets('shows the category sidebar and keeps Log out reachable', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1400, 900));

      expect(_sidebar(), findsOneWidget);
      for (final category in SettingsCategory.values) {
        expect(
          find.descendant(of: _sidebar(), matching: find.text(category.label)),
          findsOneWidget,
          reason: category.label,
        );
      }
      expect(
        find.descendant(of: _sidebar(), matching: find.text('Log out')),
        findsOneWidget,
      );
    });

    testWidgets('Account pane inlines Connections and Privacy as panes', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1400, 900));

      // Account is the default category.
      expect(_section('Account'), findsOneWidget);
      expect(_section('Connections'), findsOneWidget);
      expect(_section('Privacy & Data'), findsOneWidget);
      expect(_section('Server Directory'), findsOneWidget);

      // Privacy content itself is present, not behind a pushed route.
      expect(find.text('Request Data Export'), findsOneWidget);
      expect(_section('Data retention'), findsOneWidget);

      // The redundant "push a sub-page" tiles are gone from the Account card.
      expect(find.text('Privacy & Data'), findsNothing);
      expect(find.text('Connections'), findsNothing);
    });

    testWidgets('every section is reachable from one of the four categories', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1400, 900));

      await _selectCategory(tester, 'App');
      for (final title in const [
        'Appearance',
        'Notifications',
        'Sounds',
        'Voice & Video',
      ]) {
        expect(_section(title), findsOneWidget, reason: title);
      }

      await _selectCategory(tester, 'System');
      for (final title in const ['Updates', 'Backup']) {
        expect(_section(title), findsOneWidget, reason: title);
      }

      await _selectCategory(tester, 'Advanced');
      for (final title in const ['Developer', 'About']) {
        expect(_section(title), findsOneWidget, reason: title);
      }

      await _selectCategory(tester, 'Account');
      expect(_section('Account'), findsOneWidget);
      expect(_section('Server Directory'), findsOneWidget);
    });

    testWidgets('reflows 1 → 2 → 3 columns at 1000 / 1200 / 1700', (
      tester,
    ) async {
      await _pumpAt(tester, const Size(1000, 900));
      expect(_sidebar(), findsOneWidget);
      expect(_column(0), findsOneWidget);
      expect(_column(1), findsNothing);

      await _pumpAt(tester, const Size(1200, 900));
      expect(_column(1), findsOneWidget);
      expect(_column(2), findsNothing);

      await _pumpAt(tester, const Size(1700, 900));
      expect(_column(2), findsOneWidget);
      expect(_column(3), findsNothing);
    });

    testWidgets('caps card width so labels stay next to their controls', (
      tester,
    ) async {
      for (final width in const [1000.0, 1200.0, 1700.0, 3440.0]) {
        await _pumpAt(tester, Size(width, 900));
        await _selectCategory(tester, 'App');
        final columns = settingsColumnCount(width);
        for (var i = 0; i < columns; i++) {
          expect(
            tester.getSize(_column(i)).width,
            lessThanOrEqualTo(kSettingsCardMaxWidth),
            reason: 'width $width, column $i',
          );
        }
      }
    });

    testWidgets('holds up at 150% UI scale', (tester) async {
      // `uiScale` is applied as a TextScaler, so the logical-pixel breakpoints
      // are unchanged; only the rows get taller.
      await _pumpAt(tester, const Size(1200, 900), textScale: 1.5);

      expect(_sidebar(), findsOneWidget);
      expect(_column(1), findsOneWidget);
      expect(_column(2), findsNothing);
      expect(tester.takeException(), isNull);

      await _selectCategory(tester, 'App');
      expect(_section('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
