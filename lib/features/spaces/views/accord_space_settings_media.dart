import 'dart:typed_data';

import 'package:bonfire/shared/components/ticker_aware_circle_avatar.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The selected bytes take precedence over the saved, possibly stable URL.
class SpaceSettingsIconPreview extends StatelessWidget {
  const SpaceSettingsIconPreview({
    super.key,
    this.url,
    this.pendingBytes,
    this.removed = false,
  });

  final String? url;
  final Uint8List? pendingBytes;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final ImageProvider? image = removed
        ? null
        : pendingBytes != null
        ? MemoryImage(pendingBytes!)
        : url != null
        ? CachedNetworkImageProvider(url!)
        : null;
    return TickerAwareCircleAvatar(
      radius: 28,
      backgroundColor: colors.darkGray,
      foregroundImage: image,
      child: image == null
          ? Icon(Icons.image_outlined, color: colors.gray)
          : null,
    );
  }
}

/// Use the crop's aspect ratio at every settings width; cover in a fixed-height
/// container would silently crop the user's selected framing a second time.
class SpaceSettingsBannerPreview extends StatelessWidget {
  const SpaceSettingsBannerPreview({super.key, this.url, this.pendingBytes});

  final String? url;
  final Uint8List? pendingBytes;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: colors.darkGray,
          child: pendingBytes != null
              ? Image.memory(
                  pendingBytes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                )
              : url != null
              ? CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorWidget: (_, _, _) => Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: colors.gray,
                    ),
                  ),
                )
              : Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: colors.gray,
                    size: 32,
                  ),
                ),
        ),
      ),
    );
  }
}
