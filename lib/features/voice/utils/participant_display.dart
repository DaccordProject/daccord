import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:flutter/material.dart';

/// How a voice participant is presented: display name, avatar image URL, and
/// the imageless-avatar background color.
typedef ParticipantDisplay = ({String name, String? avatarUrl, Color color});

/// Resolves [userId]'s display identity for the voice surfaces, preferring the
/// space's member entry (nickname + per-space avatar override) over the bare
/// user from the global cache, and falling back to the raw [userId] as the
/// name while neither cache has resolved yet. A member without an embedded
/// user falls through to the global cache for profile details. [ensure] starts
/// a background profile fetch when both user sources are missing.
ParticipantDisplay participantDisplay(
  String userId, {
  required Map<String, AccordMember>? members,
  required Map<String, AccordUser>? users,
  required String? cdnUrl,
  void Function(String userId)? ensure,
}) {
  final member = members?[userId];
  final user = member?.user ?? users?[userId];
  if (user == null) ensure?.call(userId);
  final userName = accordUserName(user, fallback: userId);
  return (
    name: member != null
        ? accordMemberName(member, fallback: userName)
        : userName,
    avatarUrl:
        accordMemberAvatarUrl(member, cdnUrl) ?? accordAvatarUrl(user, cdnUrl),
    color: accordAvatarColor(user, userId),
  );
}
