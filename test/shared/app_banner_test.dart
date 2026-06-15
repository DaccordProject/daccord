import 'package:bonfire/shared/components/app_banner.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget banner) => MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(body: banner),
    );

void main() {
  group('AppBanner', () {
    testWidgets('renders message text', (tester) async {
      await tester.pumpWidget(
        _host(AppBanner(
          icon: Icons.info,
          message: 'Hello banner',
          onTap: () {},
          onDismiss: () {},
        )),
      );
      expect(find.text('Hello banner'), findsOneWidget);
    });

    testWidgets('renders leading icon', (tester) async {
      await tester.pumpWidget(
        _host(AppBanner(
          icon: Icons.system_update,
          message: 'Update',
          onTap: () {},
          onDismiss: () {},
        )),
      );
      expect(find.byIcon(Icons.system_update), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _host(AppBanner(
          icon: Icons.info,
          message: 'Tap me',
          onTap: () => tapped = true,
          onDismiss: () {},
        )),
      );
      await tester.tap(find.text('Tap me'));
      expect(tapped, isTrue);
    });

    testWidgets('calls onDismiss when close icon tapped', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        _host(AppBanner(
          icon: Icons.info,
          message: 'msg',
          onTap: () {},
          onDismiss: () => dismissed = true,
        )),
      );
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });

    testWidgets('renders optional actions', (tester) async {
      await tester.pumpWidget(
        _host(AppBanner(
          icon: Icons.info,
          message: 'msg',
          onTap: () {},
          onDismiss: () {},
          actions: [TextButton(onPressed: () {}, child: const Text('Reload'))],
        )),
      );
      expect(find.text('Reload'), findsOneWidget);
    });

    testWidgets('wraps in SafeArea with bottom=false', (tester) async {
      await tester.pumpWidget(
        _host(AppBanner(
          icon: Icons.info,
          message: 'msg',
          onTap: () {},
          onDismiss: () {},
        )),
      );
      final safeArea = tester.widget<SafeArea>(find.byType(SafeArea));
      expect(safeArea.bottom, isFalse);
    });
  });
}
