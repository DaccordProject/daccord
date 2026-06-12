/// Static facts about this build, used by the update checker and the local MCP
/// server's `serverInfo`.
library;

import 'package:package_info_plus/package_info_plus.dart';

/// The current app version. Populated once at startup by [initAppInfo] from the
/// version Flutter bakes into the build from `pubspec.yaml` `version:` (the
/// `+build` suffix is dropped). `pubspec.yaml` is the single source of truth —
/// bump *only* `version:` there and this follows automatically.
///
/// Falls back to `'0.0.0'` until [initAppInfo] completes (or if it fails); a
/// `0.0.0` baseline makes the update checker treat any published release as
/// newer rather than hiding updates.
String kAppVersion = '0.0.0';

/// Reads the build's version into [kAppVersion]. Call once during startup,
/// after `WidgetsFlutterBinding.ensureInitialized()` and before anything that
/// reports or compares the version (update checker, error reporting, MCP
/// `serverInfo`). Safe to await — it's a single bundled-metadata read, no
/// network — and self-contained so a platform failure can't block startup.
Future<void> initAppInfo() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) kAppVersion = info.version;
  } catch (_) {
    // Leave the 0.0.0 fallback in place.
  }
}

/// `owner/repo` whose GitHub Releases drive the in-app update checker. This is
/// the Flutter client's own repository (the reference client checks its own
/// Godot repo). See [kGithubLatestReleaseUrl].
const String kGithubRepo = 'DaccordProject/daccord';

/// GitHub REST endpoint for the latest published release of [kGithubRepo].
const String kGithubLatestReleaseUrl =
    'https://api.github.com/repos/$kGithubRepo/releases/latest';
