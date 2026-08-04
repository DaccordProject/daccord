import 'dart:io';

/// Whether [path] points at a directory on this filesystem.
///
/// Returns false for an empty path and for anything that no longer exists —
/// a vanished path is a read failure, not a folder, and should be reported as
/// one.
bool isDroppedDirectory(String path) {
  if (path.isEmpty) return false;
  try {
    return FileSystemEntity.isDirectorySync(path);
  } on FileSystemException {
    return false;
  }
}
