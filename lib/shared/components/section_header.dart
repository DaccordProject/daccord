import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// A small uppercase label used to head a group of settings/rows.
///
/// Consolidates the identical private `_SectionHeader`/`_Header` widgets that
/// were copy-pasted across the settings, developer, voice and privacy screens.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium!.copyWith(
              color: colors.gray,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}
