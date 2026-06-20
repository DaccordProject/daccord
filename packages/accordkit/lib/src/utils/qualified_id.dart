/// Qualified-ID helpers for federation.
///
/// Every federated entity is keyed by a qualified ID of the form
/// `"<snowflake>@<domain>"`, where `<domain>` is the entity's **home server**.
/// Local entities keep bare snowflakes and are only qualified at the federation
/// boundary. These helpers mirror the server's rules (see
/// `src/federation/mapping.rs` in accordserver) so the same parsing lives in
/// exactly one place on the client too.
///
/// Cache/equality keys should always use the *full* qualified ID so a remote
/// `123@b.example` never collides with a local `123`.
library;

/// The local snowflake part of an ID, dropping any `@domain` suffix. A bare ID
/// is returned unchanged.
String localPart(String id) {
  final at = id.indexOf('@');
  return at < 0 ? id : id.substring(0, at);
}

/// The home domain encoded in a qualified ID, or `null` for a bare local ID.
String? domainOf(String id) {
  final at = id.indexOf('@');
  if (at < 0 || at == id.length - 1) return null;
  return id.substring(at + 1);
}

/// Whether [id] is a qualified (remote) ID — i.e. it carries an `@domain`.
bool isRemoteId(String id) => id.contains('@');

/// Qualifies a bare local [id] with [domain]. Already-qualified IDs (containing
/// `@`) are returned unchanged, so this is idempotent.
String qualify(String id, String domain) =>
    id.contains('@') ? id : '$id@$domain';
