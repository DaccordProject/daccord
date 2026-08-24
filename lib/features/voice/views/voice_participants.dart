import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The list of users present in a voice [channelId], rendered as indented rows
/// beneath the channel tile in the sidebar. Ports the reference client's
/// `voice_channel_item.gd` participant strip: small avatar (green ring while
/// speaking), name in role color, and M/D/V/S flag glyphs.
class VoiceParticipantList extends ConsumerWidget {
  const VoiceParticipantList({
    super.key,
    required this.channelId,
    required this.spaceId,
    this.indent = 28,
  });

  final String channelId;
  final String? spaceId;
  final double indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(voiceStatesControllerProvider(ref.readActiveServerKey() ?? '')
        .select((cache) => voiceStatesFor(cache, channelId)));
    if (states.isEmpty) return const SizedBox.shrink();

    // Speaking highlights only apply while we're connected to this channel —
    // the speaking set is derived from our own LiveKit room.
    final speaking = ref.watch(voiceControllerProvider.select((v) =>
        v.channelId == channelId ? v.speakingUserIds : const <String>{}));

    // AFK, for #112. Remote members are read from presence (`idle`) — the
    // Accord voice state carries no AFK field, so an idle presence is the only
    // away signal that crosses the wire. Our own row uses the voice
    // controller's flag directly so it flips the instant we go away, without
    // waiting on the presence round-trip.
    final presences = ref.watch(activePresencesProvider);
    final selfAfk = ref.watch(voiceControllerProvider
        .select((v) => v.channelId == channelId && v.isAfk));
    final selfUserId = ref.watchUserId();

    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(ref.readActiveServerKey() ?? '', spaceId!));
    final users = ref.watch(accordUsersControllerProvider(ref.readActiveServerKey() ?? ''));
    final roles = spaceId == null
        ? const <AccordRole>[]
        : ref.watch(spacesControllerProvider.select((s) =>
                s?.firstWhereOrNull((sp) => sp.id == spaceId)?.roles)) ??
            const <AccordRole>[];
    final cdnUrl = ref.watchCdnUrl();

    final sorted = [...states]..sort((a, b) => _nameFor(a.userId, members, users)
        .toLowerCase()
        .compareTo(_nameFor(b.userId, members, users).toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final vs in sorted)
          _ParticipantRow(
            voiceState: vs,
            member: members?[vs.userId],
            user: users[vs.userId],
            roles: roles,
            cdnUrl: cdnUrl,
            speaking: speaking.contains(vs.userId),
            afk: (selfAfk && vs.userId == selfUserId) ||
                accordPresenceStatus(presences, vs.userId) == 'idle',
            indent: indent,
          ),
      ],
    );
  }
}

String _nameFor(
  String userId,
  Map<String, AccordMember>? members,
  Map<String, AccordUser> users,
) {
  final member = members?[userId];
  if (member != null) return accordMemberName(member, fallback: userId);
  return accordUserName(users[userId], fallback: userId);
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.voiceState,
    required this.member,
    required this.user,
    required this.roles,
    required this.cdnUrl,
    required this.speaking,
    required this.afk,
    required this.indent,
  });

  final AccordVoiceState voiceState;
  final AccordMember? member;
  final AccordUser? user;
  final List<AccordRole> roles;
  final String? cdnUrl;
  final bool speaking;

  /// Away from keyboard: dims the row and adds a moon badge.
  final bool afk;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final name = member != null
        ? accordMemberName(member, fallback: voiceState.userId)
        : accordUserName(user, fallback: voiceState.userId);
    final avatarUrl = member != null
        ? accordMemberAvatarUrl(member, cdnUrl)
        : accordAvatarUrl(user, cdnUrl);
    final avatarBg = accordAvatarColor(member?.user ?? user, voiceState.userId);
    final colorRole = member == null ? null : memberColorRole(member!, roles);
    final nameColor =
        (colorRole == null ? null : accordRoleColor(colorRole.color)) ??
            colors.dirtyWhite;
    final initial = accordInitial(name);

    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 1, 8, 1),
      child: Row(
        children: [
          Opacity(
            // Dimmed avatar for an away member, matching how every other chat
            // client signals "present but not here".
            opacity: afk ? 0.4 : 1,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: speaking
                    ? Border.all(color: colors.green, width: 2)
                    : null,
              ),
              padding: const EdgeInsets.all(1),
              child: AccordMemberAvatar(
                avatarUrl: avatarUrl,
                initial: initial,
                radius: 9,
                backgroundColor: avatarBg,
                initialStyle: const TextStyle(fontSize: 9),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(
                color: afk ? nameColor.withValues(alpha: 0.5) : nameColor,
              ),
            ),
          ),
          if (afk)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: 'Away',
                child: Icon(
                  Icons.nightlight_round,
                  size: 11,
                  color: colors.gray,
                  key: const Key('voice-participant-afk'),
                ),
              ),
            ),
          ..._flags(colors),
        ],
      ),
    );
  }

  List<Widget> _flags(BonfireThemeExtension colors) {
    final flags = <Widget>[];
    if (voiceState.selfDeaf) {
      flags.add(_flag('D', colors.red));
    } else if (voiceState.selfMute) {
      flags.add(_flag('M', colors.red));
    }
    if (voiceState.selfVideo) flags.add(_flag('V', colors.green));
    if (voiceState.selfStream) flags.add(_flag('S', colors.primary));
    return flags;
  }

  Widget _flag(String text, Color color) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.bold),
        ),
      );
}
