import 'dart:typed_data';
import 'package:video_player/video_player.dart' as vp;
import 'package:bonfire/shared/utils/decrypted_media_web.dart'
    if (dart.library.io) 'package:bonfire/shared/utils/decrypted_media_io.dart'
    as impl;

/// Temporary app-owned source for a video the client already authenticated.
/// Cleared when its message leaves the widget tree.
abstract interface class DecryptedMediaSource {
  String get url;
  Future<void> dispose();
}

Future<DecryptedMediaSource> createDecryptedMedia(
  Uint8List bytes,
  String filename,
  String? contentType,
) => impl.createDecryptedMedia(bytes, filename, contentType);
vp.VideoPlayerController decryptedVideoController(String url) =>
    impl.decryptedVideoController(url);
