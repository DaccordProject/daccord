/// Static facts about this build, used by the update checker and the local MCP
/// server's `serverInfo`.
library;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:bonfire/shared/package_manager_install.dart';

/// The app version from `pubspec.yaml` (without `+build`), set by
/// [initAppInfo]. The `0.0.0` fallback makes the update checker treat any
/// published release as newer rather than hiding updates.
String kAppVersion = '0.0.0';

/// Reads the build's version into [kAppVersion]. Call once at startup, before
/// anything reports or compares the version; a platform failure can't block
/// startup.
Future<void> initAppInfo() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) kAppVersion = info.version;
  } catch (_) {}
}

/// Set via `--dart-define=APP_STORE=true` in the store release lanes.
///
/// App Store Review Guidelines forbid self-updating outside the store (and the
/// sandboxed Mac App Store build blocks the swap helper anyway), so store builds
/// disable the in-app updater entirely. Call sites use [isAppStoreBuild], which
/// tests can override.
const bool kAppStoreBuild = bool.fromEnvironment('APP_STORE');

/// Forces [isAppStoreBuild] on in tests, which cannot set a `--dart-define`.
@visibleForTesting
bool? debugAppStoreBuild;

/// `kAppStoreBuild ||` keeps the const short-circuit so the updater code stays
/// statically dead in real store builds.
bool get isAppStoreBuild => kAppStoreBuild || (debugAppStoreBuild ?? false);

/// Distributors can disable self-updates without disabling desktop MCP or
/// other features that remain available outside app-store builds.
const bool kPackageManagerBuild = bool.fromEnvironment('PACKAGE_MANAGER');

@visibleForTesting
bool? debugPackageManagerBuild;

final bool _packageManagerInstall = detectPackageManagerInstall();

bool get isPackageManagerBuild =>
    kPackageManagerBuild ||
    (debugPackageManagerBuild ?? _packageManagerInstall);

/// Shared gate for automatic checks, manual checks, downloads and applying a
/// staged update. Package managers own the installed files even when writable.
bool get isSelfUpdateEnabled => !isAppStoreBuild && !isPackageManagerBuild;

@visibleForTesting
bool? debugDeveloperModeAvailable;

/// Whether Developer Mode (and its loopback MCP server for local AI agents) may
/// be offered. Desktop-only: mobile has nothing to connect and web has no
/// `dart:io` server. Never in store builds, where a debug server reads as a
/// pre-release build to app reviewers.
bool get isDeveloperModeAvailable =>
    debugDeveloperModeAvailable ??
    (!isAppStoreBuild && UniversalPlatform.isDesktop);

@visibleForTesting
bool? debugBackgroundConnectionAvailable;

/// Whether the Android background-connection foreground service may be offered,
/// shared by the settings toggle and `BackgroundConnectionController`. Never in
/// store builds: the Play AAB ships without `BackgroundConnectionService` in its
/// manifest, so starting it would crash.
bool get isBackgroundConnectionAvailable =>
    debugBackgroundConnectionAvailable ??
    (!isAppStoreBuild && UniversalPlatform.isAndroid);

/// `owner/repo` whose GitHub Releases drive the in-app update checker.
const String kGithubRepo = 'DaccordProject/daccord';

/// Public website surfaces used by in-app support and policy links.
const String kDaccordWebsiteUrl = 'https://www.daccord.gg';
const String kDaccordHelpUrl = '$kDaccordWebsiteUrl/help.html';
const String kDaccordPrivacyPolicyUrl = '$kDaccordWebsiteUrl/privacy.html';

/// Universal Link prefix; parsed by `ServerUri.parseDeepLink`.
const String kUniversalLinkBase = '$kDaccordWebsiteUrl/open';

/// GitHub REST endpoint for the latest published release of [kGithubRepo].
const String kGithubLatestReleaseUrl =
    'https://api.github.com/repos/$kGithubRepo/releases/latest';

/// GitHub REST endpoint for the release tagged `v[version]` of [kGithubRepo].
/// Used for the running build's notes, since `/releases/latest` may already
/// have moved on after a self-update.
String kGithubReleaseByTagUrl(String version) =>
    'https://api.github.com/repos/$kGithubRepo/releases/tags/v$version';
