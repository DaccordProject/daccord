import 'package:accordkit/accordkit.dart';
import 'package:collection/collection.dart';
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
/// name is empty/whitespace. Consolidates the
/// `name.isEmpty ? '?' : name[0].toUpperCase()` expression (and its
/// `.substring(0, 1)` / `.trim()` variants) duplicated across ~24 avatar sites.
String accordInitial(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, 1).toUpperCase();
}

/// Resolves a user's `avatar` reference to an absolute CDN URL, or null when
/// unset (callers fall back to an initial). The field is either a bare asset
/// hash or a server-relative/absolute path; both are handled.
String? accordAvatarUrl(AccordUser? user, String? cdnUrl) {
  final avatar = user?.avatar;
  if (avatar == null || avatar.isEmpty) return null;
  final cdn = cdnUrl ?? '';
  if (avatar.contains('/') || avatar.startsWith('http')) {
    return AccordCDN.resolvePath(avatar, cdnUrl: cdn);
  }
  return AccordCDN.avatar(user!.id, avatar,
      format: AccordCDN.autoFormat(avatar), cdnUrl: cdn);
}

/// Resolves a member's avatar, preferring a per-space avatar override
/// ([AccordMember.avatar]) over the user's global avatar. Mirrors the reference
/// client: an override starting with `/` is a CDN path; otherwise it's a bare
/// hash served from `/cdn/avatars/<hash>`. Falls back to the user avatar, then
/// null (callers render an initial).
String? accordMemberAvatarUrl(AccordMember? member, String? cdnUrl) {
  final override = member?.avatar;
  if (override is String && override.isNotEmpty) {
    final cdn = cdnUrl ?? '';
    if (override.startsWith('/') || override.startsWith('http')) {
      return AccordCDN.resolvePath(override, cdnUrl: cdn);
    }
    return AccordCDN.resolvePath('/cdn/avatars/$override', cdnUrl: cdn);
  }
  return accordAvatarUrl(member?.user, cdnUrl);
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
}) {
  final member = members?[authorId];
  if (member != null) return accordMemberName(member, fallback: fallback);
  final user = users?[authorId];
  if (user != null) return accordUserName(user, fallback: fallback);
  ensure?.call(authorId);
  return fallback;
}

/// Resolves a message/post author's avatar URL by `author_id`: member avatar
/// (with per-space override) first, then the global user avatar, else null
/// (callers render an initial). Companion to [accordAuthorName].
String? accordAuthorAvatarUrl(
  String authorId, {
  Map<String, AccordMember>? members,
  Map<String, AccordUser>? users,
  String? cdnUrl,
}) {
  final member = members?[authorId];
  if (member != null) return accordMemberAvatarUrl(member, cdnUrl);
  return accordAvatarUrl(users?[authorId], cdnUrl);
}

/// An Accord role color (RGB integer) as a [Color], or null when unset
/// (`0` is "no color" — the name renders in the default text color).
Color? accordRoleColor(int color) =>
    color == 0 ? null : Color(0xFF000000 | (color & 0xFFFFFF));

/// The reference client's fallback-avatar palette: 10 HSV hues at S 0.7, V 0.9
/// (see `client_models.gd _color_from_id`).
const List<double> _avatarPaletteHues = [
  0.0, 0.08, 0.16, 0.28, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95,
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
  AccordRole? best;
  for (final id in member.roles) {
    final role = spaceRoles.firstWhereOrNull((r) => r.id == id);
    if (role == null || !test(role)) continue;
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
