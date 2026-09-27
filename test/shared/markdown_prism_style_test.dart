import 'dart:math' as math;

import 'package:bonfire/shared/utils/style/markdown/stylesheet.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colored [PrismStyle] tokens `getMarkdownPrismStyle` sets. Mirrors
/// `PrismStyle.standardTokenNames` minus `bold`/`italic`, which only carry
/// font weight/style and have no color to check.
const _syntaxTokenNames = [
  'atrule',
  'attr-name',
  'attr-value',
  'boolean',
  'builtin',
  'cdata',
  'char',
  'class-name',
  'comment',
  'constant',
  'deleted',
  'doctype',
  'entity',
  'function',
  'important',
  'inserted',
  'keyword',
  'namespace',
  'number',
  'operator',
  'prolog',
  'property',
  'punctuation',
  'regex',
  'selector',
  'string',
  'symbol',
  'tag',
  'url',
];

/// Guards the readability of highlighted code (#364).
///
/// Inline code and code blocks render on `BonfireThemeExtension.foreground`
/// (`codeblockDecoration` / `codeSpan.backgroundColor`), not on the app
/// background, so this checks every `getMarkdownPrismStyle` syntax colour —
/// and the plain code text colour from `getMarkdownStyleSheet` — against
/// that surface for each selectable theme, mirroring
/// `test/theme/theme_contrast_test.dart`.
void main() {
  group('markdown code contrast', () {
    for (final preset in AppThemePreset.values) {
      testWidgets('${preset.label} code text and syntax colors meet WCAG AA', (
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

        final surface = BonfireThemeExtension.of(capturedContext).foreground;

        final codeColor = getMarkdownStyleSheet(
          capturedContext,
        ).codeBlock?.color;
        expect(codeColor, isNotNull);
        _expectReadable(codeColor!, surface, preset, 'codeBlock');

        final prism = getMarkdownPrismStyle(capturedContext);
        for (final name in _syntaxTokenNames) {
          final color = prism.get(name)?.color;
          expect(color, isNotNull, reason: '$name has no color set');
          _expectReadable(color!, surface, preset, name);
        }
      });
    }
  });
}

void _expectReadable(
  Color token,
  Color surface,
  AppThemePreset preset,
  String tokenName,
) {
  final ratio = _contrastRatio(token, surface);
  expect(
    ratio,
    greaterThanOrEqualTo(4.5),
    reason:
        '${preset.label}: $tokenName on the code surface is '
        '${ratio.toStringAsFixed(2)}:1, below the 4.5:1 AA floor',
  );
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
