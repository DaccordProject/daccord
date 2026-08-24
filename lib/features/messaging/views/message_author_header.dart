/// The author line shared by message rows, plus the message-action menu
/// entries common to their context menus. Used by the main channel list row
/// (`message_pane/message_row.dart`) and the thread view's reply rows
/// (`thread_view.dart`).
library;

import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The header row above a message body: optional leading pin icon, the author
/// name (optionally colored by role and tappable to open a profile popout),
/// an optional federated-origin badge, the timestamp, and an optional
/// "(edited)" marker.
///
/// The avatar is intentionally *not* part of this widget — both call sites
/// place it in a gutter outside the name/timestamp cluster (the channel row so
/// grouped messages can swap it for a hover timestamp, the thread row beside a
/// multi-line column), so the largest truly-common unit is the header line
/// itself.
class MessageAuthorHeader extends StatelessWidget {
  const MessageAuthorHeader({
    super.key,
    required this.name,
    required this.time,
    this.nameColor,
    this.onNameTap,
    this.ellipsizeName = false,
    this.pinned = false,
    this.origin,
    this.timeTooltip,
    this.smallTime = false,
    this.edited = false,
    this.onNameLongPressStart,
    this.onNameSecondaryTapUp,
  });

  /// The resolved author display name.
  final String name;

  /// The (already formatted) date-aware timestamp text.
  final String time;

  /// The author's highest colored-role color; null keeps the theme default.
  final Color? nameColor;

  /// Opens the author's profile popout. Null renders the name untappable
  /// (e.g. outside a space, where no popout makes sense).
  final VoidCallback? onNameTap;

  /// Whether to let the name shrink and ellipsize (thread rows, whose dialog
  /// can be narrow) instead of taking its natural width (channel rows).
  final bool ellipsizeName;

  /// Whether to show the leading pin icon (the message is pinned).
  final bool pinned;

  /// The home domain of a remote (federated) author, or null when local.
  final String? origin;

  /// Full timestamp for the tooltip on [time]; null shows no tooltip.
  final String? timeTooltip;

  /// Renders [time] in `labelSmall` (thread rows) instead of `labelMedium`
  /// (channel rows).
  final bool smallTime;

  /// Whether to append the "(edited)" marker.
  final bool edited;
  final GestureLongPressStartCallback? onNameLongPressStart;
  final GestureTapUpCallback? onNameSecondaryTapUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    Widget nameWidget = Text(
      name,
      overflow: ellipsizeName ? TextOverflow.ellipsis : null,
      style: theme.textTheme.titleSmall!.copyWith(color: nameColor),
    );
    if (onNameTap != null) {
      nameWidget = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onNameTap,
          onLongPressStart: onNameLongPressStart,
          onSecondaryTapUp: onNameSecondaryTapUp,
          child: nameWidget,
        ),
      );
    }
    if (ellipsizeName) nameWidget = Flexible(child: nameWidget);
    Widget timeWidget = Text(
      time,
      style:
          (smallTime
                  ? theme.textTheme.labelSmall
                  : theme.textTheme.labelMedium)!
              .copyWith(color: colors.gray),
    );
    if (timeTooltip != null) {
      timeWidget = Tooltip(message: timeTooltip!, child: timeWidget);
    }
    return Row(
      children: [
        if (pinned) ...[
          Icon(Icons.push_pin, size: 12, color: colors.gray),
          const SizedBox(width: 4),
        ],
        nameWidget,
        if (origin != null) ...[
          const SizedBox(width: 5),
          RemoteOriginBadge(domain: origin),
        ],
        const SizedBox(width: 8),
        timeWidget,
        if (edited) ...[
          const SizedBox(width: 6),
          Text(
            '(edited)',
            style: theme.textTheme.labelSmall!.copyWith(color: colors.gray),
          ),
        ],
      ],
    );
  }
}

/// The context-menu entries every message row offers: "Copy text" (when the
/// message has any), "Edit" (when [canEdit]), and "Delete" (when [canDelete]).
/// [onDelete] is expected to confirm before deleting — the wording differs per
/// site (message vs post vs reply), so confirmation stays in the callback.
///
/// Site-specific entries surrounding these stay at the call sites;
/// [beforeDelete] slots extras (the channel row's Pin/Unpin) between Edit and
/// Delete so each menu's existing order is preserved.
List<AccordMenuEntry> buildMessageActionEntries({
  required String content,
  required bool canEdit,
  required bool canDelete,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  List<AccordMenuEntry> beforeDelete = const [],
}) {
  return [
    if (content.isNotEmpty)
      AccordMenuEntry(
        label: 'Copy text',
        icon: Icons.copy_outlined,
        onSelected: () => Clipboard.setData(ClipboardData(text: content)),
      ),
    if (canEdit)
      AccordMenuEntry(
        label: 'Edit',
        icon: Icons.edit_outlined,
        onSelected: onEdit,
      ),
    ...beforeDelete,
    if (canDelete)
      AccordMenuEntry(
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onSelected: onDelete,
      ),
  ];
}
