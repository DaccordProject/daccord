import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// The title row of a custom dialog: optional leading icon, an ellipsized
/// title, optional [actions], then a close button.
class DialogTitleBar extends StatelessWidget {
  const DialogTitleBar(
    this.title, {
    super.key,
    this.icon,
    this.actions = const [],
    this.onClose,
  });

  final String title;
  final IconData? icon;
  final List<Widget> actions;

  /// Defaults to popping the enclosing route.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: colors.dirtyWhite),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ...actions,
        IconButton(
          tooltip: 'Close',
          onPressed: onClose ?? () => Navigator.of(context).pop(),
          icon: Icon(Icons.close, size: 20, color: colors.gray),
        ),
      ],
    );
  }
}
