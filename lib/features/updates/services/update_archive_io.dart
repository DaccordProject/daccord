/// The hardened archive layer behind the desktop self-updater: decodes a
/// release `.zip` / `.tar.gz` bundle into a staging directory while defending
/// against zip-slip (path traversal, absolute paths, hostile symlinks), zip
/// bombs (declared *and* actual expanded size, entry count) and malformed
/// metadata. Every path and resource limit is validated before any entry is
/// written, and the staging directory is removed again on any failure.
///
/// `dart:io` only — reachable solely through the native half of
/// `update_installer.dart`'s conditional export (via `update_installer_io.dart`).
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Thrown when an in-place install can't complete; carries a user-facing message.
class UpdateInstallException implements Exception {
  UpdateInstallException(this.message);
  final String message;
  @override
  String toString() => 'UpdateInstallException: $message';
}

/// Resource ceilings for an updater download and its extracted archive.
///
/// The defaults leave ample headroom for the desktop bundles while preventing
/// a release server from consuming unbounded memory, disk, or filesystem
/// metadata. Production always uses the defaults; tests pass smaller values to
/// exercise each boundary cheaply.
class UpdateArchiveLimits {
  const UpdateArchiveLimits({
    this.maxCompressedBytes = 512 * 1024 * 1024,
    this.maxExpandedBytes = 1024 * 1024 * 1024,
    this.maxEntries = 20000,
  }) : assert(maxCompressedBytes > 0),
       assert(maxExpandedBytes > 0),
       assert(maxEntries > 0);

  final int maxCompressedBytes;
  final int maxExpandedBytes;
  final int maxEntries;
}

/// Decodes a zip / tar.gz [archiveFile] into [dest], preserving the directory
/// tree (the #87 fix — never flatten). Every path and resource limit in
/// [limits] is validated before any entry is written. Returns [dest].
Future<Directory> extractArchive(
  File archiveFile,
  Directory dest,
  UpdateArchiveLimits limits,
) async {
  if (archiveFile.lengthSync() > limits.maxCompressedBytes) {
    throw UpdateInstallException('The update archive is too large.');
  }

  final name = archiveFile.path.toLowerCase();
  if (!name.endsWith('.tar.gz') &&
      !name.endsWith('.tgz') &&
      !name.endsWith('.zip')) {
    throw UpdateInstallException('Unsupported archive: ${p.basename(name)}');
  }

  Directory? tarTemp;
  InputFileStream? archiveInput;
  Archive? archive;
  var destinationPrepared = false;
  try {
    if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) {
      tarTemp = Directory.systemTemp.createTempSync('daccord-update-tar-');
      final tarFile = File(p.join(tarTemp.path, 'update.tar'));
      _inflateGzip(archiveFile, tarFile, limits);
      _preflightTar(tarFile, limits);
      archiveInput = InputFileStream(tarFile.path);
      archive = TarDecoder().decodeBuffer(archiveInput);
    } else {
      _preflightZip(archiveFile, limits);
      archiveInput = InputFileStream(archiveFile.path);
      archive = ZipDecoder().decodeBuffer(archiveInput);
    }

    deleteEntity(dest.path);
    dest.createSync(recursive: true);
    destinationPrepared = true;
    final root = dest.resolveSymbolicLinksSync();
    final entries = _validateEntries(archive, root, limits);
    _extractEntries(entries, root, limits);
    return dest;
  } on UpdateInstallException {
    if (destinationPrepared) deleteEntity(dest.path);
    rethrow;
  } catch (_) {
    if (destinationPrepared) deleteEntity(dest.path);
    throw UpdateInstallException('Could not safely extract the update.');
  } finally {
    try {
      await archive?.clear();
    } catch (_) {}
    try {
      await archiveInput?.close();
    } catch (_) {}
    try {
      if (tarTemp?.existsSync() ?? false) {
        tarTemp!.deleteSync(recursive: true);
      }
    } catch (_) {}
  }
}

void _inflateGzip(File source, File destination, UpdateArchiveLimits limits) {
  final input = InputFileStream(source.path);
  final output = OutputFileStream(destination.path);
  final limited = _LimitedOutputStream(
    output,
    _ByteBudget(limits.maxExpandedBytes),
  );
  try {
    GZipDecoder().decodeStream(input, limited);
  } on UpdateInstallException {
    rethrow;
  } catch (_) {
    throw UpdateInstallException('The update archive is invalid.');
  } finally {
    input.closeSync();
    output.closeSync();
  }
}

void _preflightZip(File source, UpdateArchiveLimits limits) {
  if (_zipDeclaredEntryCount(source) > limits.maxEntries) {
    throw UpdateInstallException('The update archive has too many files.');
  }
  final input = InputFileStream(source.path);
  try {
    final directory = ZipDirectory.read(input);
    if (directory.fileHeaders.length > limits.maxEntries) {
      throw UpdateInstallException('The update archive has too many files.');
    }
    var expandedBytes = 0;
    for (final header in directory.fileHeaders) {
      _normalizeEntryName(header.filename);
      if (header.generalPurposeBitFlag & 0x1 != 0) {
        throw UpdateInstallException(
          'Encrypted update archives are not supported.',
        );
      }
      final size = header.uncompressedSize;
      if (size == null || size < 0) {
        throw UpdateInstallException('The update archive is invalid.');
      }
      expandedBytes += size;
      if (expandedBytes > limits.maxExpandedBytes) {
        throw UpdateInstallException(
          'The update archive expands beyond the safe limit.',
        );
      }
    }
  } on UpdateInstallException {
    rethrow;
  } catch (_) {
    throw UpdateInstallException('The update archive is invalid.');
  } finally {
    input.closeSync();
  }
}

int _zipDeclaredEntryCount(File source) {
  final handle = source.openSync();
  try {
    final length = handle.lengthSync();
    const maxEocdSize = 22 + 0xffff;
    final tailLength = length < maxEocdSize ? length : maxEocdSize;
    handle.setPositionSync(length - tailLength);
    final tail = handle.readSync(tailLength);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (_matchesSignature(tail, i, const [0x50, 0x4b, 0x05, 0x06]) &&
          i + 22 + _uint16(tail, i + 20) == tail.length) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw UpdateInstallException('The update archive is invalid.');
    }
    final entries = _uint16(tail, eocd + 10);
    if (entries != 0xffff) return entries;

    final absoluteEocd = length - tailLength + eocd;
    if (absoluteEocd < 20) {
      throw UpdateInstallException('The update archive is invalid.');
    }
    handle.setPositionSync(absoluteEocd - 20);
    final locator = handle.readSync(20);
    if (!_matchesSignature(locator, 0, const [0x50, 0x4b, 0x06, 0x07])) {
      throw UpdateInstallException('The update archive is invalid.');
    }
    final zip64Offset = _uint64(locator, 8);
    if (zip64Offset < 0 || zip64Offset + 40 > length) {
      throw UpdateInstallException('The update archive is invalid.');
    }
    handle.setPositionSync(zip64Offset);
    final zip64 = handle.readSync(40);
    if (!_matchesSignature(zip64, 0, const [0x50, 0x4b, 0x06, 0x06])) {
      throw UpdateInstallException('The update archive is invalid.');
    }
    return _uint64(zip64, 32);
  } finally {
    handle.closeSync();
  }
}

bool _matchesSignature(List<int> bytes, int offset, List<int> signature) {
  if (offset < 0 || offset + signature.length > bytes.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[offset + i] != signature[i]) return false;
  }
  return true;
}

int _uint16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint64(List<int> bytes, int offset) {
  var value = 0;
  for (var i = 7; i >= 0; i--) {
    value = (value << 8) | bytes[offset + i];
  }
  return value;
}

void _preflightTar(File source, UpdateArchiveLimits limits) {
  final input = InputFileStream(source.path);
  try {
    var entries = 0;
    var expandedBytes = 0;
    while (!input.isEOS) {
      final end = input.peekBytes(2).toUint8List();
      if (end.length < 2 || (end[0] == 0 && end[1] == 0)) break;
      final file = TarFile.read(input, storeData: false);
      entries += 1;
      if (entries > limits.maxEntries) {
        throw UpdateInstallException('The update archive has too many files.');
      }
      _normalizeEntryName(file.filename);
      expandedBytes += file.fileSize;
      if (expandedBytes > limits.maxExpandedBytes) {
        throw UpdateInstallException(
          'The update archive expands beyond the safe limit.',
        );
      }
    }
  } on UpdateInstallException {
    rethrow;
  } catch (_) {
    throw UpdateInstallException('The update archive is invalid.');
  } finally {
    input.closeSync();
  }
}

List<_ValidatedArchiveEntry> _validateEntries(
  Archive archive,
  String root,
  UpdateArchiveLimits limits,
) {
  if (archive.length > limits.maxEntries) {
    throw UpdateInstallException('The update archive has too many files.');
  }
  final entries = <_ValidatedArchiveEntry>[];
  final outputPaths = <String>{};
  var expandedBytes = 0;
  for (final entry in archive) {
    expandedBytes += entry.size;
    if (entry.size < 0 || expandedBytes > limits.maxExpandedBytes) {
      throw UpdateInstallException(
        'The update archive expands beyond the safe limit.',
      );
    }
    final relativePath = _normalizeEntryName(entry.name);
    final outputPath = _containedPath(root, relativePath);
    final pathKey = Platform.isWindows ? outputPath.toLowerCase() : outputPath;
    if (!outputPaths.add(pathKey)) {
      throw UpdateInstallException(
        'The update archive contains conflicting paths.',
      );
    }
    String? linkTarget;
    if (entry.isSymbolicLink) {
      linkTarget = _safeLinkTarget(root, relativePath, entry.nameOfLinkedFile);
    }
    entries.add(
      _ValidatedArchiveEntry(entry, outputPath, linkTarget: linkTarget),
    );
  }
  return entries;
}

void _extractEntries(
  List<_ValidatedArchiveEntry> entries,
  String root,
  UpdateArchiveLimits limits,
) {
  final directories = entries.where(
    (entry) => !entry.file.isFile && !entry.file.isSymbolicLink,
  );
  for (final entry in directories) {
    Directory(entry.outputPath).createSync(recursive: true);
    _verifyExistingPath(
      root,
      Directory(entry.outputPath).resolveSymbolicLinksSync(),
    );
  }

  final budget = _ByteBudget(limits.maxExpandedBytes);
  for (final entry in entries.where(
    (entry) => entry.file.isFile && !entry.file.isSymbolicLink,
  )) {
    final parent = Directory(p.dirname(entry.outputPath))
      ..createSync(recursive: true);
    _verifyExistingPath(root, parent.resolveSymbolicLinksSync());
    _writeArchiveFile(entry.file, entry.outputPath, budget);
  }

  // Links are deliberately created last, so no later file write can traverse
  // through an archive-created link even when its target is safely in-root.
  for (final entry in entries.where((entry) => entry.file.isSymbolicLink)) {
    final parent = Directory(p.dirname(entry.outputPath))
      ..createSync(recursive: true);
    _verifyExistingPath(root, parent.resolveSymbolicLinksSync());
    Link(entry.outputPath).createSync(entry.linkTarget!, recursive: false);
  }
}

void _writeArchiveFile(
  ArchiveFile entry,
  String outputPath,
  _ByteBudget budget,
) {
  final output = OutputFileStream(outputPath);
  final limited = _LimitedOutputStream(output, budget);
  try {
    final compression = entry.compressionType;
    final rawContent = entry.rawContent;
    entry.clear();
    if (compression == ArchiveFile.STORE ||
        compression == ArchiveFile.DEFLATE) {
      entry.decompress(limited);
    } else if (compression == 12 && rawContent != null) {
      BZip2Decoder().decodeStream(rawContent, limited);
    } else {
      throw UpdateInstallException(
        'The update archive uses unsupported compression.',
      );
    }
    limited.flush();
    if (limited.length != entry.size) {
      throw UpdateInstallException('The update archive is invalid.');
    }
  } finally {
    output.closeSync();
  }
}

String _normalizeEntryName(String name) {
  final raw = name.replaceAll('\\', '/');
  if (raw.isEmpty ||
      raw.contains('\u0000') ||
      raw.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:').hasMatch(raw)) {
    throw UpdateInstallException('The update archive contains an unsafe path.');
  }
  final parts = raw.split('/');
  if (parts.contains('..')) {
    throw UpdateInstallException('The update archive contains an unsafe path.');
  }
  final normalized = p.posix.normalize(raw);
  if (normalized == '.' || normalized == '..' || normalized.startsWith('../')) {
    throw UpdateInstallException('The update archive contains an unsafe path.');
  }
  return normalized;
}

String _containedPath(String root, String relativePath) {
  final candidate = p.canonicalize(
    p.joinAll([root, ...relativePath.split('/')]),
  );
  if (!p.isWithin(root, candidate)) {
    throw UpdateInstallException('The update archive contains an unsafe path.');
  }
  return candidate;
}

String _safeLinkTarget(String root, String linkPath, String target) {
  final raw = target.replaceAll('\\', '/');
  if (raw.isEmpty ||
      raw.contains('\u0000') ||
      raw.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:').hasMatch(raw)) {
    throw UpdateInstallException(
      'The update archive contains an unsafe symbolic link.',
    );
  }
  final resolvedRelative = p.posix.normalize(
    p.posix.join(p.posix.dirname(linkPath), raw),
  );
  if (resolvedRelative == '..' || resolvedRelative.startsWith('../')) {
    throw UpdateInstallException(
      'The update archive contains an unsafe symbolic link.',
    );
  }
  _containedPath(root, resolvedRelative);
  return p.normalize(p.joinAll(p.posix.normalize(raw).split('/')));
}

void _verifyExistingPath(String root, String path) {
  final canonical = p.canonicalize(path);
  if (canonical != root && !p.isWithin(root, canonical)) {
    throw UpdateInstallException('The update archive contains an unsafe path.');
  }
}

/// Removes whatever sits at [path] (file, directory tree, or link — without
/// following it), or does nothing when there is nothing there.
void deleteEntity(String path) {
  switch (FileSystemEntity.typeSync(path, followLinks: false)) {
    case FileSystemEntityType.directory:
      Directory(path).deleteSync(recursive: true);
      break;
    case FileSystemEntityType.file:
      File(path).deleteSync();
      break;
    case FileSystemEntityType.link:
      Link(path).deleteSync();
      break;
    case FileSystemEntityType.notFound:
      break;
    default:
      throw UpdateInstallException('Could not prepare the update directory.');
  }
}

class _ValidatedArchiveEntry {
  const _ValidatedArchiveEntry(this.file, this.outputPath, {this.linkTarget});

  final ArchiveFile file;
  final String outputPath;
  final String? linkTarget;
}

class _ByteBudget {
  _ByteBudget(this.limit);

  final int limit;
  int used = 0;

  void consume(int count) {
    if (count < 0 || used + count > limit) {
      throw UpdateInstallException(
        'The update archive expands beyond the safe limit.',
      );
    }
    used += count;
  }
}

/// Counts actual decompressor output before forwarding it to disk. Metadata
/// limits alone are insufficient because a malformed archive can lie about an
/// entry's expanded size.
class _LimitedOutputStream extends OutputStreamBase {
  _LimitedOutputStream(this._output, this._budget);

  final OutputStreamBase _output;
  final _ByteBudget _budget;

  @override
  int get length => _output.length;

  @override
  void flush() => _output.flush();

  @override
  void writeByte(int value) {
    _budget.consume(1);
    _output.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    final count = len ?? bytes.length;
    _budget.consume(count);
    _output.writeBytes(bytes, count);
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    const chunkSize = 64 * 1024;
    while (!stream.isEOS) {
      final count = stream.length > chunkSize ? chunkSize : stream.length;
      if (count <= 0) break;
      writeBytes(stream.readBytes(count).toUint8List());
    }
  }

  List<int> subset(int start, [int? end]) {
    final output = _output;
    if (output is OutputFileStream) return output.subset(start, end);
    if (output is OutputStream) return output.subset(start, end);
    throw StateError('The bounded archive output cannot be read back.');
  }

  @override
  void writeUint16(int value) {
    writeByte(value & 0xff);
    writeByte((value >> 8) & 0xff);
  }

  @override
  void writeUint32(int value) {
    writeUint16(value & 0xffff);
    writeUint16((value >> 16) & 0xffff);
  }

  @override
  void writeUint64(int value) {
    writeUint32(value & 0xffffffff);
    writeUint32((value >> 32) & 0xffffffff);
  }
}
