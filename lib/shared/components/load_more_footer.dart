import 'package:flutter/material.dart';

/// The "Load more" sentinel row appended to cursor-paginated lists (reports,
/// audit log): a centered text button that swaps to a small spinner while the
/// next page is fetched.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    required this.onPressed,
    this.padding = EdgeInsets.zero,
    this.spinnerPadding = EdgeInsets.zero,
  });

  /// Whether the next page is in flight (shows the spinner).
  final bool loading;

  /// Fires the next-page fetch.
  final VoidCallback onPressed;

  /// Padding around the whole footer.
  final EdgeInsetsGeometry padding;

  /// Extra padding around just the spinner (some callers pad only that state).
  final EdgeInsetsGeometry spinnerPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: loading
            ? Padding(
                padding: spinnerPadding,
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : TextButton(
                onPressed: onPressed,
                child: const Text('Load more'),
              ),
      ),
    );
  }
}
