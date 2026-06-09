/// Self-update installer facade. Resolves to the native `dart:io` implementation
/// on desktop/mobile and to a no-op stub on web (where updates come from the
/// service worker instead). Importers use [UpdateInstaller] /
/// [UpdateInstallException] without caring which backs them.
library;

export 'update_installer_stub.dart'
    if (dart.library.io) 'update_installer_io.dart';
