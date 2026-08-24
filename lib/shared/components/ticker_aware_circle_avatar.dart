import 'package:flutter/material.dart';

/// A [CircleAvatar] whose optional image participates in [TickerMode].
///
/// [CircleAvatar.foregroundImage] is painted by [DecorationImage], which keeps
/// listening to animated image frames when tickers are disabled. Painting the
/// same provider through an [Image] retains the avatar fallback and makes GIF
/// avatars pause with the rest of the app's multiframe images.
class TickerAwareCircleAvatar extends StatelessWidget {
  const TickerAwareCircleAvatar({
    super.key,
    required this.radius,
    required this.backgroundColor,
    this.foregroundImage,
    this.child,
  });

  final double radius;
  final Color backgroundColor;
  final ImageProvider? foregroundImage;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: radius * 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: backgroundColor,
            child: child,
          ),
          if (foregroundImage != null)
            ClipOval(
              child: Image(
                image: foregroundImage!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
