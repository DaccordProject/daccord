/// A published release fetched from the GitHub Releases API. Mirrors the subset
/// of fields the reference client's updater parses (`updater.gd` `_parse_release`).
class AppRelease {
  const AppRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.url,
    required this.publishedAt,
  });

  /// The release version, normalised (leading `v` stripped) from `tag_name`.
  final String version;

  /// Human-readable release name (`name`), falling back to the tag.
  final String name;

  /// Release notes / changelog body (`body`).
  final String notes;

  /// The release's web page (`html_url`) — opened for manual download since the
  /// client doesn't self-install.
  final String url;

  /// ISO-8601 publish timestamp (`published_at`), may be empty.
  final String publishedAt;

  static AppRelease? fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] ?? json['name'])?.toString() ?? '';
    final version = normalizeVersion(tag);
    if (version.isEmpty) return null;
    return AppRelease(
      version: version,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : tag,
      notes: (json['body'] as String?)?.trim() ?? '',
      url: (json['html_url'] as String?) ?? '',
      publishedAt: (json['published_at'] as String?) ?? '',
    );
  }
}

/// Strips a leading `v`/`V` and surrounding whitespace from a version tag
/// (e.g. `v1.2.3` → `1.2.3`).
String normalizeVersion(String tag) {
  var v = tag.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  return v.trim();
}

/// Whether semantic version [candidate] is strictly newer than [current].
/// Compares the numeric `major.minor.patch` core; a build/prerelease suffix is
/// ignored (sufficient for release-channel comparisons and matches the
/// reference's `Updater.is_newer` behaviour for normal releases).
bool isNewerVersion(String candidate, String current) {
  final a = _coreParts(candidate);
  final b = _coreParts(current);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

List<int> _coreParts(String version) {
  // Drop any prerelease/build metadata, then take the first three dot segments.
  final core = normalizeVersion(version).split(RegExp(r'[-+]')).first;
  final segs = core.split('.');
  return [
    for (var i = 0; i < 3; i++)
      i < segs.length ? (int.tryParse(segs[i].trim()) ?? 0) : 0,
  ];
}
