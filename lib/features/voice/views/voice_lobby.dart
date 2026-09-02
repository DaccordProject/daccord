import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/utils/participant_display.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The pre-join state: participants already in the channel plus a Join button.
///
/// This is what opening a voice channel shows — selecting a channel never
/// connects (#202), so the lobby is the only thing standing between a stray
/// click and an audible join. [compact] lays it out as a fixed-height strip
/// above the chat panel for the narrow layout, where a centred column would
/// either push the chat off-screen or be pushed off itself.
class VoiceLobbyBody extends ConsumerWidget {
  const VoiceLobbyBody({
    required this.channelId,
    required this.spaceId,
    this.channelName,
    this.compact = false,
  });

  final String channelId;
  final String? spaceId;

  /// Titles the pre-join card. Null in the DM-call case, where the header
  /// already names who is being called.
  final String? channelName;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final states = ref.watch(
      voiceStatesControllerProvider(ref.readActiveServerKey() ?? '').select(
        (cache) => voiceStatesFor(cache, channelId),
      ),
    );
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(ref.readActiveServerKey() ?? '', spaceId!));
    final users = ref.watch(accordUsersControllerProvider(ref.readActiveServerKey() ?? ''));
    final cdnUrl = ref.watchCdnUrl();

    // Viewing a lobby while a call is running elsewhere is a normal state now
    // (clicking channel B no longer drags you out of channel A), so say so
    // rather than letting the lobby read as "you're in this channel".
    final (activeChannelId, activeSpaceId) = ref.watch(
      voiceControllerProvider.select((v) => (v.channelId, v.spaceId)),
    );
    final elsewhere = activeChannelId != null && activeChannelId != channelId;
    String? activeName;
    if (elsewhere && activeSpaceId != null) {
      activeName = ref.watch(
        accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', activeSpaceId).select(
          (channels) =>
              channels?.firstWhereOrNull((c) => c.id == activeChannelId)?.name,
        ),
      );
    }

    final avatars = <Widget>[];
    for (final vs in states) {
      final display = participantDisplay(
        vs.userId,
        members: members,
        users: users,
        cdnUrl: cdnUrl,
      );
      avatars.add(
        _LobbyAvatar(
          name: display.name,
          avatarUrl: display.avatarUrl,
          bg: display.color,
          compact: compact,
        ),
      );
    }

    // A bare "No one is here yet" line over a Join button reads as an
    // unfinished feature — voice/video/screen share is a headline feature and
    // has to look like one at rest (#292). Both presentations show the same
    // pre-join card: the channel it belongs to, who is already in it, the
    // media state you would join with, and what joining actually does.
    // [compact] only tightens it so the text chat below still has room.
    final theme = Theme.of(context);
    final selfMute = ref.watch(
      voiceControllerProvider.select((v) => v.selfMute),
    );

    final joinButton = FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: colors.green),
      onPressed: spaceId == null
          ? null
          : () => ref
                .read(voiceControllerProvider.notifier)
                .join(channelId, spaceId!),
      icon: const Icon(Icons.call),
      label: const Text('Join Voice'),
    );

    final note = elsewhere
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              activeName == null
                  ? "You're connected to another voice channel — joining moves you."
                  : "You're connected to #$activeName — joining moves you.",
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
          )
        : null;

    final card = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.volume_up,
              size: compact ? 18 : 20,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                channelName == null || channelName!.isEmpty
                    ? 'Voice channel'
                    : channelName!,
                overflow: TextOverflow.ellipsis,
                style:
                    (compact
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          switch (states.length) {
            0 => "No one is here yet — you'd be the first.",
            1 => '1 person is in this channel.',
            _ => '${states.length} people are in this channel.',
          },
          style:
              (compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
                  ?.copyWith(color: colors.gray),
        ),
        if (states.isNotEmpty) ...[
          SizedBox(height: compact ? 10 : 18),
          if (compact)
            SizedBox(
              height: 62,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final avatar in avatars)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: avatar,
                    ),
                ],
              ),
            )
          else
            Wrap(spacing: 12, runSpacing: 12, children: avatars),
        ],
        SizedBox(height: compact ? 10 : 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PreJoinChip(
              icon: selfMute ? Icons.mic_off : Icons.mic,
              label: selfMute ? 'Joining muted' : 'Microphone will be live',
            ),
            const _PreJoinChip(
              icon: Icons.videocam_off,
              label: 'Camera starts off',
            ),
            if (!kIsWeb)
              const _PreJoinChip(
                icon: Icons.screen_share_outlined,
                label: 'Screen share available',
              ),
          ],
        ),
        SizedBox(height: compact ? 10 : 16),
        Text(
          compact
              ? 'Turn your camera on or share a screen once you are in.'
              : 'Joining connects you to the call. Once in, you can mute, turn '
                    'your camera on, share a screen, and chat alongside the '
                    'call — and you stay until you disconnect.',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.gray),
        ),
        SizedBox(height: compact ? 12 : 20),
        SizedBox(height: 44, child: joinButton),
        if (note != null) note,
        if (!compact) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showVoiceSettings(context),
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Voice settings'),
            ),
          ),
        ],
      ],
    );

    // Compact: a fixed block above the chat panel, so joining never requires
    // closing the chat first (#202).
    if (compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.foreground,
          border: Border(
            bottom: BorderSide(color: colors.background, width: 1),
          ),
        ),
        child: card,
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            decoration: BoxDecoration(
              color: colors.foreground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: card,
          ),
        ),
      ),
    );
  }
}

/// One "here is what you'll join with" pill on the pre-join card. Read-only:
/// the media toggles only take effect once a LiveKit session exists, so the
/// card reports state rather than pretending to change it.
class _PreJoinChip extends StatelessWidget {
  const _PreJoinChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.dirtyWhite),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.dirtyWhite),
          ),
        ],
      ),
    );
  }
}

class _LobbyAvatar extends StatelessWidget {
  const _LobbyAvatar({
    required this.name,
    required this.avatarUrl,
    required this.bg,
    this.compact = false,
  });

  final String name;
  final String? avatarUrl;
  final Color bg;

  /// Smaller, for the narrow layout's participant strip.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final initial = accordInitial(name);
    return SizedBox(
      width: compact ? 56 : 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AccordMemberAvatar(
            avatarUrl: avatarUrl,
            initial: initial,
            radius: compact ? 18 : 24,
            backgroundColor: bg,
            initialStyle: TextStyle(fontSize: compact ? 14 : 18),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: colors.dirtyWhite),
          ),
        ],
      ),
    );
  }
}
