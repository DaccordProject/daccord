import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// A small uppercase label used to head a group of settings/rows.
///
/// Consolidates the identical private `_SectionHeader`/`_Header` widgets that
/// were copy-pasted across the settings, developer, voice and privacy screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;

  /// Optional widget pinned to the trailing edge of the header (e.g. a "Clear"
  /// action). When present the title flexes and the right padding tightens.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final label = Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium!.copyWith(
            color: colors.gray,
            letterSpacing: 0.6,
          ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, trailing != null ? 8 : 16, 4),
      child: trailing == null
          ? label
          : Row(
              children: [
                Expanded(child: label),
                trailing!,
              ],
            ),
    );
  }
}
