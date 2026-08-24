/// Opt-in two-process voice test against a real digest-pinned LiveKit SFU
/// (#226). Kept separate from the cheap voice-state scenario because this
/// requires Docker host networking, UDP, a Linux release bundle, xvfb, and
/// usable PulseAudio input/output devices.
library;

import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration/support/accord_test_server.dart';
import 'support/app_instance.dart';

Future<void> main() async {
  final requested = AccordTestServer.liveKitRequested;
  final fleet = requested ? await AppFleet.resolve() : null;
  final skipReason = !requested
      ? 'Set ACCORD_TEST_LIVEKIT=1 to run the real-SFU voice fixture.'
      : fleet!.skipReason ??
            (fleet.harness.server.managesLiveKit
                ? null
                : 'The real-SFU test requires the fixture to manage LiveKit; '
                      'ACCORD_TEST_SERVER_URL cannot provide restart/room '
                      'observables. Unset it and use Docker or a local binary.');
  if (requested && skipReason != null) await fleet?.dispose();

  group('real LiveKit voice session', () {
    late AppInstance alice;
    late AppInstance bob;
    late String spaceId;
    late String voiceChannelId;

    setUpAll(() async {
      final aliceAccount = await fleet!.harness.newAccount('alice');
      final bobAccount = await fleet.harness.newAccount('bob');

      final space = await aliceAccount.client.spaces.create({
        'name': 'LiveKit Fixture Space',
        'public': true,
      });
      expect(space.ok, isTrue, reason: '${space.error}');
      spaceId = (space.data! as AccordSpace).id;

      final voice = await aliceAccount.client.spaces.createChannel(spaceId, {
        'name': 'Real SFU',
        'type': 'voice',
      });
      expect(voice.ok, isTrue, reason: '${voice.error}');
      voiceChannelId = (voice.data! as AccordChannel).id;

      final joined = await bobAccount.client.spaces.join(spaceId);
      expect(joined.ok, isTrue, reason: '${joined.error}');

      alice = await fleet.spawn('alice-livekit', account: aliceAccount);
      bob = await fleet.spawn('bob-livekit', account: bobAccount);
    });

    tearDownAll(() async => fleet?.dispose());

    test(
      'join, media flags, reconnect, and teardown use the real room',
      () async {
        final activeFleet = fleet!;
        for (final client in [alice, bob]) {
          await _prepareVoiceChannel(client, spaceId, voiceChannelId);
        }
        await alice.call('join_voice_channel', {'channel_id': voiceChannelId});
        await _waitForConnected(
          alice,
          voiceChannelId,
          activeFleet.harness.server,
        );

        final roomName = 'channel_$voiceChannelId';
        await _waitUntil(
          () => activeFleet.harness.server.liveKitRoomExists(roomName),
          description: 'LiveKit room $roomName to exist',
        );

        await bob.call('join_voice_channel', {'channel_id': voiceChannelId});
        await _waitForConnected(
          bob,
          voiceChannelId,
          activeFleet.harness.server,
        );

        for (final (client, remoteId) in [
          (alice, bob.account.userId),
          (bob, alice.account.userId),
        ]) {
          await client.callUntil(
            'get_current_state',
            (state) =>
                (state['voice_livekit_remote_identities'] as List).contains(
                  remoteId,
                ) &&
                (state['voice_livekit_remote_audio_tracks'] as num) > 0,
            timeout: const Duration(seconds: 45),
            description: 'the remote LiveKit participant and microphone track',
          );
        }

        // Mute must affect the published LiveKit microphone as well as the
        // Accord gateway state seen by the peer.
        await alice.call('toggle_mute');
        await alice.callUntil(
          'get_current_state',
          (state) =>
              state['voice_self_mute'] == true &&
              state['voice_livekit_microphone_enabled'] == false,
          description: 'the local LiveKit microphone to be muted',
        );
        await bob.callUntil(
          'get_current_state',
          (state) => (state['voice_livekit_remote_muted_identities'] as List)
              .contains(alice.account.userId),
          description: "alice's LiveKit publication to be muted",
        );
        await _waitForPeerVoiceFlag(
          bob,
          voiceChannelId,
          alice.account.userId,
          'self_mute',
          true,
        );

        await alice.call('toggle_mute');
        await alice.callUntil(
          'get_current_state',
          (state) => state['voice_livekit_microphone_enabled'] == true,
          description: 'the local LiveKit microphone to be restored',
        );

        // Deafen is implemented as disabling the real remote audio
        // publications. It is not inferred from the gateway self_deaf bit.
        await alice.callUntil(
          'get_current_state',
          (state) => (state['voice_livekit_remote_audio_enabled'] as num) > 0,
          description: "bob's remote audio publication to be enabled",
        );
        await alice.call('toggle_deafen');
        await alice.callUntil(
          'get_current_state',
          (state) =>
              state['voice_self_deaf'] == true &&
              (state['voice_livekit_remote_audio_tracks'] as num) > 0 &&
              state['voice_livekit_remote_audio_enabled'] == 0,
          description: 'all remote LiveKit audio to be disabled while deafened',
        );
        await _waitForPeerVoiceFlag(
          bob,
          voiceChannelId,
          alice.account.userId,
          'self_deaf',
          true,
        );
        await alice.call('toggle_deafen');
        await alice.callUntil(
          'get_current_state',
          (state) => (state['voice_livekit_remote_audio_enabled'] as num) > 0,
          description: 'remote LiveKit audio to be restored after undeafen',
        );

        // Briefly interrupt the SFU and observe the actual SDK reconnection
        // state before restoring it. Keeping the outage below LiveKit's retry
        // budget verifies that the same Room reconnects instead of replacing
        // this with a leave/new-join assertion.
        await activeFleet.harness.server.stopLiveKit();
        await alice.callUntil(
          'get_current_state',
          (state) => state['voice_session_state'] == 'reconnecting',
          timeout: const Duration(seconds: 30),
          description: 'the interrupted LiveKit session to start reconnecting',
        );
        await activeFleet.harness.server.restartLiveKit();
        await _waitForConnected(
          alice,
          voiceChannelId,
          activeFleet.harness.server,
        );
        await _waitUntil(
          () => activeFleet.harness.server.liveKitRoomExists(roomName),
          description: 'the LiveKit room to be recreated after reconnect',
        );

        await alice.call('leave_voice');
        await bob.call('leave_voice');
        for (final client in [alice, bob]) {
          await client.callUntil(
            'get_current_state',
            (state) =>
                state['voice_channel_id'] == '' &&
                state['voice_session_state'] == 'disconnected' &&
                state['voice_livekit_room_connected'] == false,
            description: 'the LiveKit session to be torn down',
          );
        }
        await _waitUntil(
          () async =>
              !await activeFleet.harness.server.liveKitRoomExists(roomName),
          description: 'accordserver to delete the empty LiveKit room',
        );
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }, skip: skipReason);
}

Future<void> _prepareVoiceChannel(
  AppInstance client,
  String spaceId,
  String channelId,
) async {
  await client.call('select_space', {'space_id': spaceId});
  await client.callUntil(
    'get_current_state',
    (state) => state['space_id'] == spaceId,
    description: 'the voice space to be selected',
  );
  // Selecting a voice channel opens its lobby and loads the server-qualified
  // channel cache; it deliberately does not join media on a single click.
  await client.call('select_channel', {'channel_id': channelId});
  await client.callUntil(
    'get_current_state',
    (state) => state['channel_id'] == channelId,
    description: 'the voice channel lobby to be selected',
  );
}

Future<void> _waitForConnected(
  AppInstance client,
  String channelId,
  AccordTestServer server,
) async {
  try {
    await client.callUntil(
      'get_current_state',
      (state) =>
          state['voice_channel_id'] == channelId &&
          state['voice_session_state'] == 'connected' &&
          state['voice_livekit_room_connected'] == true &&
          state['voice_livekit_local_identity'] == client.account.userId,
      timeout: const Duration(seconds: 60),
      description: 'a connected LiveKit room with the local participant',
    );
  } on TimeoutException catch (error) {
    final liveKitLogs = await server.liveKitLogs();
    throw TimeoutException(
      '$error\n--- ${client.label} output ---\n${client.log}'
      '\n--- LiveKit output ---\n$liveKitLogs',
    );
  }
}

Future<void> _waitForPeerVoiceFlag(
  AppInstance observer,
  String channelId,
  String userId,
  String key,
  bool value,
) async {
  await observer.callUntil(
    'list_voice_states',
    (result) => (result['voice_states'] as List).any(
      (state) => state['user_id'] == userId && state[key] == value,
    ),
    arguments: {'channel_id': channelId},
    description: "$userId's $key=$value gateway state",
  );
}

Future<void> _waitUntil(
  Future<bool> Function() predicate, {
  required String description,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('$description did not complete within $timeout');
}
