import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart' as vp;
import 'package:bonfire/shared/utils/decrypted_media.dart';
import 'package:bonfire/shared/utils/download_attachment.dart';

class _Source implements DecryptedMediaSource {
  final Directory directory;
  final File file;
  _Source(this.directory, this.file);
  @override
  String get url => file.uri.toString();
  @override
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

Future<DecryptedMediaSource> createDecryptedMedia(
  Uint8List bytes,
  String filename,
  String? contentType,
) async {
  // mkdtemp creates a private directory on POSIX, including for decrypted video.
  final directory = await Directory.systemTemp.createTemp(
    'daccord-private-media-',
  );
  try {
    final file = File(
      '${directory.path}/${sanitizeAttachmentFilename(filename)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return _Source(directory, file);
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
}

vp.VideoPlayerController decryptedVideoController(String url) =>
    vp.VideoPlayerController.file(File.fromUri(Uri.parse(url)));
