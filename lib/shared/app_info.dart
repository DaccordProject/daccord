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

/// True when this build is destined for an app store (iOS App Store / Mac App
/// Store), set via `--dart-define=APP_STORE=true` in the store release lanes.
///
/// App Store Review Guidelines forbid apps that download and run executable
/// code or self-update outside the store, and the Mac App Store build is
/// sandboxed (which blocks the swap helper anyway). So when this is true the
/// in-app updater is disabled entirely: no startup/periodic GitHub check and no
/// in-place install path. Store builds update through the store.
const bool kAppStoreBuild = bool.fromEnvironment('APP_STORE');

/// `owner/repo` whose GitHub Releases drive the in-app update checker. This is
/// the Flutter client's own repository (the reference client checks its own
/// Godot repo). See [kGithubLatestReleaseUrl].
const String kGithubRepo = 'DaccordProject/daccord';

/// GitHub REST endpoint for the latest published release of [kGithubRepo].
const String kGithubLatestReleaseUrl =
    'https://api.github.com/repos/$kGithubRepo/releases/latest';

/// GitHub REST endpoint for the release tagged `v[version]` of [kGithubRepo].
///
/// Used to fetch the notes for the build that is *currently running* (see the
/// release-notes controller): after a self-update the staged release object is
/// gone with the old process, and `/releases/latest` may already have moved on
/// to a newer build.
String kGithubReleaseByTagUrl(String version) =>
    'https://api.github.com/repos/$kGithubRepo/releases/tags/v$version';
