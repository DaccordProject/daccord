import 'package:bonfire/shared/components/server_unreachable.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(body: child),
    );

void main() {
  group('ServerUnreachable', () {
    testWidgets('defaults to the "Server unreachable" title', (tester) async {
      await tester.pumpWidget(_host(const ServerUnreachable()));
      expect(find.text('Server unreachable'), findsOneWidget);
      expect(find.text('Trying to reconnect…'), findsOneWidget);
    });

    testWidgets('renders a custom title for a pane-specific failure', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const ServerUnreachable(
        title: "Couldn't load members",
        message: 'Something went wrong fetching the member list.',
      )));
      expect(find.text("Couldn't load members"), findsOneWidget);
      expect(
        find.text('Something went wrong fetching the member list.'),
        findsOneWidget,
      );
      expect(find.text('Server unreachable'), findsNothing);
    });

    testWidgets('hides the Retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(_host(const ServerUnreachable()));
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows and wires the Retry button when onRetry is set', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        _host(ServerUnreachable(onRetry: () => tapped = true)),
      );
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(tapped, isTrue);
    });
  });
}
