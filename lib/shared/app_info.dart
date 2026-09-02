/// Static facts about this build, used by the update checker and the local MCP
/// server's `serverInfo`.
library;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_platform/universal_platform.dart';

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
/// in-app updater is disabled entirely: no startup/periodic GitHub check, no
/// manual check, no Updates entry point and no banner. Store builds update
/// through the store.
///
/// Prefer [isAppStoreBuild] at call sites — it is the same value, but overridable
/// in tests (this const is baked in at compile time and so is always `false` in
/// a normal `flutter test` run).
const bool kAppStoreBuild = bool.fromEnvironment('APP_STORE');

/// Forces [isAppStoreBuild] on in tests, which cannot set a `--dart-define`.
/// Null in production. Mirrors `UpdateInstaller.debugInstallRootWritable`.
@visibleForTesting
bool? debugAppStoreBuild;

/// Whether this build must behave as an app-store build — see [kAppStoreBuild].
///
/// `kAppStoreBuild ||` keeps the const short-circuit for real store builds (the
/// compiler still folds the whole expression to `true`), so the updater code is
/// still statically dead there.
bool get isAppStoreBuild => kAppStoreBuild || (debugAppStoreBuild ?? false);

/// Overrides [isDeveloperModeAvailable] in tests, which can neither set a
/// `--dart-define` nor pretend to run on another platform. Null in production.
@visibleForTesting
bool? debugDeveloperModeAvailable;

/// Whether Developer Mode (and the local Client MCP server it unlocks) may be
/// offered on this build at all.
///
/// The MCP server binds an HTTP listener on `127.0.0.1` for AI agents running on
/// the same machine. That only means anything on a desktop the user also runs
/// agents on: on phones and tablets there is nothing to connect to it, and web
/// has no `dart:io` server at all. Shipping a debug server (and a settings
/// toggle describing one) inside a store binary also reads as a pre-release
/// build to app reviewers. So it is desktop-only, and never on a store build.
bool get isDeveloperModeAvailable =>
    debugDeveloperModeAvailable ??
    (!isAppStoreBuild && UniversalPlatform.isDesktop);

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
