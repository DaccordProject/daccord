import 'dart:math' as math;

import 'package:bonfire/shared/utils/style/markdown/stylesheet.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the readability of markdown message text.
///
/// The paragraph/list/headline colour used to be hard-coded to #EBEBEB, which
/// sits at ~1:1 on the Light theme's surfaces, so message text was effectively
/// invisible there. This checks every text slot `getMarkdownStyleSheet` sets a
/// colour on against both app surfaces (`background`, where messages render,
/// and `foreground`) for each selectable theme, mirroring
/// `test/theme/theme_contrast_test.dart`.
void main() {
  group('markdown text contrast', () {
    for (final preset in AppThemePreset.values) {
      testWidgets('${preset.label} markdown text meets WCAG AA', (
        tester,
      ) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(preset),
            home: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        );

        final palette = BonfireThemeExtension.of(capturedContext);
        final style = getMarkdownStyleSheet(capturedContext);
        final slots = {
          'paragraph': style.paragraph,
          'list': style.list,
          'listItem': style.listItem,
          'headline1': style.headline1,
          'headline2': style.headline2,
          'headline3': style.headline3,
          'headline4': style.headline4,
          'headline5': style.headline5,
          'headline6': style.headline6,
        };

        for (final MapEntry(key: slot, value: textStyle) in slots.entries) {
          final color = textStyle?.color;
          expect(color, isNotNull, reason: '$slot has no color set');
          for (final (surfaceName, surface) in [
            ('background', palette.background),
            ('foreground', palette.foreground),
          ]) {
            final ratio = _contrastRatio(color!, surface);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '${preset.label}: $slot on $surfaceName is '
                  '${ratio.toStringAsFixed(2)}:1, below the 4.5:1 AA floor',
            );
          }
        }
      });
    }
  });
}

/// WCAG 2.1 relative luminance.
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio, 1.0 (identical) to 21.0 (black on white).
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
