/// Static facts about this build, used by the update checker and the local MCP
/// server's `serverInfo`.
library;

/// The current app version, kept in sync with `pubspec.yaml` `version:`
/// (the `+build` suffix is omitted). Used as the baseline the update checker
/// compares GitHub releases against.
const String kAppVersion = '1.0.0';

/// `owner/repo` whose GitHub Releases drive the in-app update checker. This is
/// the Flutter client's own repository (the reference client checks its own
/// Godot repo). See [kGithubLatestReleaseUrl].
const String kGithubRepo = 'DaccordProject/daccord-app';

/// GitHub REST endpoint for the latest published release of [kGithubRepo].
const String kGithubLatestReleaseUrl =
    'https://api.github.com/repos/$kGithubRepo/releases/latest';
