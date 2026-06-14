import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const incoming = IncomingCall(
    channelId: 'dm1',
    callerId: 'u2',
    serverKey: 'u1@s',
    participants: ['u1', 'u2'],
    video: true,
  );

  group('CallState.copyWith', () {
    test('carries forward unspecified fields', () {
      const state = CallState(incoming: incoming, outgoingChannelId: 'dm9');
      final next = state.copyWith(endedMessage: 'Call declined');
      expect(next.incoming, same(incoming));
      expect(next.outgoingChannelId, 'dm9');
      expect(next.endedMessage, 'Call declined');
    });

    test('clearIncoming wins over a passed incoming', () {
      const state = CallState(incoming: incoming);
      final next = state.copyWith(incoming: incoming, clearIncoming: true);
      expect(next.incoming, isNull);
    });

    test('clearOutgoing clears the ringing channel', () {
      const state = CallState(outgoingChannelId: 'dm1');
      expect(state.hasOutgoing, isTrue);
      final next = state.copyWith(clearOutgoing: true);
      expect(next.outgoingChannelId, isNull);
      expect(next.hasOutgoing, isFalse);
    });

    test('clearEnded drops the transient banner', () {
      const state = CallState(endedMessage: 'Call declined');
      expect(state.copyWith(clearEnded: true).endedMessage, isNull);
    });

    test('clear flags do not disturb the other fields', () {
      const state = CallState(
        incoming: incoming,
        outgoingChannelId: 'dm9',
        endedMessage: 'x',
      );
      final next = state.copyWith(clearIncoming: true);
      expect(next.incoming, isNull);
      expect(next.outgoingChannelId, 'dm9');
      expect(next.endedMessage, 'x');
    });
  });
}
