import 'dart:io';

import 'package:path/path.dart' as p;

/// Package wrappers can opt out without changing the signed executable. The
/// marker belongs beside the Windows/Linux executable, outside its resources.
bool detectPackageManagerInstall({
  Map<String, String>? environment,
  String? executable,
}) {
  final env = environment ?? Platform.environment;
  const managers = {
    'winget',
    'scoop',
    'chocolatey',
    'homebrew',
    'flatpak',
    'true',
    '1',
  };
  if (managers.contains(env['DACCORD_PACKAGE_MANAGER']?.toLowerCase())) {
    return true;
  }
  if (env['FLATPAK_ID'] == 'io.github.DaccordProject.daccord') return true;
  try {
    return File(
      p.join(
        p.dirname(executable ?? Platform.resolvedExecutable),
        'daccord.package-manager',
      ),
    ).existsSync();
  } on FileSystemException {
    return false;
  }
}
