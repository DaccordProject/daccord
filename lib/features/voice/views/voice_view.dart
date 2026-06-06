import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import 'package:livekit_client/livekit_client.dart' as lk;

/// The voice channel screen shown in the message pane: a header, the video
/// grid (one tile per participant, camera/screen tracks or an initials
/// placeholder), and a control bar. Ports the reference client's voice view
/// (`main_window_voice_view.gd` + `video_grid.gd` + `video_tile.gd`), minus the
/// activity/plugin and PiP subsystems which this client doesn't have.
class VoiceChannelView extends ConsumerStatefulWidget {
  const VoiceChannelView({
    super.key,
    required this.channelId,
    required this.spaceId,
    required this.channelName,
  });

  final String channelId;
  final String? spaceId;
  final String? channelName;

  @override
  ConsumerState<VoiceChannelView> createState() => _VoiceChannelViewState();
}

class _VoiceChannelViewState extends ConsumerState<VoiceChannelView> {
  String? _spotlightUserId;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final connectedHere = ref.watch(voiceControllerProvider
        .select((v) => v.channelId == widget.channelId));

    return Container(
      color: colors.background,
      child: Column(
        children: [
          _header(context, colors),
          Expanded(
            child: connectedHere
                ? _ConnectedBody(
                    channelId: widget.channelId,
                    spaceId: widget.spaceId,
                    spotlightUserId: _spotlightUserId,
                    onToggleSpotlight: (userId) => setState(() =>
                        _spotlightUserId =
                            _spotlightUserId == userId ? null : userId),
                  )
                : _LobbyBody(
                    channelId: widget.channelId,
                    spaceId: widget.spaceId,
                  ),
          ),
          if (connectedHere)
            _ControlBar(channelId: widget.channelId, spaceId: widget.spaceId),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, BonfireThemeExtension colors) {
    return Container(
      height: 48,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.foreground, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.volume_up, size: 18, color: colors.dirtyWhite),
          const SizedBox(width: 6),
          Expanded(
            child: Text(widget.channelName ?? '',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
        ],
      ),
    );
  }
}

/// The pre-join state: participants already in the channel plus a Join button.
class _LobbyBody extends ConsumerWidget {
  const _LobbyBody({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final states = ref.watch(voiceStatesControllerProvider
        .select((cache) => voiceStatesFor(cache, channelId)));
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(spaceId!));
    final users = ref.watch(accordUsersControllerProvider);
    final cdnUrl = ref.watch(accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null));

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (states.isEmpty)
            Text('No one is here yet',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: colors.gray))
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final vs in states)
                  _LobbyAvatar(
                    name: members?[vs.userId] != null
                        ? accordMemberName(members![vs.userId],
                            fallback: vs.userId)
                        : accordUserName(users[vs.userId], fallback: vs.userId),
                    avatarUrl: members?[vs.userId] != null
                        ? accordMemberAvatarUrl(members![vs.userId], cdnUrl)
                        : accordAvatarUrl(users[vs.userId], cdnUrl),
                    bg: accordAvatarColor(
                        members?[vs.userId]?.user ?? users[vs.userId],
                        vs.userId),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: colors.green),
            onPressed: spaceId == null
                ? null
                : () => ref
                    .read(voiceControllerProvider.notifier)
                    .join(channelId, spaceId!),
            icon: const Icon(Icons.call),
            label: const Text('Join Voice'),
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
  });

  final String name;
  final String? avatarUrl;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: bg,
            foregroundImage: avatarUrl == null
                ? null
                : CachedNetworkImageProvider(avatarUrl!),
            child: Text(initial,
                style: TextStyle(color: accordOnColor(bg), fontSize: 18)),
          ),
          const SizedBox(height: 4),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall!
                  .copyWith(color: colors.dirtyWhite)),
        ],
      ),
    );
  }
}

/// A renderable tile: either a video track or a placeholder for [userId].
class _Tile {
  const _Tile({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.bg,
    required this.track,
    required this.isScreen,
    required this.muted,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final Color bg;
  final VideoTrack? track;
  final bool isScreen;
  final bool muted;
}

/// The in-call body: the video grid (or spotlight + strip).
class _ConnectedBody extends ConsumerWidget {
  const _ConnectedBody({
    required this.channelId,
    required this.spaceId,
    required this.spotlightUserId,
    required this.onToggleSpotlight,
  });

  final String channelId;
  final String? spaceId;
  final String? spotlightUserId;
  final ValueChanged<String> onToggleSpotlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild on any room change (track added/removed, speaker changes).
    ref.watch(voiceControllerProvider.select((v) => v.tick));
    final states = ref.watch(voiceStatesControllerProvider
        .select((cache) => voiceStatesFor(cache, channelId)));
    final speaking = ref.watch(
        voiceControllerProvider.select((v) => v.speakingUserIds));
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(spaceId!));
    final users = ref.watch(accordUsersControllerProvider);
    final cdnUrl = ref.watch(accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null));
    final myId = ref.watch(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.session.userId : null));
    final session = ref.read(voiceControllerProvider.notifier).session;

    String nameOf(String userId) => members?[userId] != null
        ? accordMemberName(members![userId], fallback: userId)
        : accordUserName(users[userId], fallback: userId);
    String? avatarOf(String userId) => members?[userId] != null
        ? accordMemberAvatarUrl(members![userId], cdnUrl)
        : accordAvatarUrl(users[userId], cdnUrl);
    Color bgOf(String userId) => accordAvatarColor(
        members?[userId]?.user ?? users[userId], userId);

    final tiles = <_Tile>[];
    for (final vs in states) {
      final isMe = vs.userId == myId;
      VideoTrack? camera;
      if (vs.selfVideo && session != null) {
        camera = isMe
            ? session.localCameraTrack
            : session.remoteCameraTrack(vs.userId);
      }
      tiles.add(_Tile(
        userId: vs.userId,
        name: nameOf(vs.userId),
        avatarUrl: avatarOf(vs.userId),
        bg: bgOf(vs.userId),
        track: camera,
        isScreen: false,
        muted: vs.selfMute || vs.selfDeaf,
      ));
      if (vs.selfStream && session != null) {
        final screen = isMe
            ? session.localScreenTrack
            : session.remoteScreenTrack(vs.userId);
        tiles.add(_Tile(
          userId: vs.userId,
          name: nameOf(vs.userId),
          avatarUrl: avatarOf(vs.userId),
          bg: bgOf(vs.userId),
          track: screen,
          isScreen: true,
          muted: false,
        ));
      }
    }

    if (tiles.isEmpty) {
      return const Center(child: Text('Connecting…'));
    }

    Widget tileWidget(_Tile t) => _VideoTile(
          key: ValueKey('${t.userId}:${t.isScreen}'),
          tile: t,
          speaking: speaking.contains(t.userId),
          spotlighted: spotlightUserId == t.userId,
          onDoubleTap: () => onToggleSpotlight(t.userId),
        );

    // Spotlight a chosen tile (or any active screen-share) above a strip.
    final spotlightIdx = spotlightUserId != null
        ? tiles.indexWhere((t) => t.userId == spotlightUserId)
        : tiles.indexWhere((t) => t.isScreen);
    if (spotlightIdx >= 0 && tiles.length > 1) {
      final rest = [
        for (var i = 0; i < tiles.length; i++)
          if (i != spotlightIdx) tiles[i]
      ];
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: tileWidget(tiles[spotlightIdx]),
            ),
          ),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final t in rest)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: AspectRatio(aspectRatio: 1, child: tileWidget(t)),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final columns = tiles.length <= 1
        ? 1
        : tiles.length <= 4
            ? 2
            : tiles.length <= 9
                ? 3
                : 4;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 16 / 10,
        children: [for (final t in tiles) tileWidget(t)],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    super.key,
    required this.tile,
    required this.speaking,
    required this.spotlighted,
    required this.onDoubleTap,
  });

  final _Tile tile;
  final bool speaking;
  final bool spotlighted;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final initial =
        tile.name.isEmpty ? '?' : tile.name.characters.first.toUpperCase();
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.foreground,
          borderRadius: BorderRadius.circular(8),
          border: speaking
              ? Border.all(color: colors.green, width: 2)
              : spotlighted
                  ? Border.all(color: colors.primary, width: 2)
                  : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (tile.track != null)
              lk.VideoTrackRenderer(
                tile.track!,
                fit: tile.isScreen
                    ? lk.VideoViewFit.contain
                    : lk.VideoViewFit.cover,
              )
            else
              Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: tile.bg,
                  foregroundImage: tile.avatarUrl == null
                      ? null
                      : CachedNetworkImageProvider(tile.avatarUrl!),
                  child: Text(initial,
                      style: TextStyle(
                          color: accordOnColor(tile.bg), fontSize: 20)),
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tile.muted) ...[
                      Icon(Icons.mic_off, size: 12, color: colors.red),
                      const SizedBox(width: 4),
                    ],
                    if (tile.isScreen) ...[
                      const Icon(Icons.screen_share,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                    ],
                    Text(tile.name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The in-call control bar at the bottom of the voice view.
class _ControlBar extends ConsumerWidget {
  const _ControlBar({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final voice = ref.watch(voiceControllerProvider);
    final notifier = ref.read(voiceControllerProvider.notifier);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.foreground,
        border: Border(top: BorderSide(color: colors.background, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ControlButton(
            icon: voice.selfMute ? Icons.mic_off : Icons.mic,
            tooltip: voice.selfMute ? 'Unmute' : 'Mute',
            active: voice.selfMute,
            activeColor: colors.red,
            onPressed: notifier.toggleMute,
          ),
          _ControlButton(
            icon: voice.selfDeaf ? Icons.headset_off : Icons.headset,
            tooltip: voice.selfDeaf ? 'Undeafen' : 'Deafen',
            active: voice.selfDeaf,
            activeColor: colors.red,
            onPressed: notifier.toggleDeafen,
          ),
          _ControlButton(
            icon: voice.selfVideo ? Icons.videocam_off : Icons.videocam,
            tooltip: voice.selfVideo ? 'Stop camera' : 'Camera',
            active: voice.selfVideo,
            activeColor: colors.green,
            onPressed: notifier.toggleVideo,
          ),
          if (!kIsWeb)
            _ControlButton(
              icon: voice.selfStream
                  ? Icons.stop_screen_share
                  : Icons.screen_share,
              tooltip: voice.selfStream ? 'Stop sharing' : 'Screen share',
              active: voice.selfStream,
              activeColor: colors.green,
              onPressed: notifier.toggleScreenShare,
            ),
          _ControlButton(
            icon: Icons.settings,
            tooltip: 'Voice settings',
            active: false,
            activeColor: colors.primary,
            onPressed: () => showVoiceSettings(context),
          ),
          _ControlButton(
            icon: Icons.call_end,
            tooltip: 'Disconnect',
            active: true,
            activeColor: colors.red,
            onPressed: notifier.leave,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.activeColor,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: active ? activeColor : colors.darkGray,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon,
              size: 20,
              color: active ? Colors.white : colors.dirtyWhite),
        ),
      ),
    );
  }
}
