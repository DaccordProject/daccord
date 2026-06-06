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
