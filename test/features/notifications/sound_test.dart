import 'package:audioplayers/audioplayers.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Thin wrapper so each case reads as the decision under test, defaulting the
  // "enabled & audible" knobs that most cases share.
  String? decide({
    bool isMention = false,
    bool isVisibleChannel = false,
    bool isMemberJoin = false,
    bool focused = true,
    bool enabled = true,
    double volume = 1.0,
  }) => SoundManager.soundForMessage(
    isMention: isMention,
    isVisibleChannel: isVisibleChannel,
    isMemberJoin: isMemberJoin,
    focused: focused,
    enabled: enabled,
    volume: volume,
  );

  group('SoundManager.soundForMessage', () {
    test('a member join plays member_join', () {
      expect(decide(isMemberJoin: true), 'member_join');
    });

    test('member join plays even in the visible channel', () {
      expect(decide(isMemberJoin: true, isVisibleChannel: true), 'member_join');
    });

    test('the visible channel is silent, even for a mention', () {
      expect(decide(isVisibleChannel: true), isNull);
      expect(decide(isVisibleChannel: true, isMention: true), isNull);
    });

    test('a mention outside the visible channel plays mention_received', () {
      expect(decide(isMention: true), 'mention_received');
    });

    test('a mention chimes even while focused', () {
      expect(decide(isMention: true, focused: true), 'mention_received');
    });

    test('a non-mention while unfocused plays message_received', () {
      expect(decide(isMention: false, focused: false), 'message_received');
    });

    test('a non-mention while focused is silent', () {
      expect(decide(isMention: false, focused: true), isNull);
    });

    group('gating', () {
      test('disabled sounds are silent regardless of the message', () {
        expect(decide(enabled: false, isMention: true), isNull);
        expect(decide(enabled: false, isMemberJoin: true), isNull);
        expect(decide(enabled: false, focused: false), isNull);
      });

      test('zero volume is silent regardless of the message', () {
        expect(decide(volume: 0.0, isMention: true), isNull);
        expect(decide(volume: 0.0, isMemberJoin: true), isNull);
      });

      test('negative volume is treated as muted', () {
        expect(decide(volume: -0.5, isMention: true), isNull);
      });
    });
  });

  group('SoundManager.silent', () {
    test('defaults to true under flutter test', () {
      // The guard that keeps audio plugins — and the path_provider call behind
      // them — out of the test VM (#220). If this ever defaults to false,
      // every chime fired from code under test throws MissingPluginException
      // from an async gap and fails an unrelated test.
      expect(SoundManager.silent, isTrue);
    });

    test(
      'play is a no-op while silent, even when enabled and audible',
      () async {
        soundManager.enabled = true;
        soundManager.volume = 1.0;

        // Reaching a real AudioPlayer here would throw rather than return.
        await expectLater(soundManager.play('message_received'), completes);
        await expectLater(soundManager.startRingtone(), completes);
        await expectLater(soundManager.stopRingtone(), completes);
      },
    );

    test('init is a no-op while silent', () {
      expect(soundManager.init, returnsNormally);
    });

    test('dispose is a no-op while silent', () {
      // Guards against forcing the late `_pool`/`_ringPlayer` fields into
      // existence just to tear them down — that construction reaches the
      // platform the same as `play` does.
      expect(soundManager.dispose, returnsNormally);
    });
  });

  group('SoundManager during a voice call (#323)', () {
    tearDown(() => soundManager.setVoiceSessionActive(false));

    test('one-shot chimes are held back only on iOS', () {
      // iOS: audioplayers deactivates the shared AVAudioSession when a one-shot
      // finishes, which kills WebRTC's capture/playback mid-call.
      expect(
        SoundManager.allowsOneShotInCall(
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        isFalse,
      );
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          SoundManager.allowsOneShotInCall(platform: platform, isWeb: false),
          isTrue,
          reason: '$platform has no shared session to break',
        );
      }
      // A browser on an iPhone reports iOS but plays through the web backend.
      expect(
        SoundManager.allowsOneShotInCall(
          platform: TargetPlatform.iOS,
          isWeb: true,
        ),
        isTrue,
      );
    });

    test('setVoiceSessionActive is plain, readable state', () {
      expect(soundManager.voiceSessionActive, isFalse);
      soundManager.setVoiceSessionActive(true);
      expect(soundManager.voiceSessionActive, isTrue);
      soundManager.setVoiceSessionActive(false);
      expect(soundManager.voiceSessionActive, isFalse);
    });

    test(
      'play and the ringtone stay no-ops while silent, in-call too',
      () async {
        soundManager.enabled = true;
        soundManager.volume = 1.0;
        soundManager.setVoiceSessionActive(true);
        await expectLater(soundManager.play('mute'), completes);
        await expectLater(
          soundManager.startRingtone(outgoing: true),
          completes,
        );
        await expectLater(soundManager.stopRingtone(), completes);
      },
    );

    test('Android context never takes audio focus, leaves globals alone', () {
      final context = SoundManager.audioContextFor(TargetPlatform.android)!;
      expect(context.android.audioFocus, AndroidAudioFocus.none);
      // These two are written straight to AudioManager when applied; keeping
      // the plugin defaults means the startup-time write is a no-op and the
      // call's MODE_IN_COMMUNICATION is never touched.
      expect(context.android.audioMode, AndroidAudioMode.normal);
      expect(context.android.isSpeakerphoneOn, isFalse);
      // Volume/routing semantics unchanged from the plugin default.
      expect(context.android.usageType, AndroidUsageType.media);
    });

    test('iOS context keeps playback but mixes with other audio', () {
      final context = SoundManager.audioContextFor(TargetPlatform.iOS)!;
      expect(context.iOS.category, AVAudioSessionCategory.playback);
      expect(
        context.iOS.options,
        contains(AVAudioSessionOptions.mixWithOthers),
      );
    });

    test('desktop has no audio context to configure', () {
      expect(SoundManager.audioContextFor(TargetPlatform.linux), isNull);
      expect(SoundManager.audioContextFor(TargetPlatform.macOS), isNull);
      expect(SoundManager.audioContextFor(TargetPlatform.windows), isNull);
    });
  });
}
