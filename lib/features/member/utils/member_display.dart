import 'package:accordkit/accordkit.dart';
import 'package:flutter/material.dart';

/// Resolves a member's preferred display name: nickname → user display name →
/// username → [fallback].
String accordMemberName(AccordMember? member, {String fallback = 'Unknown'}) {
  final nick = member?.nickname;
  if (nick != null && nick.isNotEmpty) return nick;
  final display = member?.user?.displayName;
  if (display != null && display.isNotEmpty) return display;
  final username = member?.user?.username;
  if (username != null && username.isNotEmpty) return username;
  return fallback;
}

/// Resolves a bare user's preferred display name: display name → username →
/// [fallback]. Used for authors/typers resolved via the on-demand user cache
/// (outside a space's loaded member page), where no [AccordMember] exists.
String accordUserName(AccordUser? user, {String fallback = 'Unknown'}) {
  final display = user?.displayName;
  if (display != null && display.isNotEmpty) return display;
  final username = user?.username;
  if (username != null && username.isNotEmpty) return username;
  return fallback;
}

/// The single uppercase initial drawn on an imageless avatar, or `?` when the
/// name is empty/whitespace.
String accordInitial(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, 1).toUpperCase();
}

/// The CDN base URL for a federated home [domain] (e.g. `b.example` →
/// `https://b.example/cdn`), or `null` when [domain] is not a safe host to fetch
/// from. Used to resolve a remote user's avatar/banner against their *home*
/// server rather than the connected server. A federated peer supplies [domain],
/// so it is validated as a real hostname (optionally with a `:port`) and
/// rejected when it is loopback/link-local — otherwise a malicious origin could
/// point image fetches at internal/cloud-metadata addresses or smuggle
/// userinfo/path into the host. Mirrors the per-server CDN derivation in
/// `AccordServer.fromBaseUrl`.
String? cdnBaseForDomain(String domain) =>
    _isSafeFederationHost(domain) ? 'https://$domain/cdn' : null;

/// Validates a federation [domain] that may carry an optional `:port`: a real
/// hostname that is not loopback/link-local.
bool _isSafeFederationHost(String domain) {
  var host = domain;
  final colon = domain.lastIndexOf(':');
  if (colon != -1) {
    if (int.tryParse(domain.substring(colon + 1)) == null) return false;
    host = domain.substring(0, colon);
  }
  return isValidHost(host) && !isLoopbackOrLinkLocalHost(host);
}

/// Whether [asset] is safe to fetch for a remote home [domain]: a relative path
/// (resolved against the home CDN) or an absolute URL whose host is the home
/// [domain] itself. An absolute URL pointing anywhere else is rejected so a
/// remote object can't turn an avatar/emoji into an off-home tracking fetch.
bool _assetAllowedForDomain(String asset, String domain) {
  if (!(asset.startsWith('http://') || asset.startsWith('https://'))) {
    return true; // relative — resolves against the home CDN
  }
  final uri = Uri.tryParse(asset);
  if (uri == null) return false;
  final colon = domain.lastIndexOf(':');
  final host = colon != -1 && int.tryParse(domain.substring(colon + 1)) != null
      ? domain.substring(0, colon)
      : domain;
  return uri.host.toLowerCase() == host.toLowerCase();
}

/// The home domain of a remote (federated) user, or null when local. Falls back
/// to the domain embedded in a qualified id when `origin` isn't set explicitly.
String? accordUserOrigin(AccordUser? user) {
  if (user == null) return null;
  final origin = user.origin;
  if (origin != null && origin.isNotEmpty) return origin;
  return domainOf(user.id);
}

/// The home domain of a remote (federated) member, or null when local.
String? accordMemberOrigin(AccordMember? member) => member?.homeDomain;

/// Resolves a user's `avatar` reference to an absolute CDN URL, or null when
/// unset (callers fall back to an initial). The field is either a bare asset
/// hash or a server-relative/absolute path; both are handled. For a remote
/// (federated) user the asset lives on their *home* server, so a bare hash or
/// server-relative path resolves against the home domain's CDN rather than the
/// connected server's; absolute URLs (already rewritten server-side) pass
/// through unchanged.
String? accordAvatarUrl(AccordUser? user, String? cdnUrl) =>
    _userAvatarUrl(user, cdnUrl, domain: accordUserOrigin(user));

String? _userAvatarUrl(AccordUser? user, String? cdnUrl, {String? domain}) {
  final avatar = user?.avatar;
  if (avatar == null || avatar.isEmpty) return null;
  final String cdn;
  if (domain != null) {
    final base = cdnBaseForDomain(domain);
    // Unsafe home domain, or an absolute URL that points off the home server:
    // render an initial rather than fetch from an untrusted host.
    if (base == null || !_assetAllowedForDomain(avatar, domain)) return null;
    cdn = base;
  } else {
    cdn = cdnUrl ?? '';
  }
  if (avatar.contains('/') || avatar.startsWith('http')) {
    return AccordCDN.resolvePath(avatar, cdnUrl: cdn);
  }
  // A remote user's id is qualified; the home CDN keys avatars by the bare
  // snowflake, so strip any `@domain` before building the path.
  return AccordCDN.avatar(
    localPart(user!.id),
    avatar,
    format: AccordCDN.autoFormat(avatar),
    cdnUrl: cdn,
  );
}

/// Resolves a member's avatar, preferring a per-space avatar override
/// ([AccordMember.avatar]) over the user's global avatar. Mirrors the reference
/// client: an override starting with `/` is a CDN path; otherwise it's a bare
/// hash served from `/cdn/avatars/<hash>`. Falls back to the user avatar, then
/// null (callers render an initial). Remote members resolve assets against their
/// home server's CDN.
String? accordMemberAvatarUrl(AccordMember? member, String? cdnUrl) {
  final domain = member?.homeDomain;
  final override = member?.avatar;
  if (override is String && override.isNotEmpty) {
    final String cdn;
    if (domain != null) {
      final base = cdnBaseForDomain(domain);
      // Unsafe home domain, or an off-home absolute override: fall back to the
      // user's global avatar (itself home-gated) rather than fetch off-home.
      if (base == null || !_assetAllowedForDomain(override, domain)) {
        return _userAvatarUrl(member?.user, cdnUrl, domain: domain);
      }
      cdn = base;
    } else {
      cdn = cdnUrl ?? '';
    }
    if (override.startsWith('/') || override.startsWith('http')) {
      return AccordCDN.resolvePath(override, cdnUrl: cdn);
    }
    return AccordCDN.resolvePath('/cdn/avatars/$override', cdnUrl: cdn);
  }
  return _userAvatarUrl(member?.user, cdnUrl, domain: domain);
}

/// Resolves a custom [emoji] to an absolute image URL, applying the same
/// federation trust boundary as avatars: a remote emoji (one carrying an
/// `origin`) resolves against its home server's CDN, and an absolute `imageUrl`
/// is honoured only when it points at that home server. Returns null when there
/// is nothing safe to show (callers render the emoji name/placeholder).
String? accordEmojiUrl(AccordEmoji emoji, String? cdnUrl) {
  final domain = emoji.origin;
  final remote = domain != null && domain.isNotEmpty;
  final String cdn;
  if (remote) {
    final base = cdnBaseForDomain(domain);
    if (base == null) return null; // unsafe home domain
    cdn = base;
  } else {
    cdn = cdnUrl ?? '';
  }
  if (emoji.imageUrl.isNotEmpty) {
    if (remote && !_assetAllowedForDomain(emoji.imageUrl, domain)) return null;
    return AccordCDN.resolvePath(emoji.imageUrl, cdnUrl: cdn);
  }
  final id = emoji.id;
  if (id == null) return null;
  // A remote emoji id is qualified; the home CDN keys by the bare snowflake.
  return AccordCDN.emoji(
    localPart(id),
    format: emoji.animated ? 'gif' : 'png',
    cdnUrl: cdn,
  );
}

/// Resolves a message/post author's display name by `author_id`, consulting the
/// space member cache first, then the on-demand global user cache, then
/// [fallback]. When neither cache has the author yet it schedules a fetch via
/// [ensure] (safe to call during build — the user controller dedupes and only
/// mutates post-request). Mirrors the reference client, which shows "Unknown"
/// until the user resolves rather than the raw snowflake ID. Use this anywhere a
/// surface renders `authorId` so identity is consistent and never a raw ID.
String accordAuthorName(
  String authorId, {
  Map<String, AccordMember>? members,
  Map<String, AccordUser>? users,
  void Function(String userId)? ensure,
  String fallback = 'Unknown',
}) => accordAuthorNameOf(
  authorId,
  member: members?[authorId],
  user: users?[authorId],
  ensure: ensure,
  fallback: fallback,
);

/// Single-author variant of [accordAuthorName], for per-row widgets that scope
/// their cache watches to one author (`.select((m) => m[authorId])`) instead of
/// passing whole member/user maps down the tree.
String accordAuthorNameOf(
  String authorId, {
  AccordMember? member,
  AccordUser? user,
  void Function(String userId)? ensure,
  String fallback = 'Unknown',
}) {
  if (member != null) return accordMemberName(member, fallback: fallback);
  if (user != null) return accordUserName(user, fallback: fallback);
  ensure?.call(authorId);
  return fallback;
}

/// Resolves a message/post author's avatar URL from the already-selected
/// member/user cache entries. The member avatar (including a per-space
/// override) wins over the global user avatar; callers render an initial when
/// neither exists. Companion to [accordAuthorNameOf].
String? accordAuthorAvatarUrlOf({
  AccordMember? member,
  AccordUser? user,
  String? cdnUrl,
}) {
  if (member != null) return accordMemberAvatarUrl(member, cdnUrl);
  return accordAvatarUrl(user, cdnUrl);
}

/// An Accord role color (RGB integer) as a [Color], or null when unset
/// (`0` is "no color" — the name renders in the default text color).
Color? accordRoleColor(int color) =>
    color == 0 ? null : Color(0xFF000000 | (color & 0xFFFFFF));

/// The reference client's fallback-avatar palette: 10 HSV hues at S 0.7, V 0.9
/// (see `client_models.gd _color_from_id`).
const List<double> _avatarPaletteHues = [
  0.0,
  0.08,
  0.16,
  0.28,
  0.45,
  0.55,
  0.65,
  0.75,
  0.85,
  0.95,
];

/// A deterministic background color for an avatar with no image, derived from a
/// user/space ID so each identity gets a stable color. Mirrors the reference
/// client, which tints initial-only avatars instead of using a flat grey. The
/// hash differs from Godot's `String.hash`, so colors won't match the Godot
/// client exactly — only the per-id stability matters.
Color accordIdColor(String id) {
  if (id.isEmpty) return const Color(0xFF4F545C);
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  final hue = _avatarPaletteHues[hash % _avatarPaletteHues.length];
  return HSVColor.fromAHSV(1, hue * 360, 0.7, 0.9).toColor();
}

/// Black or white, whichever reads better on [background] — for the initial
/// letter drawn over an [accordIdColor] avatar.
Color accordOnColor(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

/// The background color for an imageless avatar: the user's chosen
/// `accent_color` when set, otherwise the deterministic [accordIdColor] derived
/// from [fallbackId]. "Transparent" in the picker means no `accent_color`, which
/// falls through to the auto color — never a blank swatch.
Color accordAvatarColor(AccordUser? user, String fallbackId) {
  final accent = user?.accentColor;
  if (accent is int && accent > 0) {
    return Color(0xFF000000 | (accent & 0xFFFFFF));
  }
  return accordIdColor(fallbackId);
}

/// The dot color for a presence status, or null for offline/unknown (callers
/// hide the dot or render it muted).
Color? accordPresenceColor(String status) {
  switch (status) {
    case 'online':
      return const Color(0xFF3BA55D);
    case 'idle':
      return const Color(0xFFFAA81A);
    case 'dnd':
      return const Color(0xFFED4245);
    default:
      return null;
  }
}

/// The highest-positioned role assigned to [member] (looked up in [spaceRoles])
/// that matches [test], or null when the member has no such role.
AccordRole? _highestRole(
  AccordMember member,
  List<AccordRole> spaceRoles,
  bool Function(AccordRole) test,
) {
  final roleIds = member.roles.toSet();
  AccordRole? best;
  for (final role in spaceRoles) {
    if (!roleIds.contains(role.id) || !test(role)) continue;
    if (best == null || role.position > best.position) best = role;
  }
  return best;
}

/// The role that determines a member's name color: their highest-positioned
/// colored role, or null.
AccordRole? memberColorRole(AccordMember member, List<AccordRole> spaceRoles) =>
    _highestRole(member, spaceRoles, (r) => r.color != 0);

/// The role a member is grouped under in the roster: their highest-positioned
/// hoisted role, or null (ungrouped members fall under a default section).
AccordRole? memberHoistRole(AccordMember member, List<AccordRole> spaceRoles) =>
    _highestRole(member, spaceRoles, (r) => r.hoist);
