import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/spaces/utils/space_media_cache.dart';

/// Resolves a space's `banner` reference to an absolute CDN URL, or null when
/// unset. The field is either a bare asset hash or a server-relative/absolute
/// path; both are handled (mirrors `accordMemberAvatarUrl`).
String? accordSpaceBannerUrl(
  AccordSpace space,
  String? cdnUrl, {
  bool versioned = true,
}) {
  final banner = space.banner;
  if (banner is! String || banner.isEmpty) return null;
  final cdn = cdnUrl ?? '';
  String resolve(String url) => versioned ? spaceMediaCache.resolve(url) : url;
  if (banner.contains('/') || banner.startsWith('http')) {
    return resolve(AccordCDN.resolvePath(banner, cdnUrl: cdn));
  }
  return resolve(
    AccordCDN.spaceBanner(
      space.id,
      banner,
      format: AccordCDN.autoFormat(banner),
      cdnUrl: cdn,
    ),
  );
}

/// Resolves a space's `icon` reference to an absolute CDN URL, or null when
/// unset. Mirrors [accordSpaceBannerUrl].
String? accordSpaceIconUrl(
  AccordSpace space,
  String? cdnUrl, {
  bool versioned = true,
}) {
  final icon = space.icon;
  if (icon is! String || icon.isEmpty) return null;
  final cdn = cdnUrl ?? '';
  String resolve(String url) => versioned ? spaceMediaCache.resolve(url) : url;
  if (icon.contains('/') || icon.startsWith('http')) {
    return resolve(AccordCDN.resolvePath(icon, cdnUrl: cdn));
  }
  return resolve(
    AccordCDN.spaceIcon(
      space.id,
      icon,
      format: AccordCDN.autoFormat(icon),
      cdnUrl: cdn,
    ),
  );
}
