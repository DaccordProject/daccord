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
  nord('Nord');

  const AppThemePreset(this.label);

  final String label;

  static AppThemePreset fromName(String? name) =>
      AppThemePreset.values.firstWhere(
        (p) => p.name == name,
        orElse: () => AppThemePreset.dark,
      );
}

/// The fixed palette for a preset, before any user accent override is applied.
const Map<AppThemePreset, BonfireThemeExtension> _palettes = {
  AppThemePreset.dark: BonfireThemeExtension(
    background: Color(0xFF14161A),
    foreground: Color(0xFF21252B),
    dirtyWhite: Color(0xFFE4E5E8),
    gray: Color(0xFF818491),
    darkGray: Color(0xFF18191F),
    primary: Color(0xFF2448BE),
    red: Color(0xFFED4245),
    green: Color(0xFF57F287),
    yellow: Color(0xFFFEE75C),
  ),
  AppThemePreset.midnight: BonfireThemeExtension(
    background: Color(0xFF000000),
    foreground: Color(0xFF14161A),
    dirtyWhite: Color(0xFFE4E5E8),
    gray: Color(0xFF818491),
    darkGray: Color(0xFF0A0B0D),
    primary: Color(0xFF2448BE),
    red: Color(0xFFED4245),
    green: Color(0xFF57F287),
    yellow: Color(0xFFFEE75C),
  ),
  AppThemePreset.light: BonfireThemeExtension(
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFFF2F3F5),
    // dirtyWhite is the high-emphasis text colour throughout the app, so on a
    // light surface it has to be dark.
    dirtyWhite: Color(0xFF1E1F22),
    gray: Color(0xFF6D6F78),
    darkGray: Color(0xFFE3E5E8),
    primary: Color(0xFF2448BE),
    red: Color(0xFFD83C3E),
    green: Color(0xFF248046),
    yellow: Color(0xFFC9A227),
  ),
  AppThemePreset.nord: BonfireThemeExtension(
    background: Color(0xFF2E3440),
    foreground: Color(0xFF3B4252),
    dirtyWhite: Color(0xFFECEFF4),
    gray: Color(0xFF81A1C1),
    darkGray: Color(0xFF272C36),
    primary: Color(0xFF88C0D0),
    red: Color(0xFFBF616A),
    green: Color(0xFFA3BE8C),
    yellow: Color(0xFFEBCB8B),
  ),
};

/// The default accent (primary) colour for a preset — used when the user has
/// not chosen a custom accent.
Color defaultAccentFor(AppThemePreset preset) => _palettes[preset]!.primary;

Brightness _brightnessFor(AppThemePreset preset) =>
    preset == AppThemePreset.light ? Brightness.light : Brightness.dark;

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
      surface: palette.background,
    ),
    textTheme: _textTheme(palette),
    extensions: [palette],
  );
}
