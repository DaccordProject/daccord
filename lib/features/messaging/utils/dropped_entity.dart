/// Reading the files dragged onto the composer.
library;

import 'dart:typed_data';

import 'package:bonfire/features/messaging/utils/attachment_limits.dart';
import 'package:bonfire/features/messaging/utils/attachment_types.dart';
import 'package:bonfire/features/messaging/utils/dropped_entity_stub.dart'
    if (dart.library.io) 'package:bonfire/features/messaging/utils/dropped_entity_io.dart';
import 'package:desktop_drop/desktop_drop.dart';

/// Reads dropped [items] into attachments, with a line for each one that
/// can't be attached. Folders are refused, and files are size-checked before
/// being read so a dropped 4 GB video is rejected rather than pulled into
/// memory first.
Future<AttachmentScreening> readDroppedFiles(
  List<DropItem> items, {
  required int maxBytes,
}) async {
  final accepted = <PendingAttachment>[];
  final rejections = <String>[];
  for (final item in items) {
    // `desktop_drop` only types directories as `DropItemDirectory` on macOS
    // and web; Linux and Windows share a handler that types every dropped path
    // as a file, so the path itself has to be checked or a folder reads as an
    // unreadable file.
    if (item is DropItemDirectory || isDroppedDirectory(item.path)) {
      rejections.add(
        '${item.name} is a folder — drop the files inside it instead.',
      );
      continue;
    }
    // macOS sandbox: a file dragged in from outside the container is only
    // readable while its security-scoped bookmark is held open.
    final bookmark = item.extraAppleBookmark;
    final scoped = await _startScopedAccess(bookmark);
    try {
      final size = await item.length();
      if (size > maxBytes) {
        rejections.add(
          oversizeAttachmentMessage(item.name, size, maxBytes: maxBytes),
        );
        continue;
      }
      accepted.add(
        PendingAttachment.fromBytes(
          name: item.name,
          bytes: await item.readAsBytes(),
          path: item.path.isEmpty ? null : item.path,
          // Drag-and-drop is the one path where the platform says what the
          // file is; prefer that over guessing from the extension.
          platformMimeType: item.mimeType,
        ),
      );
    } catch (_) {
      rejections.add(unreadableAttachmentMessage(item.name));
    } finally {
      if (scoped) await _stopScopedAccess(bookmark!);
    }
  }
  return AttachmentScreening(accepted: accepted, rejections: rejections);
}

Future<bool> _startScopedAccess(Uint8List? bookmark) async {
  if (bookmark == null || bookmark.isEmpty) return false;
  try {
    return await DesktopDrop.instance.startAccessingSecurityScopedResource(
      bookmark: bookmark,
    );
  } catch (_) {
    return false;
  }
}

Future<void> _stopScopedAccess(Uint8List bookmark) async {
  try {
    await DesktopDrop.instance.stopAccessingSecurityScopedResource(
      bookmark: bookmark,
    );
  } catch (_) {
    // Access lapses with the drop anyway; nothing useful to tell the user.
  }
}
