import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Selectable colour themes for the Accord client. Each preset maps to a
/// [BonfireThemeExtension] palette + a [Brightness]; the user may additionally
/// override the accent (primary) colour via settings.
enum AppThemePreset {
  dark('Dark'),
  midnight('Midnight'),
  light('Light'),
  nord('Nord'),
  monokai('Monokai'),
  solarized('Solarized');

  const AppThemePreset(this.label);

  final String label;

  static AppThemePreset fromName(String? name) =>
      AppThemePreset.values.firstWhere(
        (p) => p.name == name,
        orElse: () => AppThemePreset.dark,
      );
}

/// The fixed palette for a preset, before any user accent override is applied.
///
/// Colours are ported from the reference daccord client's ThemeManager presets,
/// mapping its tokens onto this client's 9-colour palette:
/// background←nav_bg, foreground←panel_bg, darkGray←input_bg,
/// dirtyWhite←text_body, gray←text_muted, primary←accent, red←error,
/// green←success, yellow←warning.
const Map<AppThemePreset, BonfireThemeExtension> _palettes = {
  AppThemePreset.dark: BonfireThemeExtension(
    background: Color(0xFF27292C),
    foreground: Color(0xFF2C2E34),
    dirtyWhite: Color(0xFFD5D9DF),
    gray: Color(0xFF939BA3),
    darkGray: Color(0xFF1E1F23),
    primary: Color(0xFF5764F1),
    red: Color(0xFFEC4245),
    green: Color(0xFF43B06D),
    yellow: Color(0xFFFFD833),
  ),
  // AMOLED variant of [dark]: pure-black base, same accent/text tokens.
  AppThemePreset.midnight: BonfireThemeExtension(
    background: Color(0xFF000000),
    foreground: Color(0xFF14161A),
    dirtyWhite: Color(0xFFD5D9DF),
    gray: Color(0xFF939BA3),
    darkGray: Color(0xFF000000),
    primary: Color(0xFF5764F1),
    red: Color(0xFFEC4245),
    green: Color(0xFF43B06D),
    yellow: Color(0xFFFFD833),
  ),
  AppThemePreset.light: BonfireThemeExtension(
    background: Color(0xFFE8EAED),
    foreground: Color(0xFFF4F4F7),
    // dirtyWhite is the high-emphasis text colour throughout the app, so on a
    // light surface it has to be dark.
    dirtyWhite: Color(0xFF2D3338),
    gray: Color(0xFF6B707A),
    darkGray: Color(0xFFE0E2E5),
    primary: Color(0xFF5764F1),
    red: Color(0xFFD82D33),
    green: Color(0xFF2D9959),
    yellow: Color(0xFFE5BF00),
  ),
  AppThemePreset.nord: BonfireThemeExtension(
    background: Color(0xFF282C38),
    foreground: Color(0xFF2D3440),
    dirtyWhite: Color(0xFFD7DEE9),
    gray: Color(0xFF9DAABB),
    darkGray: Color(0xFF212730),
    primary: Color(0xFF81A0C1),
    red: Color(0xFFBE606A),
    green: Color(0xFFA2BD8B),
    yellow: Color(0xFFEBCA8A),
  ),
  AppThemePreset.monokai: BonfireThemeExtension(
    background: Color(0xFF21211B),
    foreground: Color(0xFF282820),
    dirtyWhite: Color(0xFFF8F8F1),
    gray: Color(0xFF99998C),
    darkGray: Color(0xFF1D1D16),
    primary: Color(0xFFA2D439),
    red: Color(0xFFFA5D5D),
    green: Color(0xFFA2D439),
    yellow: Color(0xFFE6DB74),
  ),
  AppThemePreset.solarized: BonfireThemeExtension(
    background: Color(0xFF00242D),
    foreground: Color(0xFF002B36),
    dirtyWhite: Color(0xFF839395),
    gray: Color(0xFF647A83),
    darkGray: Color(0xFF063642),
    primary: Color(0xFF258AD2),
    red: Color(0xFFDC312E),
    green: Color(0xFF859900),
    yellow: Color(0xFFB58800),
  ),
};

/// The default accent (primary) colour for a preset — used when the user has
/// not chosen a custom accent.
Color defaultAccentFor(AppThemePreset preset) => _palettes[preset]!.primary;

Brightness _brightnessFor(AppThemePreset preset) =>
    preset == AppThemePreset.light ? Brightness.light : Brightness.dark;

/// A readable foreground (text/icon) colour for content sitting on [background].
Color _onColor(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

/// Builds the [BonfireThemeExtension] for [preset], substituting [accent] for
/// the preset's default primary when provided.
BonfireThemeExtension paletteFor(AppThemePreset preset, {Color? accent}) {
  final base = _palettes[preset]!;
  return accent == null ? base : base.copyWith(primary: accent);
}

TextTheme _textTheme(BonfireThemeExtension palette) {
  final family = GoogleFonts.publicSans().fontFamily!;
  final high = palette.dirtyWhite;
  final medium = palette.gray;
  return TextTheme(
    displayLarge:
        TextStyle(fontSize: 36, fontFamily: family, fontWeight: FontWeight.w500),
    displayMedium:
        TextStyle(fontSize: 20, fontFamily: family, fontWeight: FontWeight.w500),
    displaySmall:
        TextStyle(fontSize: 15, fontFamily: family, fontWeight: FontWeight.w500),
    titleLarge: TextStyle(
        fontSize: 36,
        fontFamily: family,
        fontWeight: FontWeight.w500,
        color: high),
    titleMedium: TextStyle(
        fontSize: 20,
        fontFamily: family,
        fontWeight: FontWeight.w500,
        color: high),
    titleSmall: TextStyle(
        fontSize: 15,
        fontFamily: family,
        fontWeight: FontWeight.w500,
        color: high),
    headlineLarge:
        TextStyle(fontSize: 18, fontWeight: FontWeight.w500, fontFamily: family),
    labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        fontFamily: family,
        color: medium),
    labelMedium: TextStyle(
        fontSize: 12,
        fontFamily: family,
        fontWeight: FontWeight.w500,
        color: medium),
    bodyLarge: TextStyle(
        fontSize: 15,
        fontFamily: family,
        color: high,
        fontWeight: FontWeight.w500),
    bodyMedium: TextStyle(
        fontSize: 14,
        fontFamily: family,
        color: medium,
        fontWeight: FontWeight.w500),
  );
}

/// Builds the [ThemeData] for [preset], applying an optional custom [accent].
ThemeData buildAppTheme(AppThemePreset preset, {Color? accent}) {
  final palette = paletteFor(preset, accent: accent);
  final brightness = _brightnessFor(preset);
  final base =
      brightness == Brightness.light ? ThemeData.light() : ThemeData.dark();
  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: brightness,
    ).copyWith(
      primary: palette.primary,
      // fromSeed derives onPrimary for its generated primary tone, not the
      // accent we force above — so a light accent (e.g. Nord, or a custom one)
      // would otherwise get light text. Pick the on-colour by luminance.
      onPrimary: _onColor(palette.primary),
      error: palette.red,
      onError: _onColor(palette.red),
      surface: palette.background,
    ),
    textTheme: _textTheme(palette),
    extensions: [palette],
  );
}
