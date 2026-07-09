/// Web/no-io stub of the self-update installer. The web build updates via the
/// service worker (see `web_update.dart`), so in-place install is unsupported
/// here; these methods exist only to satisfy the shared API in
/// `update_installer.dart` and are never reached (the UI gates on
/// [UpdateInstaller.isSupported]).
library;

class UpdateInstallException implements Exception {
  UpdateInstallException(this.message);
  final String message;
  @override
  String toString() => 'UpdateInstallException: $message';
}

class UpdateInstaller {
  UpdateInstaller();

  /// No in-place install path off a native platform.
  static bool get isSupported => false;

  /// No in-place install off a native platform, so the install root is never
  /// writable in the swap sense (the web build updates via the service worker).
  static bool get isInstallRootWritable => false;

  /// API parity with the native installer's test seam; unused off native.
  static bool? debugInstallRootWritable;

  /// No privileged package installer off a native platform.
  static bool get hasPrivilegedInstaller => false;

  /// API parity with the native installer's test seam; unused off native.
  static bool? debugHasPrivilegedInstaller;

  Future<String> download(
    String url, {
    String? fileName,
    void Function(double progress)? onProgress,
  }) =>
      throw UpdateInstallException('Self-update is not supported here.');

  Future<void> verify(String path, String expectedHex) =>
      throw UpdateInstallException('Self-update is not supported here.');

  Future<void> install(
    String path, {
    required Future<void> Function() onReadyToQuit,
  }) =>
      throw UpdateInstallException('Self-update is not supported here.');
}
