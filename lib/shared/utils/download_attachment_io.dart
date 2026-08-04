/// Native (`dart:io`) implementation of [downloadAttachment].
///
/// Desktop streams to the OS Downloads directory so a large attachment is never
/// buffered in memory; mobile has no writable public directory, so it fetches
/// the bytes and hands them to the platform save sheet instead. Reached only
/// through `download_attachment.dart`'s conditional import — don't import this
/// directly.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bonfire/shared/utils/download_attachment.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_platform/universal_platform.dart';

/// Only desktop has a file manager worth opening.
bool get canRevealDownloads => UniversalPlatform.isDesktop;

Future<DownloadResult> downloadAttachment(
  String url, {
  required String filename,
  DownloadProgressCallback? onProgress,
}) async {
  final safeName = sanitizeAttachmentFilename(filename);
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return const DownloadResult.failed('That attachment has no valid address.');
  }

  final client = http.Client();
  try {
    return UniversalPlatform.isDesktop
        ? await _saveToDownloadsDir(client, uri, safeName, onProgress)
        : await _saveViaShareSheet(client, uri, safeName, onProgress);
  } on _DownloadException catch (e) {
    return DownloadResult.failed(e.message);
  } on SocketException {
    return const DownloadResult.failed(
      "Couldn't reach the server. Check your connection and try again.",
    );
  } on HttpException {
    return const DownloadResult.failed('The download was interrupted.');
  } catch (e) {
    debugPrint('Attachment download failed: $e');
    return const DownloadResult.failed("Couldn't save the file.");
  } finally {
    client.close();
  }
}

/// Desktop: stream the response body straight into `~/Downloads` (or the
/// platform equivalent), chunk by chunk.
Future<DownloadResult> _saveToDownloadsDir(
  http.Client client,
  Uri uri,
  String safeName,
  DownloadProgressCallback? onProgress,
) async {
  final dir = await _downloadsDirectory();
  final response = await _send(client, uri);

  // Reserve the name before the first byte arrives so two concurrent downloads
  // of the same attachment can't race onto one path.
  final file = await _createExclusively(dir, safeName);
  final total = response.contentLength ?? 0;
  var received = 0;
  final sink = file.openWrite();
  try {
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(total > 0 ? (received / total).clamp(0.0, 1.0) : null);
    }
    await sink.close();
  } catch (_) {
    // Don't leave a truncated file sitting in Downloads looking complete.
    await sink.close().catchError((_) {});
    await file.delete().catchError((_) => file);
    rethrow;
  }
  return DownloadResult.saved(file.path);
}

/// Mobile: there is no public directory an app may write to, so buffer the
/// bytes and let the system save/share sheet place the file.
Future<DownloadResult> _saveViaShareSheet(
  http.Client client,
  Uri uri,
  String safeName,
  DownloadProgressCallback? onProgress,
) async {
  final response = await _send(client, uri);
  final total = response.contentLength ?? 0;
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response.stream) {
    builder.add(chunk);
    onProgress?.call(
      total > 0 ? (builder.length / total).clamp(0.0, 1.0) : null,
    );
  }

  final String? saved;
  try {
    saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Save attachment',
      fileName: safeName,
      bytes: builder.takeBytes(),
    );
  } catch (e) {
    debugPrint('Save sheet failed: $e');
    return const DownloadResult.failed("Couldn't save the file.");
  }
  // `saveFile` returns null when the user backs out of the sheet.
  return saved == null
      ? const DownloadResult.cancelled()
      : DownloadResult.saved(saved);
}

Future<http.StreamedResponse> _send(http.Client client, Uri uri) async {
  final request = http.Request('GET', uri)..followRedirects = true;
  final response = await client.send(request);
  if (response.statusCode != 200) {
    throw _DownloadException(
      'The server refused the download (HTTP ${response.statusCode}).',
    );
  }
  return response;
}

Future<Directory> _downloadsDirectory() async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (e) {
    debugPrint('getDownloadsDirectory failed: $e');
  }
  // Not every desktop session has an XDG downloads dir configured.
  dir ??= await getApplicationDocumentsDirectory();
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

/// Creates a new, empty file for [safeName] inside [dir], never clobbering an
/// existing one.
///
/// Two independent guards, because the name originated with a remote user:
/// the resolved path is asserted to be a direct child of [dir], and the file is
/// created with `exclusive: true` so the check and the write can't be split by
/// a race.
Future<File> _createExclusively(Directory dir, String safeName) async {
  var candidate = uniqueDownloadPath(
    dir.path,
    safeName,
    (path) => File(path).existsSync(),
  );
  for (var attempt = 0; attempt < 32; attempt++) {
    _assertDirectChild(dir.path, candidate);
    final file = File(candidate);
    try {
      return await file.create(exclusive: true);
    } on FileSystemException {
      // Either someone won the race for this name, or the directory isn't
      // writable — re-resolving distinguishes them: a name collision moves on,
      // an unwritable directory keeps failing until we give up below.
      candidate = uniqueDownloadPath(
        dir.path,
        safeName,
        (path) => File(path).existsSync(),
      );
    }
  }
  throw const _DownloadException("Couldn't create a file to download into.");
}

/// Fails closed if [filePath] would land anywhere but immediately inside
/// [dirPath]. [sanitizeAttachmentFilename] should already make this
/// unreachable; it is asserted anyway so a future change to the sanitizer can't
/// quietly turn into a path-traversal write.
void _assertDirectChild(String dirPath, String filePath) {
  final parent = p.canonicalize(p.dirname(filePath));
  if (parent != p.canonicalize(dirPath)) {
    throw const _DownloadException('That attachment has an unsafe filename.');
  }
}

Future<bool> revealDownloadedFile(String path) async {
  if (!canRevealDownloads) return false;
  final file = File(path);
  if (!file.existsSync()) return false;
  final folder = p.dirname(path);
  try {
    if (UniversalPlatform.isWindows) {
      // `/select,` highlights the file itself. Explorer exits non-zero even on
      // success, so its status is deliberately ignored.
      await Process.start('explorer.exe', ['/select,', path]);
      return true;
    }
    if (UniversalPlatform.isMacOS) {
      final result = await Process.run('open', ['-R', path]);
      return result.exitCode == 0;
    }
    // Linux: ask the FreeDesktop file manager to select the file, falling back
    // to just opening the folder where no such service is registered.
    final show = await Process.run('dbus-send', [
      '--session',
      '--print-reply',
      '--dest=org.freedesktop.FileManager1',
      '--type=method_call',
      '/org/freedesktop/FileManager1',
      'org.freedesktop.FileManager1.ShowItems',
      'array:string:${Uri.file(path)}',
      'string:',
    ]);
    if (show.exitCode == 0) return true;
    final open = await Process.run('xdg-open', [folder]);
    return open.exitCode == 0;
  } catch (e) {
    debugPrint('Reveal failed: $e');
    return false;
  }
}

/// An expected, user-reportable failure. Kept private: callers see a
/// [DownloadResult] with [DownloadOutcome.failed] instead.
class _DownloadException implements Exception {
  const _DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}
