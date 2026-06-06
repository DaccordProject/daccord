import 'dart:async';

import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/views/mic_level_meter.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The voice-connection panel shown above the user controls while connected to
/// a channel. Ports the reference client's `voice_bar.gd`: a status row
/// (channel name + pulsing connection dot, with transient errors) over a row of
/// mute / deafen / video / screen-share / disconnect buttons.
class VoiceBar extends ConsumerStatefulWidget {
  const VoiceBar({super.key, this.onTapStatus});

  /// Called when the status row is tapped — the host opens the voice view for
  /// the connected channel.
  final VoidCallback? onTapStatus;

  @override
  ConsumerState<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends ConsumerState<VoiceBar> {
  Timer? _errorTimer;

  @override
  void dispose() {
    _errorTimer?.cancel();
    super.dispose();
  }

  void _scheduleErrorClear() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) ref.read(voiceControllerProvider.notifier).clearError();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final voice = ref.watch(voiceControllerProvider);
    if (!voice.isConnected) return const SizedBox.shrink();

    // Drive the 4s error auto-dismiss off the current state.
    if (voice.error != null) {
      _scheduleErrorClear();
    }

    final channelName = voice.spaceId == null
        ? null
        : ref
            .watch(accordChannelsControllerProvider(voice.spaceId!))
            ?.firstWhereOrNull((c) => c.id == voice.channelId)
            ?.name;

    final (statusText, statusColor) = _status(voice, colors, channelName);

    return Material(
      color: colors.darkGray,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: widget.onTapStatus,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusText,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium!
                            .copyWith(color: statusColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _VoiceButton(
                  icon: voice.selfMute ? Icons.mic_off : Icons.mic,
                  tooltip: voice.selfMute ? 'Unmute' : 'Mute',
                  active: voice.selfMute,
                  activeColor: colors.red,
                  onPressed: () =>
                      ref.read(voiceControllerProvider.notifier).toggleMute(),
                ),
                _VoiceButton(
                  icon: voice.selfDeaf ? Icons.headset_off : Icons.headset,
                  tooltip: voice.selfDeaf ? 'Undeafen' : 'Deafen',
                  active: voice.selfDeaf,
                  activeColor: colors.red,
                  onPressed: () =>
                      ref.read(voiceControllerProvider.notifier).toggleDeafen(),
                ),
                _VoiceButton(
                  icon: voice.selfVideo ? Icons.videocam_off : Icons.videocam,
                  tooltip: voice.selfVideo ? 'Stop camera' : 'Camera',
                  active: voice.selfVideo,
                  activeColor: colors.green,
                  onPressed: () =>
                      ref.read(voiceControllerProvider.notifier).toggleVideo(),
                ),
                if (!kIsWeb)
                  _VoiceButton(
                    icon: voice.selfStream
                        ? Icons.stop_screen_share
                        : Icons.screen_share,
                    tooltip: voice.selfStream ? 'Stop sharing' : 'Screen share',
                    active: voice.selfStream,
                    activeColor: colors.green,
                    onPressed: () => ref
                        .read(voiceControllerProvider.notifier)
                        .toggleScreenShare(),
                  ),
                const Spacer(),
                _VoiceButton(
                  icon: Icons.settings,
                  tooltip: 'Voice settings',
                  active: false,
                  activeColor: colors.primary,
                  onPressed: () => showVoiceSettings(context),
                ),
                _VoiceButton(
                  icon: Icons.call_end,
                  tooltip: 'Disconnect',
                  active: false,
                  activeColor: colors.red,
                  iconColor: colors.red,
                  onPressed: () =>
                      ref.read(voiceControllerProvider.notifier).leave(),
                ),
              ],
            ),
            // Live mic-activity meter — shows the user their input is picked up.
            if (!voice.selfMute) ...[
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: MicLevelMeter(height: 4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (String, Color) _status(
    VoiceConnection voice,
    BonfireThemeExtension colors,
    String? channelName,
  ) {
    if (voice.error != null) return (voice.error!, colors.red);
    switch (voice.sessionState) {
      case VoiceSessionState.connected:
        return (channelName ?? 'Voice connected', colors.green);
      case VoiceSessionState.connecting:
        return ('Connecting…', colors.yellow);
      case VoiceSessionState.reconnecting:
        return ('Reconnecting…', colors.yellow);
      case VoiceSessionState.failed:
        return ('Connection failed', colors.red);
      case VoiceSessionState.disconnected:
        return (channelName ?? 'Voice', colors.gray);
    }
  }
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.activeColor,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final Color activeColor;
  final Color? iconColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: active
            ? activeColor.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon,
              size: 18, color: iconColor ?? colors.dirtyWhite),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ),
    );
  }
}
