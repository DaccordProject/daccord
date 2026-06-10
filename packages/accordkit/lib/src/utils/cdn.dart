import 'dart:convert';
import 'dart:typed_data';

import '../core/accord_config.dart';

/// Builds CDN URLs for avatars, icons, banners, emojis, attachments, and
/// sounds, and resolves server-returned relative CDN paths to absolute URLs.
class AccordCDN {
  /// Fallback CDN base used when a per-call [cdnUrl] is not provided.
  static String baseUrl = AccordConfig.defaultCdnUrl;

  static String _resolve(String cdnUrl) => cdnUrl.isNotEmpty ? cdnUrl : baseUrl;

  static String avatar(
    String userId,
    String hash, {
    String format = 'png',
    String cdnUrl = '',
  }) {
    return '${_resolve(cdnUrl)}/avatars/$userId/$hash.$format';
  }

  static String defaultAvatar(int index, {String cdnUrl = ''}) {
    return '${_resolve(cdnUrl)}/embed/avatars/$index.png';
  }

  static String spaceIcon(
    String spaceId,
    String hash, {
    String format = 'png',
    String cdnUrl = '',
  }) {
    return '${_resolve(cdnUrl)}/space-icons/$spaceId/$hash.$format';
  }

  static String spaceBanner(
    String spaceId,
    String hash, {
    String format = 'png',
    String cdnUrl = '',
  }) {
    return '${_resolve(cdnUrl)}/banners/$spaceId/$hash.$format';
  }

  static String emoji(
    String emojiId, {
    String format = 'png',
    String cdnUrl = '',
  }) {
    return '${_resolve(cdnUrl)}/emojis/$emojiId.$format';
  }

  static String attachment(
    String channelId,
    String attachmentId,
    String filename, {
    String cdnUrl = '',
  }) {
    return '${_resolve(cdnUrl)}/attachments/$channelId/$attachmentId/$filename';
  }

  static String sound(String audioUrl, {String cdnUrl = ''}) {
    return resolvePath(audioUrl, cdnUrl: cdnUrl);
  }

  /// Resolves a server-returned CDN path (e.g. "/cdn/avatars/123.png") to a
  /// full URL. Absolute URLs are returned unchanged.
  static String resolvePath(String path, {String cdnUrl = ''}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('/cdn/')) {
      return _resolve(cdnUrl) + path.substring(4);
    }
    if (path.startsWith('/')) {
      return _resolve(cdnUrl) + path;
    }
    return '${_resolve(cdnUrl)}/$path';
  }

  /// Builds a `data:` URI from raw file [bytes], inferring the MIME type from
  /// [filePath]'s extension. Suitable for avatar/icon/banner upload fields.
  static String buildDataUri(Uint8List bytes, String filePath) {
    final dotIndex = filePath.lastIndexOf('.');
    final ext =
        dotIndex >= 0 ? filePath.substring(dotIndex + 1).toLowerCase() : '';
    final String mime;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        mime = 'image/jpeg';
        break;
      case 'webp':
        mime = 'image/webp';
        break;
      case 'gif':
        mime = 'image/gif';
        break;
      default:
        mime = 'image/png';
    }
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  /// Whether the given asset hash denotes an animated asset (`a_` prefix).
  static bool isAnimated(String hash) => hash.startsWith('a_');

  /// Picks `gif` for animated hashes, otherwise `png`.
  static String autoFormat(String hash) => isAnimated(hash) ? 'gif' : 'png';
}
