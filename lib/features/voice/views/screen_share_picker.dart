import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:universal_platform/universal_platform.dart';

/// Shows LiveKit's desktop screen/window source picker (Screen and Window tabs
/// with live thumbnails). Returns the chosen source, or null if cancelled.
Future<rtc.DesktopCapturerSource?> showScreenShareSourcePicker(
  BuildContext context,
) {
  return showDialog<rtc.DesktopCapturerSource>(
    context: context,
    barrierDismissible: true,
    builder: (_) => ScreenSelectDialog(),
  );
}

/// Starts or stops screen sharing for the current voice session.
///
/// On desktop, starting first prompts the user to pick a screen or window;
/// cancelling the picker aborts without sharing. On web/mobile the platform
/// shows its own native capture prompt, so we toggle directly.
Future<void> toggleScreenShareWithPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final notifier = ref.read(voiceControllerProvider.notifier);
  final sharing = ref.read(voiceControllerProvider).selfStream;

  if (sharing) {
    await notifier.toggleScreenShare();
    return;
  }

  if (UniversalPlatform.isDesktop) {
    final source = await showScreenShareSourcePicker(context);
    if (source == null) return; // cancelled
    await notifier.toggleScreenShare(sourceId: source.id);
  } else {
    await notifier.toggleScreenShare();
  }
}
