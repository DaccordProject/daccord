import 'package:bonfire/shared/components/color_swatch_chip.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(body: child),
    );

void main() {
  group('avatarColorPalette', () {
    test('has 8 entries', () {
      expect(avatarColorPalette.length, 8);
    });

    test('all entries have a non-empty name', () {
      for (final (_, name) in avatarColorPalette) {
        expect(name, isNotEmpty);
      }
    });
  });

  group('ColorSwatchChip', () {
    testWidgets('renders a 36x36 circle', (tester) async {
      await tester.pumpWidget(
        _host(ColorSwatchChip(
          color: Colors.blue,
          selected: false,
          onTap: () {},
        )),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxWidth, 36);
      expect(container.constraints?.maxHeight, 36);
    });

    testWidgets('shows check icon when selected and not transparent',
        (tester) async {
      await tester.pumpWidget(
        _host(ColorSwatchChip(
          color: Colors.blue,
          selected: true,
          onTap: () {},
        )),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('shows no icon when not selected and not transparent',
        (tester) async {
      await tester.pumpWidget(
        _host(ColorSwatchChip(
          color: Colors.blue,
          selected: false,
          onTap: () {},
        )),
      );
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('shows format_color_reset icon when transparent', (tester) async {
      await tester.pumpWidget(
        _host(ColorSwatchChip(
          color: Colors.blue,
          selected: false,
          onTap: () {},
          transparent: true,
        )),
      );
      expect(find.byIcon(Icons.format_color_reset_outlined), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _host(ColorSwatchChip(
          color: Colors.red,
          selected: false,
          onTap: () => tapped = true,
        )),
      );
      await tester.tap(find.byType(GestureDetector));
      expect(tapped, isTrue);
    });

    testWidgets('wraps in Tooltip when label is provided', (tester) async {
      await tester.pumpWidget(
        _host(ColorSwatchChip(
          color: Colors.green,
          selected: false,
          onTap: () {},
          label: 'Green',
        )),
      );
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('does not wrap in Tooltip when label is null', (tester) async {
      await tester.pumpWidget(
        _host(ColorSwatchChip(
          color: Colors.green,
          selected: false,
          onTap: () {},
        )),
      );
      expect(find.byType(Tooltip), findsNothing);
    });
  });
}
