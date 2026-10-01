import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:video_player/video_player.dart' as vp;
import 'package:bonfire/shared/utils/decrypted_media.dart';

class _Source implements DecryptedMediaSource {
  @override
  final String url;
  _Source(this.url);
  @override
  Future<void> dispose() async => web.URL.revokeObjectURL(url);
}

Future<DecryptedMediaSource> createDecryptedMedia(
  Uint8List bytes,
  String filename,
  String? contentType,
) async => _Source(
  web.URL.createObjectURL(
    web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: contentType ?? 'application/octet-stream'),
    ),
  ),
);
vp.VideoPlayerController decryptedVideoController(String url) =>
    vp.VideoPlayerController.networkUrl(Uri.parse(url));
