import 'package:bonfire/shared/components/settings_scaffold.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: child,
    );

void main() {
  group('SettingsScaffold', () {
    testWidgets('renders title in AppBar', (tester) async {
      await tester.pumpWidget(
        _host(const SettingsScaffold(
          title: 'My Settings',
          body: SizedBox(),
        )),
      );
      expect(find.text('My Settings'), findsOneWidget);
    });

    testWidgets('renders body content', (tester) async {
      await tester.pumpWidget(
        _host(SettingsScaffold(
          title: 'X',
          body: const Text('body content'),
        )),
      );
      expect(find.text('body content'), findsOneWidget);
    });

    testWidgets('renders optional actions in AppBar', (tester) async {
      await tester.pumpWidget(
        _host(SettingsScaffold(
          title: 'X',
          body: const SizedBox(),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {},
            ),
          ],
        )),
      );
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('renders back button', (tester) async {
      await tester.pumpWidget(
        _host(SettingsScaffold(
          title: 'X',
          body: const SizedBox(),
        )),
      );
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('renders floatingActionButton when provided', (tester) async {
      await tester.pumpWidget(
        _host(SettingsScaffold(
          title: 'X',
          body: const SizedBox(),
          floatingActionButton: FloatingActionButton(
            onPressed: () {},
            child: const Icon(Icons.add),
          ),
        )),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
