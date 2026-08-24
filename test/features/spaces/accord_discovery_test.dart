import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/views/accord_discovery.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

Widget _host(AccordDiscoveryBrowse browse) => ProviderScope(
  overrides: [
    settingsControllerProvider.overrideWith(_FakeSettingsController.new),
    accordDiscoveryBrowseProvider.overrideWithValue(browse),
  ],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: const Scaffold(body: AccordDiscoveryBody()),
  ),
);

RestResult _spaces(String name, {List<String> tags = const []}) =>
    RestResult.success(200, [
      {
        'space_id': name.toLowerCase().replaceAll(' ', '-'),
        'server_url': 'https://accord.example.test',
        'name': name,
        'tags': tags,
      },
    ]);

void main() {
  testWidgets('an older search cannot replace the latest results', (
    tester,
  ) async {
    final pending = <String, Completer<RestResult>>{};
    Future<RestResult> browse({
      required String masterUrl,
      required String query,
      required String tag,
    }) {
      if (query.isEmpty) return Future.value(_spaces('Initial'));
      return pending.putIfAbsent(query, Completer<RestResult>.new).future;
    }

    await tester.pumpWidget(_host(browse));
    await tester.pump();
    expect(find.text('Initial'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'older');
    await tester.pump(const Duration(milliseconds: 400));
    expect(pending, contains('older'));

    await tester.enterText(find.byType(TextField), 'latest');
    await tester.pump(const Duration(milliseconds: 400));
    expect(pending, contains('latest'));

    pending['latest']!.complete(_spaces('Latest result'));
    await tester.pump();
    expect(find.text('Latest result'), findsOneWidget);

    pending['older']!.complete(_spaces('Stale result'));
    await tester.pump();
    expect(find.text('Latest result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
  });
}
