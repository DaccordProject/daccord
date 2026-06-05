import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A circular member/user avatar with a presence status dot overlaid in the
/// lower-right corner. The dot is hidden for offline/unknown status. Used by the
/// roster and the member profile popout.
class AccordMemberAvatar extends StatelessWidget {
  const AccordMemberAvatar({
    super.key,
    required this.avatarUrl,
    required this.initial,
    required this.status,
    this.radius = 16,
    this.ringColor,
  });

  final String? avatarUrl;
  final String initial;
  final String status;
  final double radius;

  /// The color the status dot's border blends into (the surrounding surface).
  /// Defaults to the theme foreground.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final dotColor = accordPresenceColor(status);
    final dotSize = radius * 0.6;
    final url = avatarUrl;
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: colors.darkGray,
            foregroundImage:
                url == null ? null : CachedNetworkImageProvider(url),
            child: Text(
              initial,
              style: theme.textTheme.labelLarge!.copyWith(color: Colors.white),
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
