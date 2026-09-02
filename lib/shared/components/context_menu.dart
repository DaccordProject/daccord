import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Context menus open and close a third faster than Material's defaults, which
/// feel sluggish for a menu you flick open dozens of times a session. Each
/// constant is ~⅔ of the framework value it overrides.

/// Open *and* close duration of the anchored desktop menu (Material: 300ms).
const _kAnchoredMenuDuration = Duration(milliseconds: 200);

/// Enter duration of the mobile bottom sheet (Material: 250ms).
const _kSheetEnterDuration = Duration(milliseconds: 167);

/// Exit duration of the mobile bottom sheet (Material: 200ms).
const _kSheetExitDuration = Duration(milliseconds: 133);

/// One row in an Accord context menu. A null [onSelected] (or [enabled] false)
/// renders the entry disabled. Use [AccordMenuEntry.divider] for a separator.
class AccordMenuEntry {
  const AccordMenuEntry({
    required this.label,
    this.icon,
    this.subtitle,
    this.onSelected,
    this.destructive = false,
    this.enabled = true,
  }) : isDivider = false;

  const AccordMenuEntry.divider()
    : label = '',
      icon = null,
      subtitle = null,
      onSelected = null,
      destructive = false,
      enabled = false,
      isDivider = true;

  final String label;
  final IconData? icon;

  /// Secondary line shown under [label] in the bottom-sheet form only (anchored
  /// menus stay compact).
  final String? subtitle;

  /// Run after the menu closes. Null = disabled.
  final VoidCallback? onSelected;

  /// Tints the entry with the theme's danger color.
  final bool destructive;
  final bool enabled;
  final bool isDivider;

  bool get _interactive => isDivider ? false : enabled && onSelected != null;
}

/// Shows a context menu for [entries]. On desktop layouts it opens an anchored
/// [showMenu] next to [globalPosition]; on mobile/touch (or when no position is
/// given) it opens a bottom sheet titled [title]. The chosen entry's
/// [AccordMenuEntry.onSelected] runs after the menu closes — callbacks must not
/// dismiss the menu themselves.
Future<void> showAccordContextMenu(
  BuildContext context, {
  required List<AccordMenuEntry> entries,
  Offset? globalPosition,
  String? title,
  IconData? titleIcon,
}) {
  if (shouldUseDesktopLayout(context) && globalPosition != null) {
    return _showAnchored(context, entries, globalPosition);
  }
  return _showSheet(context, entries, title, titleIcon);
}

Future<void> _showAnchored(
  BuildContext context,
  List<AccordMenuEntry> entries,
  Offset position,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final colors = BonfireThemeExtension.of(context);
  final items = <PopupMenuEntry<int>>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (entry.isDivider) {
      items.add(const PopupMenuDivider());
      continue;
    }
    final color = entry.destructive ? colors.red : colors.dirtyWhite;
    items.add(
      PopupMenuItem<int>(
        value: i,
        enabled: entry._interactive,
        height: 40,
        child: Row(
          children: [
            if (entry.icon != null) ...[
              Icon(entry.icon, size: 18, color: color),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                entry.label,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: entry.destructive ? colors.red : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  final selected = await showMenu<int>(
    context: context,
    color: colors.foreground,
    position: RelativeRect.fromRect(
      position & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    items: items,
    popUpAnimationStyle: AnimationStyle(duration: _kAnchoredMenuDuration),
  );
  if (selected != null) entries[selected].onSelected?.call();
}

Future<void> _showSheet(
  BuildContext context,
  List<AccordMenuEntry> entries,
  String? title,
  IconData? titleIcon,
) {
  final colors = BonfireThemeExtension.of(context);
  return showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: AnimationStyle(
      duration: _kSheetEnterDuration,
      reverseDuration: _kSheetExitDuration,
    ),
    builder: (sheetCtx) {
      final theme = Theme.of(sheetCtx);
      return SafeArea(
        // Scrollable: the sheet is capped at a fraction of the viewport, and a
        // long menu — the DM user menu is nine entries — overflowed it on a
        // short screen, clipping the last entries instead of letting the user
        // reach them.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                ListTile(
                  dense: true,
                  leading: titleIcon == null
                      ? null
                      : Icon(titleIcon, color: colors.dirtyWhite),
                  title: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const Divider(height: 1),
              ],
              for (final entry in entries)
                if (entry.isDivider)
                  const Divider(height: 1)
                else
                  ListTile(
                    leading: entry.icon == null
                        ? null
                        : Icon(
                            entry.icon,
                            color: entry.destructive ? colors.red : null,
                          ),
                    title: Text(
                      entry.label,
                      style: entry.destructive
                          ? TextStyle(color: colors.red)
                          : null,
                    ),
                    subtitle: entry.subtitle == null
                        ? null
                        : Text(entry.subtitle!),
                    enabled: entry._interactive,
                    onTap: entry._interactive
                        ? () {
                            Navigator.of(sheetCtx).pop();
                            entry.onSelected!.call();
                          }
                        : null,
                  ),
            ],
          ),
        ),
      );
    },
  );
}
