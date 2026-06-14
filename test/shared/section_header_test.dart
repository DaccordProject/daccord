import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _theme = BonfireThemeExtension(
  foreground: Colors.white,
  background: Color(0xFF1e1f22),
  dirtyWhite: Color(0xFFdcddde),
  gray: Color(0xFF949ba4),
  darkGray: Color(0xFF4e5058),
  primary: Color(0xFF5865f2),
  red: Color(0xFFed4245),
  green: Color(0xFF23a55a),
  yellow: Color(0xFFf0b232),
);

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(extensions: [_theme]),
      home: Scaffold(body: child),
    );

void main() {
  group('SectionHeader', () {
    testWidgets('renders title in uppercase', (tester) async {
      await tester.pumpWidget(_wrap(const SectionHeader('hello world')));
      expect(find.text('HELLO WORLD'), findsOneWidget);
    });

    testWidgets('has fromLTRB(16,12,16,4) padding', (tester) async {
      await tester.pumpWidget(_wrap(const SectionHeader('Test')));
      final padding = tester.widget<Padding>(find.byType(Padding).first);
      expect(padding.padding,
          const EdgeInsets.fromLTRB(16, 12, 16, 4));
    });

    testWidgets('accepts a key', (tester) async {
      const k = Key('hdr');
      await tester.pumpWidget(_wrap(const SectionHeader('X', key: k)));
      expect(find.byKey(k), findsOneWidget);
    });
  });
}
