import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:flutter/material.dart';

/// Shared body layout for the instance-admin tabs (Users / Spaces / Reports):
/// a tab-specific [header] row, an optional inline [error] banner, then the
/// loading → empty → list state switch. The tabs differ in how they load and
/// shape their data but render this same skeleton, so it lives here once.
class AdminListScaffold extends StatelessWidget {
  const AdminListScaffold({
    super.key,
    required this.header,
    required this.error,
    required this.loading,
    required this.isEmpty,
    required this.emptyMessage,
    required this.list,
  });

  /// Tab-specific controls (search field, filter chips, action buttons).
  final Widget header;

  /// Current error message, or null when there's nothing to surface.
  final String? error;

  /// Whether the first load is still in flight.
  final bool loading;

  /// Whether the (post-load) list has no items to show.
  final bool isEmpty;

  /// Message shown in place of an empty list.
  final String emptyMessage;

  /// The populated list, built only when not loading and not empty.
  final Widget list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InlineError(error!, centered: false),
          ),
        Expanded(
          child: loading
              ? const LoadingView()
              : isEmpty
                  ? Center(
                      child: Text(emptyMessage,
                          style: theme.textTheme.bodyMedium))
                  : list,
        ),
      ],
    );
  }
}
