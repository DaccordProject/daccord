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

RestResult _spaces(
  String name, {
  List<String> tags = const [],
  String serverUrl = 'https://accord.example.test',
}) => RestResult.success(200, [
  {
    'space_id': name.toLowerCase().replaceAll(' ', '-'),
    'server_url': serverUrl,
    'name': name,
    'tags': tags,
  },
]);

const _sparseHeading = 'This list is short on purpose';

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

  testWidgets('shows an error for a non-list directory payload', (
    tester,
  ) async {
    Future<RestResult> browse({
      required String masterUrl,
      required String query,
      required String tag,
    }) async => RestResult.success(200, {
      'spaces': {'space_id': 'not-a-list'},
    });

    await tester.pumpWidget(_host(browse));
    await tester.pump();

    expect(
      find.text('The server returned an invalid directory response'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows an error when the directory payload is missing', (
    tester,
  ) async {
    Future<RestResult> browse({
      required String masterUrl,
      required String query,
      required String tag,
    }) async => RestResult.success(200, {'page': 1});

    await tester.pumpWidget(_host(browse));
    await tester.pump();

    expect(
      find.text('The server returned an invalid directory response'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a near-empty directory explains itself and offers a way in', (
    tester,
  ) async {
    Future<RestResult> browse({
      required String masterUrl,
      required String query,
      required String tag,
    }) async => _spaces('Daccord Official');

    await tester.pumpWidget(_host(browse));
    await tester.pump();

    expect(find.text('Daccord Official'), findsOneWidget);
    expect(find.text(_sparseHeading), findsOneWidget);
    expect(find.text('Connect to a server by URL'), findsOneWidget);
    expect(find.text('Host your own'), findsOneWidget);
  });

  testWidgets('an empty directory still offers the manual-connect footer', (
    tester,
  ) async {
    Future<RestResult> browse({
      required String masterUrl,
      required String query,
      required String tag,
    }) async => RestResult.success(200, const []);

    await tester.pumpWidget(_host(browse));
    await tester.pump();

    expect(find.text('No servers found'), findsOneWidget);
    expect(find.text(_sparseHeading), findsOneWidget);
    expect(find.text('Connect to a server by URL'), findsOneWidget);
  });

  testWidgets('a search that matched nothing is not blamed on the directory', (
    tester,
  ) async {
    Future<RestResult> browse({
      required String masterUrl,
      required String query,
      required String tag,
    }) async => query.isEmpty
        ? _spaces('Daccord Official')
        : RestResult.success(200, const []);

    await tester.pumpWidget(_host(browse));
    await tester.pump();
    expect(find.text(_sparseHeading), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('No servers found'), findsOneWidget);
    expect(find.text(_sparseHeading), findsNothing);
    // The way out of a dead end is still there.
    expect(find.text('Connect to a server by URL'), findsOneWidget);
  });

  testWidgets(
    'a failed join reports itself while the listing stays on screen',
    (tester) async {
      // A listing with no server URL fails in `_join` before any network call,
      // which is exactly the case that used to render nothing at all: the
      // error was only painted inside the `listings.isEmpty` branch (#292).
      Future<RestResult> browse({
        required String masterUrl,
        required String query,
        required String tag,
      }) async => _spaces('Daccord Official', serverUrl: '');

      await tester.pumpWidget(_host(browse));
      await tester.pump();
      expect(find.text('Daccord Official'), findsOneWidget);
      expect(
        find.text('This listing is missing its server details'),
        findsNothing,
      );

      await tester.tap(find.text('Join'));
      await tester.pump();

      expect(
        find.text('This listing is missing its server details'),
        findsOneWidget,
      );
      // ...and the listing it applies to is still visible next to it.
      expect(find.text('Daccord Official'), findsOneWidget);
    },
  );
}
