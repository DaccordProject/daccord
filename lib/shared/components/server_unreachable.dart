import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// A centered "server unreachable" placeholder, shown in panes (channel list,
/// member roster, …) that are still waiting on data from a server whose gateway
/// has dropped. Replaces the otherwise-endless loading spinner so a downed
/// server reads as an error rather than a permanent load.
class ServerUnreachable extends StatelessWidget {
  const ServerUnreachable({
    super.key,
    this.title = 'Server unreachable',
    this.message = 'Trying to reconnect…',
    this.onRetry,
  });

  /// The headline (e.g. 'Server unreachable', or 'Couldn't load members' for a
  /// pane whose own fetch failed while the connection is otherwise up).
  final String title;

  /// The secondary line under the headline (e.g. a hint about retrying).
  final String message;

  /// Forces a fresh reconnect attempt. When null, no retry button is shown.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: colors.gray),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(color: colors.dirtyWhite),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: colors.gray),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.dirtyWhite,
                  backgroundColor: colors.darkGray,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
