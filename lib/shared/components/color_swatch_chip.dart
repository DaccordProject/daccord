import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// The shared accent / imageless-avatar color palette (ARGB value + name).
const avatarColorPalette = <(int, String)>[
  (0xFF2448BE, 'Blue'),
  (0xFF5865F2, 'Blurple'),
  (0xFF57F287, 'Green'),
  (0xFFEB459E, 'Pink'),
  (0xFFFEE75C, 'Yellow'),
  (0xFFED4245, 'Red'),
  (0xFF88C0D0, 'Cyan'),
  (0xFFFF7A45, 'Orange'),
];

/// A selectable color swatch used by the accent, avatar, folder and role color
/// pickers. Defaults to the 36×36 circle of the accent/avatar pickers; [size],
/// [borderRadius], [borderWidth] and the icon overrides let the folder and
/// role pickers render their smaller / squared variants. A selected swatch
/// gets a light ring and a check icon; [transparent] swaps the check for a
/// "no color" glyph (the avatar then falls back to its auto color).
///
/// Consolidates the identical `_AccentSwatch`/`_ColorSwatch` widgets that were
/// copy-pasted into the settings, profile-edit, folder-color and role-editor
/// screens.
class ColorSwatchChip extends StatelessWidget {
  const ColorSwatchChip({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
    this.transparent = false,
    this.size = 36,
    this.borderRadius,
    this.borderWidth = 3,
    this.icon,
    this.iconColor,
    this.iconSize = 18,
    this.ink = false,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final String? label;
  final bool transparent;

  /// Swatch diameter (circle) or side length (rounded square).
  final double size;

  /// Rounded-square corner radius; null renders the default circle.
  final BorderRadius? borderRadius;

  /// Width of the selection ring.
  final double borderWidth;

  /// Overrides the default glyph (check when [selected], "no color" when
  /// [transparent], none otherwise).
  final IconData? icon;

  /// Overrides the automatic on-color for the glyph.
  final Color? iconColor;
  final double iconSize;

  /// Taps via an [InkWell] (ripple) instead of a bare [GestureDetector].
  final bool ink;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final glyph =
        icon ??
        (transparent
            ? Icons.format_color_reset_outlined
            : (selected ? Icons.check : null));
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: borderRadius,
        border: Border.all(
          color: selected ? colors.dirtyWhite : Colors.transparent,
          width: borderWidth,
        ),
      ),
      child: Icon(
        glyph,
        size: iconSize,
        color: iconColor ?? accordOnColor(color),
      ),
    );
    final swatch = ink
        ? InkWell(onTap: onTap, borderRadius: borderRadius, child: box)
        : GestureDetector(onTap: onTap, child: box);
    final label = this.label;
    if (label == null || label.isEmpty) return swatch;
    return Tooltip(message: label, child: swatch);
  }
}
