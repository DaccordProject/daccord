/// Humanizes a snake_case token into Title Case, e.g. `manage_channels` →
/// `Manage Channels`.
String titleCaseFromToken(String token) => token
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
