import 'package:flutter/material.dart';

/// Tiny rounded pill used to tag a row with a short status label — e.g. the
/// admin user list's "Admin"/"Disabled" badges and the device-profiles page's
/// "Active" marker.
///
/// By default the pill tints its background with a translucent [color] and
/// draws the text in [color]; pass [filled] for a solid [color] background
/// with white text.
class LabelPill extends StatelessWidget {
  const LabelPill(this.text, {super.key, required this.color, this.filled = false});

  final String text;
  final Color color;

  /// Solid [color] background with white text instead of the tinted style.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: filled ? Colors.white : color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
