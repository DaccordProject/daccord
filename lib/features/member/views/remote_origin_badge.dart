import 'package:flutter/material.dart';

import 'package:bonfire/theme/theme.dart';

/// A subtle "federated" marker for content homed on a remote server. Renders a
/// small globe glyph and, optionally, the home `@domain` suffix in a muted
/// color. Returns an empty widget for local content so callers can pass a
/// nullable [domain] unconditionally.
///
/// Used across the message author line, member list, profile popout, and space
/// header so remote provenance reads consistently.
class RemoteOriginBadge extends StatelessWidget {
  const RemoteOriginBadge({
    super.key,
    required this.domain,
    this.showDomain = true,
    this.iconSize = 12,
  });

  /// The home domain (e.g. `b.example`), or null/empty for local content.
  final String? domain;

  /// Whether to render the `@domain` text after the glyph. When false only the
  /// glyph shows (e.g. as a compact avatar overlay).
  final bool showDomain;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final d = domain;
    if (d == null || d.isEmpty) return const SizedBox.shrink();
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Homed on $d',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public, size: iconSize, color: colors.gray),
          if (showDomain) ...[
            const SizedBox(width: 3),
            Text(
              '@$d',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.gray),
            ),
          ],
        ],
      ),
    );
  }
}
