import 'dart:math' as math;
import 'dart:ui';

import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the readability of every selectable theme.
///
/// App Review rejected 0.2.12 under guideline 4.0 for "hard to read type".
/// Two presets were measurably at fault: Solarized put muted text at 3.33:1 and
/// Light put it at 4.12:1, both under the 4.5:1 WCAG AA floor for normal-size
/// text. `dirtyWhite` (high-emphasis) and `gray` (muted) are the two tokens the
/// whole app's typography resolves to — `_textTheme` assigns every `TextTheme`
/// slot one or the other — so checking them against both surfaces covers the
/// body text wholesale.
void main() {
  group('theme contrast', () {
    for (final preset in AppThemePreset.values) {
      test('${preset.label} meets WCAG AA for body text', () {
        final palette = paletteFor(preset);
        for (final (surfaceName, surface) in [
          ('background', palette.background),
          ('foreground', palette.foreground),
        ]) {
          for (final (tokenName, token) in [
            ('dirtyWhite', palette.dirtyWhite),
            ('gray', palette.gray),
          ]) {
            final ratio = _contrastRatio(token, surface);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '${preset.label}: $tokenName on $surfaceName is '
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
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio, 1.0 (identical) to 21.0 (black on white).
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
