import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:flutter/material.dart';

/// How a voice participant is presented: display name, avatar image URL, and
/// the imageless-avatar background color.
typedef ParticipantDisplay = ({String name, String? avatarUrl, Color color});

/// Resolves [userId]'s display identity for the voice surfaces: the space
/// member (nickname + per-space avatar) wins over the cached bare user, and the
/// raw [userId] is the last-resort name. The avatar color needs a user object
/// (for its accent color), so a member without an embedded user falls through
/// to the cached bare user.
ParticipantDisplay participantDisplay(
  String userId, {
  required Map<String, AccordMember>? members,
  required Map<String, AccordUser>? users,
  required String? cdnUrl,
}) {
  final member = members?[userId];
  final user = users?[userId];
  return (
    name: accordAuthorNameOf(
      userId,
      member: member,
      user: user,
      fallback: userId,
    ),
    avatarUrl: accordAuthorAvatarUrlOf(
      member: member,
      user: user,
      cdnUrl: cdnUrl,
    ),
    color: accordAvatarColor(member?.user ?? user, userId),
  );
}
