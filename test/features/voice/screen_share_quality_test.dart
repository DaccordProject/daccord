import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the arguments the controller hands the LiveKit session, so the
/// screen-share quality path can be asserted without a native room.
class _RecordingSession extends VoiceSession {
  bool? enabled;
  int? width;
  int? height;
  int? fps;
  int? bitrate;
  bool? motionPriority;
  int calls = 0;

  // Camera capture, recorded separately so a test can prove the two toggles
  // read different settings.
  int? cameraWidth;
  int? cameraHeight;
  int? cameraFps;
  int? cameraBitrate;

  @override
  Future<void> setScreenShareEnabled(
    bool enabled, {
    String? sourceId,
    int? width,
    int? height,
    int? fps,
    int? bitrate,
    bool motionPriority = true,
  }) async {
    calls++;
    this.enabled = enabled;
    this.width = width;
    this.height = height;
    this.fps = fps;
    this.bitrate = bitrate;
    this.motionPriority = motionPriority;
  }

  @override
  Future<void> setCameraEnabled(
    bool enabled, {
    int? width,
    int? height,
    int? fps,
    int? bitrate,
    String? deviceId,
  }) async {
    cameraWidth = width;
    cameraHeight = height;
    cameraFps = fps;
    cameraBitrate = bitrate;
  }
}

/// A [VoiceController] that starts out "connected" (so the media toggles run)
/// without ever touching LiveKit or the gateway.
class _ConnectedVoiceController extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection(channelId: 'c1');
}

class _FixedSettingsController extends SettingsController {
  _FixedSettingsController(this._settings);
  final AccordSettings _settings;
  @override
  AccordSettings build() => _settings;
}

({ProviderContainer container, _RecordingSession session}) _harness(
  AccordSettings settings,
) {
  final container = ProviderContainer(
    overrides: [
      settingsControllerProvider.overrideWith(
        () => _FixedSettingsController(settings),
      ),
      voiceControllerProvider.overrideWith(_ConnectedVoiceController.new),
    ],
  );
  addTearDown(container.dispose);
  final session = _RecordingSession();
  container.read(voiceControllerProvider.notifier).debugSession = session;
  return (container: container, session: session);
}

void main() {
  group('toggleScreenShare quality', () {
    test('passes the screen-share settings, not the camera ones', () async {
      // Camera deliberately set to something different from screen share, so a
      // regression that reads `videoDimensions`/`videoFps`/`videoBitrate`
      // again fails here.
      const settings = AccordSettings(
        videoResolution: 0, // 854x480 camera
        videoFps: 15,
        screenShareResolution: 1, // 1920x1080 share
        screenShareFps: 60,
      );
      final h = _harness(settings);

      await h.container
          .read(voiceControllerProvider.notifier)
          .toggleScreenShare();

      expect(h.session.enabled, isTrue);
      expect(h.session.width, 1920);
      expect(h.session.height, 1080);
      expect(h.session.fps, 60);
      expect(h.session.bitrate, settings.screenShareBitrate);
      expect(h.session.motionPriority, isTrue);

      // The camera values it used to send.
      expect(h.session.width, isNot(854));
      expect(h.session.fps, isNot(settings.videoFps));
      expect(h.session.bitrate, isNot(settings.videoBitrate));
    });

    test('the default install shares at 720p60, not 720p30', () async {
      final h = _harness(const AccordSettings());

      await h.container
          .read(voiceControllerProvider.notifier)
          .toggleScreenShare();

      expect(h.session.width, 1280);
      expect(h.session.height, 720);
      expect(h.session.fps, 60);
      expect(h.session.bitrate, 3000000);
    });

    test('the motion-priority preference is forwarded', () async {
      final h = _harness(
        const AccordSettings(screenShareMotionPriority: false),
      );

      await h.container
          .read(voiceControllerProvider.notifier)
          .toggleScreenShare();

      expect(h.session.motionPriority, isFalse);
    });

    test('toggling again stops the share', () async {
      final h = _harness(const AccordSettings());
      final notifier = h.container.read(voiceControllerProvider.notifier);

      await notifier.toggleScreenShare();
      expect(h.container.read(voiceControllerProvider).selfStream, isTrue);

      await notifier.toggleScreenShare();
      expect(h.session.enabled, isFalse);
      expect(h.session.calls, 2);
      expect(h.container.read(voiceControllerProvider).selfStream, isFalse);
    });

    test('the camera toggle still uses the camera settings', () async {
      const settings = AccordSettings(
        videoResolution: 2, // 1920x1080 camera
        videoFps: 30,
        screenShareResolution: 0,
        screenShareFps: 60,
      );
      final h = _harness(settings);

      await h.container.read(voiceControllerProvider.notifier).toggleVideo();

      expect(h.session.cameraWidth, 1920);
      expect(h.session.cameraHeight, 1080);
      expect(h.session.cameraFps, 30);
      expect(h.session.cameraBitrate, settings.videoBitrate);
    });
  });

  group('screen-share fallbacks', () {
    test('an unspecified frame rate means 60, never LiveKit\'s 15 fps '
        'slideshow preset', () {
      expect(defaultScreenShareFps, 60);
      expect(defaultScreenShareFps, AccordSettings.defaultScreenShareFps);
    });

    test('the fallback bitrate matches the 720p60 setting', () {
      expect(
        defaultScreenShareBitrate,
        const AccordSettings().screenShareBitrate,
      );
    });
  });
}
