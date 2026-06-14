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

/// A 36×36 circular color swatch used by the accent and avatar color pickers.
/// A selected swatch gets a light ring and a check icon; [transparent] swaps the
/// check for a "no color" glyph (the avatar then falls back to its auto color).
///
/// Consolidates the identical `_AccentSwatch`/`_ColorSwatch` widgets that were
/// copy-pasted into the settings and profile-edit screens.
class ColorSwatchChip extends StatelessWidget {
  const ColorSwatchChip({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
    this.transparent = false,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final String? label;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final swatch = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.dirtyWhite : Colors.transparent,
            width: 3,
          ),
        ),
        child: Icon(
          transparent
              ? Icons.format_color_reset_outlined
              : (selected ? Icons.check : null),
          size: 18,
          color: accordOnColor(color),
        ),
      ),
    );
    final label = this.label;
    if (label == null || label.isEmpty) return swatch;
    return Tooltip(message: label, child: swatch);
  }
}
