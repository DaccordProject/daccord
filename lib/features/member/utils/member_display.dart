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

/// An Accord role color (RGB integer) as a [Color], or null when unset
/// (`0` is "no color" — the name renders in the default text color).
Color? accordRoleColor(int color) =>
    color == 0 ? null : Color(0xFF000000 | (color & 0xFFFFFF));

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
