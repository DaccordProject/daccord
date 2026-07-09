import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Small circular user avatar: the image at [imageUrl] when available,
/// otherwise the [accordInitial] of [name] on the theme's dark-gray disc.
///
/// Consolidates the identical `CircleAvatar(backgroundColor: colors.darkGray,
/// child: Text(accordInitial(...)))` leading avatars that were hand-inlined
/// across the DM/friends dialogs and the DM conversation list. Site-specific
/// decoration (presence dots, group icons, badges) stays at the call sites.
class UserAvatar extends StatelessWidget {
  const UserAvatar(this.name, {super.key, this.imageUrl, this.radius = 16});

  final String name;

  /// Optional avatar image URL, shown over the initial when it loads.
  final String? imageUrl;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.darkGray,
      foregroundImage:
          imageUrl == null ? null : CachedNetworkImageProvider(imageUrl!),
      child: Text(accordInitial(name)),
    );
  }
}
