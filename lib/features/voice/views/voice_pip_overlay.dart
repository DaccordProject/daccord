import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_client/livekit_client.dart' show VideoTrack;

/// A small, draggable picture-in-picture window that floats over the app while
/// connected to a voice channel that has active video, but only when the user
/// has navigated away from that channel. Tapping it jumps back to the voice
/// channel. Ports the reference client's PiP (`main_window_voice_view.gd`
/// `maybe_spawn_pip` / `video_pip.gd`): it only appears when there is video to
/// show, and clicking it reopens the voice view.
///
/// Designed to be dropped directly into a [Stack] (it returns a [Positioned]).
class VoicePipOverlay extends ConsumerStatefulWidget {
  const VoicePipOverlay({
    super.key,
    required this.shownChannelId,
    required this.onOpen,
  });

  /// The channel currently on screen. The PiP hides while the voice channel is
  /// the one being viewed (the full voice view is already showing).
  final String? shownChannelId;

  /// Jumps to the voice channel ([channelId], [spaceId]) when the PiP is tapped.
  final void Function(String channelId, String spaceId) onOpen;

  @override
  ConsumerState<VoicePipOverlay> createState() => _VoicePipOverlayState();
}

class _VoicePipOverlayState extends ConsumerState<VoicePipOverlay> {
  // Top-left position of the PiP. Null until first laid out (then anchored to
  // the bottom-right corner).
  Offset? _pos;

  static const double _w = 200;
  static const double _h = 124;
  static const double _margin = 12;

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceControllerProvider);
    // Rebuild as tracks come and go.
    ref.watch(voiceControllerProvider.select((v) => v.tick));

    final channelId = voice.channelId;
    final spaceId = voice.spaceId;
    final viewingVoice =
        channelId != null && widget.shownChannelId == channelId;
    if (!voice.isConnected ||
        channelId == null ||
        spaceId == null ||
        viewingVoice) {
      return const SizedBox.shrink();
    }

    final track = _firstVideoTrack();
    if (track == null) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    final pos = _clamp(
      _pos ??
          Offset(size.width - _w - _margin, size.height - _h - _margin * 2),
      size,
    );

    final colors = BonfireThemeExtension.of(context);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onTap: () => widget.onOpen(channelId, spaceId),
        onPanUpdate: (d) => setState(() => _pos = _clamp(pos + d.delta, size)),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: _w,
            height: _h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: lk.VideoTrackRenderer(track,
                      fit: lk.VideoViewFit.contain),
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Disconnect',
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () =>
                          ref.read(voiceControllerProvider.notifier).leave(),
                      icon: Icon(Icons.call_end, color: colors.red),
                    ),
                  ),
                ),
                const Positioned(
                  left: 4,
                  bottom: 4,
                  child: Icon(Icons.open_in_full,
                      size: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Offset _clamp(Offset p, Size screen) {
    final maxX = (screen.width - _w - _margin).clamp(_margin, double.infinity);
    final maxY = (screen.height - _h - _margin).clamp(_margin, double.infinity);
    return Offset(
      p.dx.clamp(_margin, maxX),
      p.dy.clamp(_margin, maxY),
    );
  }

  /// The first available video track to preview: our own screen-share or
  /// camera first, otherwise any remote participant's screen/camera.
  VideoTrack? _firstVideoTrack() {
    final session = ref.read(voiceControllerProvider.notifier).session;
    if (session == null) return null;
    final voice = ref.read(voiceControllerProvider);
    final myId = ref.readUserId();

    if (voice.selfStream && session.localScreenTrack != null) {
      return session.localScreenTrack;
    }
    if (voice.selfVideo && session.localCameraTrack != null) {
      return session.localCameraTrack;
    }

    final channelId = voice.channelId;
    if (channelId == null) return null;
    final states = voiceStatesFor(
      ref.read(voiceStatesControllerProvider),
      channelId,
    );
    for (final vs in states) {
      if (vs.userId == myId) continue;
      if (vs.selfStream) {
        final t = session.remoteScreenTrack(vs.userId);
        if (t != null) return t;
      }
      if (vs.selfVideo) {
        final t = session.remoteCameraTrack(vs.userId);
        if (t != null) return t;
      }
    }
    return null;
  }
}
