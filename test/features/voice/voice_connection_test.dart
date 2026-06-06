import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/services/voice_session.dart'
    show VoiceSessionState;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default connection is disconnected', () {
    const v = VoiceConnection();
    expect(v.isConnected, isFalse);
    expect(v.sessionState, VoiceSessionState.disconnected);
    expect(v.speakingUserIds, isEmpty);
  });

  test('isConnected tracks channelId', () {
    expect(const VoiceConnection(channelId: 'c1').isConnected, isTrue);
  });

  test('copyWith updates only the given fields', () {
    const v = VoiceConnection(channelId: 'c1', selfMute: false);
    final muted = v.copyWith(selfMute: true);
    expect(muted.selfMute, isTrue);
    expect(muted.channelId, 'c1'); // unchanged
    expect(muted.selfDeaf, isFalse);
  });

  test('clearError wins over a passed error and resets to null', () {
    const v = VoiceConnection(error: 'boom');
    expect(v.copyWith(clearError: true).error, isNull);
    expect(v.copyWith(error: 'again').error, 'again');
  });

  test('tick and speaking set carry through copyWith', () {
    const v = VoiceConnection();
    final next = v.copyWith(tick: 3, speakingUserIds: {'u1', 'u2'});
    expect(next.tick, 3);
    expect(next.speakingUserIds, {'u1', 'u2'});
  });
}
