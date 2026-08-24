import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_platform/universal_platform.dart';

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
/// metadata. Tests use smaller values to exercise each boundary cheaply.
@visibleForTesting
class UpdateArchiveLimits {
  const UpdateArchiveLimits({
    this.maxCompressedBytes = 512 * 1024 * 1024,
    this.maxExpandedBytes = 1024 * 1024 * 1024,
    this.maxEntries = 20000,
  })  : assert(maxCompressedBytes > 0),
        assert(maxExpandedBytes > 0),
        assert(maxEntries > 0);

  final int maxCompressedBytes;
  final int maxExpandedBytes;
  final int maxEntries;
}

/// Downloads a release asset, verifies it, and installs it in place — the
/// desktop binary-swap / Android APK-install machinery behind the update UI.
///
/// Ports the reference client's `updater.gd` apply steps, with the fix called
/// out in #87: the Godot updater copied flat files only and would drop Flutter's
/// `data/` subtree; this copies the **whole bundle tree**. The actual swap +
/// relaunch is delegated to a small detached helper script (per platform) that
/// waits for this process to exit first — a running binary can't replace itself.
///
/// Paths are passed as plain strings so this stays free of `dart:io` types in
/// its public surface; the web build gets the no-op stub instead (see
/// `update_installer.dart`'s conditional export).
class UpdateInstaller {
  UpdateInstaller({
    http.Client? client,
    UpdateArchiveLimits archiveLimits = const UpdateArchiveLimits(),
    @visibleForTesting Future<Directory> Function()? temporaryDirectory,
  })  : _http = client ?? http.Client(),
        _archiveLimits = archiveLimits,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final http.Client _http;
  final UpdateArchiveLimits _archiveLimits;
  final Future<Directory> Function() _temporaryDirectory;

  /// Platform channel mirrored by `MainActivity.kt` for the Android APK install.
  static const _androidChannel = MethodChannel('com.daccord.app/installer');

  /// Whether an in-place install is implemented for the current platform.
  static bool get isSupported =>
      UniversalPlatform.isWindows ||
      UniversalPlatform.isMacOS ||
      UniversalPlatform.isLinux ||
      UniversalPlatform.isAndroid;

  /// Cached result of [isInstallRootWritable] — the install location can't
  /// change while the app runs, so the probe is done at most once.
  static bool? _installRootWritable;

  /// Overrides the writability probe in tests, where `resolvedExecutable` is the
  /// Dart/Flutter SDK binary and its directory's writability is both irrelevant
  /// and host-dependent. Null in production (the real probe runs).
  @visibleForTesting
  static bool? debugInstallRootWritable;

  /// Whether the (unprivileged) swap helper could actually replace the running
  /// bundle in place — i.e. the install root's *parent* directory is writable,
  /// so `mv "$root" "$root.old"` and the move-into-place can succeed.
  ///
  /// A package-manager install is not: the Linux `.deb` lands under root-owned
  /// `/opt`, a macOS build may sit in `/Applications`, a Windows setup installs
  /// to `Program Files`. There the helper's `mv`/`cp` silently fails and it
  /// relaunches the *old* build — the update appears to apply but nothing
  /// changes. Callers gate the one-click apply on this and fall back to a manual
  /// download instead. Always true on Android (the system installer applies the
  /// APK, not this helper).
  static bool get isInstallRootWritable {
    final override = debugInstallRootWritable;
    if (override != null) return override;
    if (UniversalPlatform.isAndroid) return true;
    return _installRootWritable ??= _probeInstallRootWritable();
  }

  static bool _probeInstallRootWritable() {
    try {
      final probe = File(
        p.join(p.dirname(_installRoot), '.daccord-update-probe'),
      );
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cached result of [hasPrivilegedInstaller].
  static bool? _hasPrivilegedInstaller;

  /// Overrides the privileged-installer probe in tests. Null in production.
  @visibleForTesting
  static bool? debugHasPrivilegedInstaller;

  /// Whether a privileged package install is available — i.e. Linux with
  /// `pkexec` (polkit) present. Used to update a non-writable system install
  /// (the `.deb` under root-owned `/opt`) by reinstalling the package with an
  /// admin-authentication prompt, rather than the unprivileged binary swap.
  /// Always false off Linux. Cheap + cached (called from widget builds).
  static bool get hasPrivilegedInstaller {
    final override = debugHasPrivilegedInstaller;
    if (override != null) return override;
    if (!UniversalPlatform.isLinux) return false;
    return _hasPrivilegedInstaller ??= _probePkexec();
  }

  static bool _probePkexec() {
    for (final path in const [
      '/usr/bin/pkexec',
      '/bin/pkexec',
      '/usr/local/bin/pkexec',
    ]) {
      if (File(path).existsSync()) return true;
    }
    return false;
  }

  /// Streams [url] to a temp file, reporting fractional progress (0..1) when the
  /// server sends a Content-Length. Returns the downloaded file's path.
  Future<String> download(
    String url, {
    String? fileName,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _temporaryDirectory();
    final staging = Directory(p.join(dir.path, 'daccord-update'));
    _deleteEntity(staging.path);
    staging.createSync(recursive: true);

    final requestedName = fileName ?? Uri.parse(url).path;
    final name = p.posix.basename(requestedName.replaceAll('\\', '/'));
    final safeName = name.isEmpty ||
            name == '.' ||
            name == '/' ||
            name.contains('\u0000')
        ? 'download'
        : name;
    final out = File(p.join(staging.path, safeName));

    final req = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = 'daccord-updater'
      ..followRedirects = true;
    final resp = await _http.send(req);
    if (resp.statusCode != 200) {
      throw UpdateInstallException('Download failed (HTTP ${resp.statusCode}).');
    }
    final total = resp.contentLength ?? 0;
    if (total > _archiveLimits.maxCompressedBytes) {
      throw UpdateInstallException('The update download is too large.');
    }
    var received = 0;
    final sink = out.openWrite();
    var completed = false;
    try {
      await for (final chunk in resp.stream) {
        received += chunk.length;
        if (received > _archiveLimits.maxCompressedBytes) {
          throw UpdateInstallException('The update download is too large.');
        }
        sink.add(chunk);
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      completed = true;
    } finally {
      await sink.close();
      if (!completed && out.existsSync()) out.deleteSync();
    }
    return out.path;
  }

  /// Verifies the file at [path] against [expectedHex] (case-insensitive,
  /// streamed). Throws on mismatch so a corrupt or tampered download never
  /// reaches the swap step.
  Future<void> verify(String path, String expectedHex) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    if (digest.toString().toLowerCase() != expectedHex.toLowerCase()) {
      throw UpdateInstallException(
        'Integrity check failed — the download may be corrupt.',
      );
    }
  }

  /// Installs the downloaded asset at [path] for the current platform. On
  /// desktop this spawns the detached swap helper and then quits the app (the
  /// helper relaunches the new build); on Android it hands the APK to the system
  /// package installer and returns. Throws [UpdateInstallException] on failure.
  Future<void> install(
    String path, {
    required Future<void> Function() onReadyToQuit,
  }) async {
    final asset = File(path);
    if (UniversalPlatform.isAndroid) {
      await _installAndroid(asset);
      return;
    }
    if (UniversalPlatform.isWindows) {
      await _installWindows(asset);
    } else if (UniversalPlatform.isMacOS) {
      await _installMacOs(asset);
    } else if (UniversalPlatform.isLinux) {
      await _installLinux(asset);
    } else {
      throw UpdateInstallException('Self-update is not supported here.');
    }
    // Helper is now armed and polling for our exit — flush state, then quit.
    await onReadyToQuit();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    exit(0);
  }

  // ── Android ────────────────────────────────────────────────────────────────

  Future<void> _installAndroid(File apk) async {
    try {
      await _androidChannel.invokeMethod<void>('installApk', {
        'path': apk.path,
      });
    } on PlatformException catch (e) {
      throw UpdateInstallException(
        e.message ?? 'Could not open the installer.',
      );
    } on MissingPluginException {
      throw UpdateInstallException('Installer is unavailable on this build.');
    }
  }

  // ── Desktop: extract → stage → detached swap helper ─────────────────────────

  /// Decodes a zip / tar.gz [archiveFile] into [dest], preserving the directory
  /// tree (the #87 fix — never flatten). Every path and resource limit is
  /// validated before any entry is written. Returns [dest].
  Future<Directory> _extract(File archiveFile, Directory dest) async {
    if (archiveFile.lengthSync() > _archiveLimits.maxCompressedBytes) {
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
        _inflateGzip(archiveFile, tarFile);
        _preflightTar(tarFile);
        archiveInput = InputFileStream(tarFile.path);
        archive = TarDecoder().decodeBuffer(archiveInput);
      } else {
        _preflightZip(archiveFile);
        archiveInput = InputFileStream(archiveFile.path);
        archive = ZipDecoder().decodeBuffer(archiveInput);
      }

      _deleteEntity(dest.path);
      dest.createSync(recursive: true);
      destinationPrepared = true;
      final root = dest.resolveSymbolicLinksSync();
      final entries = _validateEntries(archive, root);
      _extractEntries(entries, root);
      return dest;
    } on UpdateInstallException {
      if (destinationPrepared) _deleteEntity(dest.path);
      rethrow;
    } catch (_) {
      if (destinationPrepared) _deleteEntity(dest.path);
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

  @visibleForTesting
  Future<Directory> extractArchiveForTesting(
    File archiveFile,
    Directory dest,
  ) =>
      _extract(archiveFile, dest);

  void _inflateGzip(File source, File destination) {
    final input = InputFileStream(source.path);
    final output = OutputFileStream(destination.path);
    final limited = _LimitedOutputStream(
      output,
      _ByteBudget(_archiveLimits.maxExpandedBytes),
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

  void _preflightZip(File source) {
    if (_zipDeclaredEntryCount(source) > _archiveLimits.maxEntries) {
      throw UpdateInstallException('The update archive has too many files.');
    }
    final input = InputFileStream(source.path);
    try {
      final directory = ZipDirectory.read(input);
      if (directory.fileHeaders.length > _archiveLimits.maxEntries) {
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
        if (expandedBytes > _archiveLimits.maxExpandedBytes) {
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

  void _preflightTar(File source) {
    final input = InputFileStream(source.path);
    try {
      var entries = 0;
      var expandedBytes = 0;
      while (!input.isEOS) {
        final end = input.peekBytes(2).toUint8List();
        if (end.length < 2 || (end[0] == 0 && end[1] == 0)) break;
        final file = TarFile.read(input, storeData: false);
        entries += 1;
        if (entries > _archiveLimits.maxEntries) {
          throw UpdateInstallException(
            'The update archive has too many files.',
          );
        }
        _normalizeEntryName(file.filename);
        expandedBytes += file.fileSize;
        if (expandedBytes > _archiveLimits.maxExpandedBytes) {
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
  ) {
    if (archive.length > _archiveLimits.maxEntries) {
      throw UpdateInstallException('The update archive has too many files.');
    }
    final entries = <_ValidatedArchiveEntry>[];
    final outputPaths = <String>{};
    var expandedBytes = 0;
    for (final entry in archive) {
      expandedBytes += entry.size;
      if (entry.size < 0 ||
          expandedBytes > _archiveLimits.maxExpandedBytes) {
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

  void _extractEntries(List<_ValidatedArchiveEntry> entries, String root) {
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

    final budget = _ByteBudget(_archiveLimits.maxExpandedBytes);
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
    if (normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../')) {
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

  String _safeLinkTarget(
    String root,
    String linkPath,
    String target,
  ) {
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

  void _deleteEntity(String path) {
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

  /// The directory that holds the running desktop bundle (everything the swap
  /// must replace). On macOS this is the `.app` bundle itself.
  static String get _installRoot {
    final exe = Platform.resolvedExecutable;
    if (UniversalPlatform.isMacOS) {
      // …/Daccord.app/Contents/MacOS/daccord → …/Daccord.app
      return p.dirname(p.dirname(p.dirname(exe)));
    }
    return p.dirname(exe);
  }

  Future<File> _writeHelper(String name, String contents) async {
    final dir = await _temporaryDirectory();
    final helper = File(p.join(dir.path, 'daccord-update', name));
    helper.parent.createSync(recursive: true);
    helper.writeAsStringSync(contents);
    if (!UniversalPlatform.isWindows) {
      await Process.run('chmod', ['+x', helper.path]);
    }
    return helper;
  }

  /// The current process id, guarded so an unexpected platform can't crash the
  /// updater (the helper's `kill -0` loop just falls through on 0).
  int get _pid {
    try {
      return pid;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _installWindows(File zip) async {
    final dir = await _temporaryDirectory();
    final staged = await _extract(
      zip,
      Directory(p.join(dir.path, 'daccord-update', 'staged')),
    );
    final dst = _installRoot;
    final pid = _pid;
    // rename-to-.old → move new → relaunch, restoring on failure (#87 rollback).
    final bat = await _writeHelper('apply.bat', '''
@echo off
:wait
tasklist /FI "PID eq $pid" 2>NUL | find "$pid" >NUL
if "%ERRORLEVEL%"=="0" ( ping -n 2 127.0.0.1 >NUL & goto wait )
if exist "$dst.old" rmdir /S /Q "$dst.old" >NUL 2>&1
move "$dst" "$dst.old" >NUL 2>&1
move "${staged.path}" "$dst" >NUL 2>&1
if not exist "$dst\\daccord.exe" (
  rmdir /S /Q "$dst" >NUL 2>&1
  move "$dst.old" "$dst" >NUL 2>&1
) else (
  rmdir /S /Q "$dst.old" >NUL 2>&1
)
start "" "$dst\\daccord.exe"
del "%~f0"
''');
    await Process.start('cmd.exe', [
      '/c',
      'start',
      '',
      '/min',
      bat.path,
    ], mode: ProcessStartMode.detached);
  }

  Future<void> _installLinux(File asset) async {
    // A system-package (`.deb`) install can't be swapped in place; reinstall the
    // package with elevated rights instead (see [_installLinuxDeb]).
    if (asset.path.toLowerCase().endsWith('.deb')) {
      await _installLinuxDeb(asset);
      return;
    }
    final dir = await _temporaryDirectory();
    final staged = await _extract(
      asset,
      Directory(p.join(dir.path, 'daccord-update', 'staged')),
    );
    final dst = _installRoot;
    final pid = _pid;
    final sh = await _writeHelper('apply.sh', '''
#!/usr/bin/env bash
set -u
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
rm -rf "$dst.old"
if mv "$dst" "$dst.old" 2>/dev/null; then
  if mv "${staged.path}" "$dst" 2>/dev/null && [ -f "$dst/daccord" ]; then
    chmod +x "$dst/daccord" 2>/dev/null
    rm -rf "$dst.old"
  else
    rm -rf "$dst"; mv "$dst.old" "$dst"
  fi
fi
nohup "$dst/daccord" >/dev/null 2>&1 &
rm -f "\$0"
''');
    await Process.start('bash', [
      sh.path,
    ], mode: ProcessStartMode.detached);
  }

  /// Updates a system-package install by reinstalling the downloaded [deb] with
  /// `pkexec dpkg -i` — polkit shows an admin-authentication dialog, then dpkg
  /// overwrites the running bundle under root-owned `/opt` (safe: Linux keeps a
  /// running executable's inode until it exits). On success a detached helper
  /// relaunches the freshly-installed binary once this process quits; on failure
  /// or a cancelled prompt it throws so the app stays on the current version
  /// with a clear message (and never quits). Requires an interactive polkit
  /// agent — the desktop session provides one.
  Future<void> _installLinuxDeb(File deb) async {
    final ProcessResult result;
    try {
      result = await Process.run('pkexec', ['dpkg', '-i', deb.path]);
    } on ProcessException {
      throw UpdateInstallException(
        'Could not start the privileged installer (pkexec).',
      );
    }
    if (result.exitCode != 0) {
      // pkexec: 126 = dialog dismissed, 127 = not authorized. Anything else is
      // a dpkg failure — surface its stderr, trimmed, to help diagnose.
      if (result.exitCode == 126 || result.exitCode == 127) {
        throw UpdateInstallException('Update needs administrator approval.');
      }
      final err = (result.stderr as String? ?? '').trim();
      throw UpdateInstallException(
        err.isEmpty ? 'Package install failed.' : 'Package install failed: $err',
      );
    }
    // dpkg has replaced the bundle in place; relaunch the new binary after we
    // exit (same detached-waiter pattern as the swap helper).
    final dst = _installRoot;
    final pid = _pid;
    final sh = await _writeHelper('relaunch.sh', '''
#!/usr/bin/env bash
set -u
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
nohup "$dst/daccord" >/dev/null 2>&1 &
rm -f "\$0"
''');
    await Process.start('bash', [
      sh.path,
    ], mode: ProcessStartMode.detached);
  }

  Future<void> _installMacOs(File dmg) async {
    // Attach the read-only image, locate the bundled .app, then let the helper
    // copy it over the running bundle once we exit. Quarantine is stripped so
    // Gatekeeper doesn't re-prompt on the freshly-copied bundle.
    final mountPoint = p.join(
      (await _temporaryDirectory()).path,
      'daccord-update',
      'mnt',
    );
    Directory(mountPoint).createSync(recursive: true);
    final attach = await Process.run('hdiutil', [
      'attach',
      dmg.path,
      '-nobrowse',
      '-mountpoint',
      mountPoint,
    ]);
    if (attach.exitCode != 0) {
      throw UpdateInstallException('Could not open the disk image.');
    }
    final srcApp = p.join(mountPoint, 'Daccord.app');
    if (!Directory(srcApp).existsSync()) {
      await Process.run('hdiutil', ['detach', mountPoint, '-force']);
      throw UpdateInstallException('The update image is missing Daccord.app.');
    }
    final dst = _installRoot; // …/Daccord.app
    final pid = _pid;
    final sh = await _writeHelper('apply.sh', '''
#!/usr/bin/env bash
set -u
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
rm -rf "$dst.old"
if mv "$dst" "$dst.old" 2>/dev/null; then
  if cp -R "$srcApp" "$dst" 2>/dev/null && [ -d "$dst" ]; then
    xattr -cr "$dst" 2>/dev/null
    rm -rf "$dst.old"
  else
    rm -rf "$dst"; mv "$dst.old" "$dst"
  fi
fi
hdiutil detach "$mountPoint" -force >/dev/null 2>&1 || true
open "$dst"
rm -f "\$0"
''');
    await Process.start('bash', [
      sh.path,
    ], mode: ProcessStartMode.detached);
  }
}

class _ValidatedArchiveEntry {
  const _ValidatedArchiveEntry(
    this.file,
    this.outputPath, {
    this.linkTarget,
  });

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
