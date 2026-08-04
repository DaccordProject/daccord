import 'package:bonfire/features/voice/services/voice_session.dart'
    show VoiceSessionState;
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('voiceGain', () {
    test('100% is unity, 0% is silent, 200% is double', () {
      expect(voiceGain(100), 1.0);
      expect(voiceGain(0), 0.0);
      expect(voiceGain(200), 2.0);
      expect(voiceGain(50), 0.5);
    });

    test('clamps out-of-range input to 0.0–2.0', () {
      expect(voiceGain(300), 2.0);
      expect(voiceGain(-50), 0.0);
    });
  });

  group('normalizeDeviceId', () {
    test('empty / null becomes null (system default)', () {
      expect(normalizeDeviceId(null), isNull);
      expect(normalizeDeviceId(''), isNull);
    });

    test('a real id passes through', () {
      expect(normalizeDeviceId('mic-1'), 'mic-1');
    });
  });

  group('isUnintentionalDisconnect', () {
    test(
      'unintentional only when neither intentional nor client-initiated',
      () {
        expect(
          isUnintentionalDisconnect(intentional: false, clientInitiated: false),
          isTrue,
        );
      },
    );

    test('intentional teardown is never unintentional', () {
      expect(
        isUnintentionalDisconnect(intentional: true, clientInitiated: false),
        isFalse,
      );
    });

    test('client-initiated leave is never unintentional', () {
      expect(
        isUnintentionalDisconnect(intentional: false, clientInitiated: true),
        isFalse,
      );
    });
  });

  group('shouldAutoReconnect', () {
    test('reconnects on an unintentional drop while connected, once', () {
      expect(
        shouldAutoReconnect(
          intentional: false,
          stillConnected: true,
          alreadyAttempted: false,
        ),
        isTrue,
      );
    });

    test('does not reconnect when the drop was intentional', () {
      expect(
        shouldAutoReconnect(
          intentional: true,
          stillConnected: true,
          alreadyAttempted: false,
        ),
        isFalse,
      );
    });

    test('does not reconnect twice for the same drop', () {
      expect(
        shouldAutoReconnect(
          intentional: false,
          stillConnected: true,
          alreadyAttempted: true,
        ),
        isFalse,
      );
    });

    test('does not reconnect when no longer connected', () {
      expect(
        shouldAutoReconnect(
          intentional: false,
          stillConnected: false,
          alreadyAttempted: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldEmitStateChange', () {
    test('fires only on an actual change', () {
      expect(
        shouldEmitStateChange(
          VoiceSessionState.connecting,
          VoiceSessionState.connected,
        ),
        isTrue,
      );
      expect(
        shouldEmitStateChange(
          VoiceSessionState.connected,
          VoiceSessionState.connected,
        ),
        isFalse,
      );
    });
  });

  group('needsReconnect', () {
    test('true for dropped/failed/reconnecting, false for healthy', () {
      expect(needsReconnect(VoiceSessionState.disconnected), isTrue);
      expect(needsReconnect(VoiceSessionState.failed), isTrue);
      expect(needsReconnect(VoiceSessionState.reconnecting), isTrue);
      expect(needsReconnect(VoiceSessionState.connected), isFalse);
      expect(needsReconnect(VoiceSessionState.connecting), isFalse);
    });
  });

  group('isVoiceDoubleTap', () {
    final now = DateTime(2026, 1, 1, 12);

    test('a first click on a row is never a join', () {
      expect(isVoiceDoubleTap(null, now), isFalse);
    });

    test('a second click inside the window joins', () {
      expect(
        isVoiceDoubleTap(now.subtract(const Duration(milliseconds: 150)), now),
        isTrue,
      );
      expect(isVoiceDoubleTap(now.subtract(voiceDoubleTapWindow), now), isTrue);
    });

    test('a slow second click only re-selects', () {
      expect(
        isVoiceDoubleTap(
          now.subtract(voiceDoubleTapWindow + const Duration(milliseconds: 1)),
          now,
        ),
        isFalse,
      );
      expect(
        isVoiceDoubleTap(now.subtract(const Duration(seconds: 5)), now),
        isFalse,
      );
    });

    test('ignores a clock that jumped backwards', () {
      expect(
        isVoiceDoubleTap(now.add(const Duration(milliseconds: 100)), now),
        isFalse,
      );
    });
  });
}
