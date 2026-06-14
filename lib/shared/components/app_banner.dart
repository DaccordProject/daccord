import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// A slim, full-width banner across the top of the app (update prompts and the
/// like): a primary-tinted [Material] bar with a leading [icon], a single-line
/// [message], optional trailing [actions], and a dismiss ✕.
///
/// Consolidates the identical banner chrome shared by `UpdateBanner` and
/// `WebUpdatePrompt`.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.onTap,
    required this.onDismiss,
    this.actions = const [],
  });

  final IconData icon;
  final String message;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Material(
      color: colors.primary,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                ...actions,
                InkWell(
                  onTap: onDismiss,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
