import 'package:flutter/material.dart';

@immutable
class BonfireThemeExtension extends ThemeExtension<BonfireThemeExtension> {
  static BonfireThemeExtension of(BuildContext context) =>
      Theme.of(context).extension<BonfireThemeExtension>()!;

  const BonfireThemeExtension({
    required this.foreground,
    required this.background,
    required this.dirtyWhite,
    required this.gray,
    required this.darkGray,
    required this.primary,
    required this.red,
    required this.green,
    required this.yellow,
  });

  final Color foreground;
  final Color background;
  final Color dirtyWhite;
  final Color gray;
  final Color darkGray;
  final Color primary;
  final Color red;
  final Color green;
  final Color yellow;

  @override
  BonfireThemeExtension copyWith({
    Color? foreground,
    Color? background,
    Color? dirtyWhite,
    Color? gray,
    Color? darkGray,
    Color? primary,
    Color? red,
    Color? green,
    Color? yellow,
  }) {
    return BonfireThemeExtension(
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      dirtyWhite: dirtyWhite ?? this.dirtyWhite,
      gray: gray ?? this.gray,
      darkGray: darkGray ?? this.darkGray,
      primary: primary ?? this.primary,
      red: red ?? this.red,
      green: green ?? this.green,
      yellow: yellow ?? this.yellow,
    );
  }

  @override
  BonfireThemeExtension lerp(
      covariant BonfireThemeExtension? other, double t) {
    if (other == null) return this;
    return BonfireThemeExtension(
      foreground: Color.lerp(foreground, other.foreground, t)!,
      background: Color.lerp(background, other.background, t)!,
      dirtyWhite: Color.lerp(dirtyWhite, other.dirtyWhite, t)!,
      gray: Color.lerp(gray, other.gray, t)!,
      darkGray: Color.lerp(darkGray, other.darkGray, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      red: Color.lerp(red, other.red, t)!,
      green: Color.lerp(green, other.green, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
    );
  }
}
