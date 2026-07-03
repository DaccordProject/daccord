import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:flutter/material.dart';

/// How a voice participant (or voice text-panel author) is presented: display
/// name, avatar image URL, and the imageless-avatar background color.
typedef ParticipantDisplay = ({String name, String? avatarUrl, Color color});

/// Resolves [userId]'s display identity for the voice surfaces, preferring the
/// space's member entry (nickname + per-space avatar override) over the bare
/// user from the global cache, and falling back to the raw [userId] as the
/// name when neither cache has resolved yet. The avatar color needs a user
/// object (for its accent color), so a member row without an embedded user
/// falls through to the cached bare user — matching the inline triples this
/// consolidates (voice lobby, video grid, voice text panel).
ParticipantDisplay participantDisplay(
  String userId, {
  required Map<String, AccordMember>? members,
  required Map<String, AccordUser>? users,
  required String? cdnUrl,
}) {
  final member = members?[userId];
  final user = users?[userId];
  return (
    name: member != null
        ? accordMemberName(member, fallback: userId)
        : accordUserName(user, fallback: userId),
    avatarUrl: member != null
        ? accordMemberAvatarUrl(member, cdnUrl)
        : accordAvatarUrl(user, cdnUrl),
    color: accordAvatarColor(member?.user ?? user, userId),
  );
}
