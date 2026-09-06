import 'dart:io';

import 'package:bonfire/features/updates/services/update_archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_platform/universal_platform.dart';

export 'package:bonfire/features/updates/services/update_archive_io.dart'
    show UpdateArchiveLimits, UpdateInstallException;

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
    deleteEntity(staging.path);
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

  /// Stages [archiveFile] into [dest] through the hardened archive layer
  /// (`update_archive_io.dart`) under this installer's limits.
  Future<Directory> _extract(File archiveFile, Directory dest) =>
      extractArchive(archiveFile, dest, _archiveLimits);

  @visibleForTesting
  Future<Directory> extractArchiveForTesting(
    File archiveFile,
    Directory dest,
  ) =>
      _extract(archiveFile, dest);

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
