import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A circular member/user avatar with an optional presence status dot overlaid
/// in the lower-right corner. The dot is hidden for offline/unknown status and
/// omitted entirely when [status] is null — pass null for the many image/initial
/// avatars (rosters, DMs, voice, admin lists) that don't show presence. Used
/// anywhere a circular avatar is rendered.
class AccordMemberAvatar extends StatelessWidget {
  const AccordMemberAvatar({
    super.key,
    required this.avatarUrl,
    required this.initial,
    this.status,
    this.radius = 16,
    this.ringColor,
    this.backgroundColor,
    this.initialStyle,
  });

  final String? avatarUrl;
  final String initial;

  /// Text style for the fallback initial. The avatar always re-tints it for
  /// contrast against the background, so callers typically pass a size/weight
  /// only (e.g. `theme.textTheme.titleSmall` or `TextStyle(fontSize: 18)`).
  /// Defaults to `labelLarge` — the size used by the roster/list avatars.
  final TextStyle? initialStyle;

  /// Presence status (`online`/`idle`/`dnd`/…) driving the dot, or null to omit
  /// the dot for avatars that don't surface presence.
  final String? status;
  final double radius;

  /// The color the status dot's border blends into (the surrounding surface).
  /// Defaults to the theme foreground.
  final Color? ringColor;

  /// Background tint shown behind the initial when there's no avatar image.
  /// Pass [accordIdColor] of the user/space ID for a stable per-identity color;
  /// defaults to a flat grey.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final status = this.status;
    final dotColor = status == null ? null : accordPresenceColor(status);
    final dotSize = radius * 0.6;
    final url = avatarUrl;
    final bg = backgroundColor ?? colors.darkGray;
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: bg,
            foregroundImage:
                url == null ? null : CachedNetworkImageProvider(url),
            child: Text(
              initial,
              style: (initialStyle ?? theme.textTheme.labelLarge!)
                  .copyWith(color: accordOnColor(bg)),
            ),
          ),
          if (dotColor != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: ringColor ?? colors.foreground, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
