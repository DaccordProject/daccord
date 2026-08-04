import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/missed_calls.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ringtone that plays nothing, so the signaling transitions can run without
/// the audio plugin (which has no implementation under `flutter test`).
class _SilentRingtone implements CallRingtone {
  @override
  void start({bool outgoing = false}) {}

  @override
  void stop() {}
}

/// A [VoiceController] stand-in: joining/leaving flips `channelId` without
/// touching LiveKit, which is all [CallController] inspects.
class _FakeVoiceController extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection();

  @override
  Future<void> join(String channelId, String? spaceId) async {
    state = VoiceConnection(channelId: channelId);
  }

  @override
  Future<void> leave() async {
    state = const VoiceConnection();
  }
}

AccordCallSignal _ring(String channelId,
        {String caller = 'u2', bool video = false}) =>
    AccordCallSignal(
      type: 'ring',
      channelId: channelId,
      callerId: caller,
      participants: const ['u1', 'u2'],
      metadata: {'video': video},
    );

AccordCallSignal _cancel(String channelId) =>
    AccordCallSignal(type: 'cancel', channelId: channelId, userId: 'u2');

AccordCallSignal _end(String channelId) =>
    AccordCallSignal(type: 'end', channelId: channelId, userId: 'u2');

void main() {
  const me = 'u1';

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        voiceControllerProvider.overrideWith(_FakeVoiceController.new),
        callRingtoneProvider.overrideWithValue(_SilentRingtone()),
      ],
    );
  });

  tearDown(() => container.dispose());

  CallController call() => container.read(callControllerProvider.notifier);
  Map<String, MissedCall> missed() =>
      container.read(missedCallsControllerProvider);

  group('MissedCallsController', () {
    MissedCallsController ctl() =>
        container.read(missedCallsControllerProvider.notifier);

    test('starts empty', () {
      expect(missed(), isEmpty);
    });

    test('records a miss keyed by channel', () {
      ctl().record(
          channelId: 'dm1', callerId: 'u2', serverKey: 'u1@s', video: true);
      final entry = missed()['dm1']!;
      expect(entry.callerId, 'u2');
      expect(entry.serverKey, 'u1@s');
      expect(entry.video, isTrue);
      expect(entry.count, 1);
      expect(entry.label, 'Missed call');
    });

    test('repeat misses on one channel collapse into a counted entry', () {
      ctl().record(channelId: 'dm1', callerId: 'u2');
      ctl().record(channelId: 'dm1', callerId: 'u2');
      ctl().record(channelId: 'dm1', callerId: 'u2');
      expect(missed(), hasLength(1));
      expect(missed()['dm1']!.count, 3);
      expect(missed()['dm1']!.label, 'Missed call (3)');
    });

    test('a bump keeps the earlier caller when the new ring has none', () {
      ctl().record(channelId: 'dm1', callerId: 'u2');
      ctl().record(channelId: 'dm1', callerId: '');
      expect(missed()['dm1']!.callerId, 'u2');
    });

    test('ignores a miss with no channel', () {
      ctl().record(channelId: '', callerId: 'u2');
      expect(missed(), isEmpty);
    });

    test('clear drops one channel, clearAll drops everything', () {
      ctl().record(channelId: 'dm1', callerId: 'u2');
      ctl().record(channelId: 'dm2', callerId: 'u3');
      ctl().clear('dm1');
      expect(missed().keys, ['dm2']);
      ctl().clear('nope'); // no-op
      expect(missed().keys, ['dm2']);
      ctl().clearAll();
      expect(missed(), isEmpty);
    });
  });

  group('CallController missed-call detection', () {
    test('ring then cancel without an accept is a missed call', () {
      call().handleRing(_ring('dm1', video: true), 'u1@s', me);
      expect(container.read(callControllerProvider).incoming, isNotNull);

      call().handleCancelOrEnd(_cancel('dm1'));

      expect(container.read(callControllerProvider).incoming, isNull);
      final entry = missed()['dm1']!;
      expect(entry.callerId, 'u2');
      expect(entry.serverKey, 'u1@s');
      expect(entry.video, isTrue);
      expect(entry.count, 1);
    });

    test('ring then end without an accept is a missed call', () {
      call().handleRing(_ring('dm1'), 'u1@s', me);
      call().handleCancelOrEnd(_end('dm1'));
      expect(missed().keys, ['dm1']);
    });

    test('ring, accept, then end is not missed', () async {
      call().handleRing(_ring('dm1'), 'u1@s', me);
      final joined = await call().acceptIncoming();
      expect(joined, 'dm1');
      expect(container.read(callControllerProvider).incoming, isNull);

      // The call ends later, from the answered state.
      call().handleCancelOrEnd(_end('dm1'));
      expect(missed(), isEmpty);
    });

    test('ring then an explicit decline is not missed', () async {
      call().handleRing(_ring('dm1'), 'u1@s', me);
      await call().declineIncoming();
      expect(container.read(callControllerProvider).incoming, isNull);
      expect(missed(), isEmpty);
    });

    test('a ring that expires client-side is missed', () {
      call().handleRing(_ring('dm1'), 'u1@s', me);
      call().expireRing();
      expect(container.read(callControllerProvider).incoming, isNull);
      expect(missed()['dm1']!.count, 1);
    });

    test('expiring with nothing ringing records nothing', () {
      call().expireRing();
      expect(missed(), isEmpty);
    });

    test('cancel for a channel we are not ringing on records nothing', () {
      call().handleRing(_ring('dm1'), 'u1@s', me);
      call().handleCancelOrEnd(_cancel('dm9'));
      expect(container.read(callControllerProvider).incoming, isNotNull);
      expect(missed(), isEmpty);
    });

    test('our own ring echo is ignored and never counts as missed', () {
      call().handleRing(_ring('dm1', caller: me), 'u1@s', me);
      expect(container.read(callControllerProvider).incoming, isNull);
      call().handleCancelOrEnd(_cancel('dm1'));
      expect(missed(), isEmpty);
    });

    test('a ring displaced by another conversation is missed', () {
      call().handleRing(_ring('dm1'), 'u1@s', me);
      call().handleRing(_ring('dm2', caller: 'u3'), 'u1@s', me);
      expect(container.read(callControllerProvider).incoming!.channelId, 'dm2');
      expect(missed().keys, ['dm1']);

      // The second ring is still live; missing it too logs both.
      call().handleCancelOrEnd(_cancel('dm2'));
      expect(missed().keys, unorderedEquals(['dm1', 'dm2']));
    });

    test('a repeat ring for the ringing channel keeps the one prompt', () {
      call().handleRing(_ring('dm1'), 'u1@s', me);
      call().handleRing(_ring('dm1'), 'u1@s', me);
      expect(missed(), isEmpty);
      call().handleCancelOrEnd(_cancel('dm1'));
      expect(missed()['dm1']!.count, 1);
    });

    test('two missed calls on one channel collapse into a counted entry', () {
      call().handleRing(_ring('dm1'), 'u1@s', me);
      call().handleCancelOrEnd(_cancel('dm1'));
      call().handleRing(_ring('dm1'), 'u1@s', me);
      call().expireRing();
      expect(missed()['dm1']!.count, 2);
      expect(missed()['dm1']!.label, 'Missed call (2)');
    });

    test('answering a later call clears the earlier missed indicator',
        () async {
      call().handleRing(_ring('dm1'), 'u1@s', me);
      call().handleCancelOrEnd(_cancel('dm1'));
      expect(missed().keys, ['dm1']);

      call().handleRing(_ring('dm1'), 'u1@s', me);
      await call().acceptIncoming();
      expect(missed(), isEmpty);
    });

    test('a ring for the call we are already in is ignored', () async {
      // Already connected to dm1's voice: the ring is our own call's echo.
      await container.read(voiceControllerProvider.notifier).join('dm1', null);
      call().handleRing(_ring('dm1'), 'u1@s', me);
      expect(container.read(callControllerProvider).incoming, isNull);
      call().handleCancelOrEnd(_cancel('dm1'));
      expect(missed(), isEmpty);
    });
  });
}
