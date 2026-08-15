/// Protocol-seam coverage: accordkit's REST and gateway layers against a real
/// accordserver. These are the assertions that mocks cannot make — that our
/// request shapes, response parsing, and event names actually match what the
/// server sends.
///
/// See `integration/README.md` for how to run.
library;

import 'package:accordkit/accordkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

Future<void> main() async {
  final harness = await IntegrationHarness.resolve();

  group('accordkit ↔ accordserver', () {
    late TestAccount alice;
    late TestAccount bob;
    late String spaceId;
    late String channelId;

    setUpAll(() async {
      // Gateways are opened last, once both accounts are members: the server
      // snapshots a session's spaces at IDENTIFY (see [connectGateway]).
      alice = await harness.newAccount('alice', connect: false);
      bob = await harness.newAccount('bob', connect: false);

      final space = await alice.client.spaces.create({
        'name': 'Integration Space',
        'public': true,
      });
      expect(space.ok, isTrue, reason: 'space create failed: ${space.error}');
      spaceId = (space.data! as AccordSpace).id;

      final channel = await alice.client.spaces.createChannel(spaceId, {
        'name': 'general',
        'type': 'text',
      });
      expect(channel.ok, isTrue,
          reason: 'channel create failed: ${channel.error}');
      channelId = (channel.data! as AccordChannel).id;

      final joined = await bob.client.spaces.join(spaceId);
      expect(joined.ok, isTrue, reason: 'bob could not join: ${joined.error}');

      await harness.connectGateway(alice);
      await harness.connectGateway(bob);
    });

    tearDownAll(harness.dispose);

    group('auth', () {
      test('a registered account can log in again with its credentials',
          () async {
        final result = await alice.client.auth.login({
          'username': alice.username,
          'password': alice.password,
        });

        expect(result.ok, isTrue, reason: '${result.error}');
        final data = result.data! as Map<String, dynamic>;
        expect(data['token'], isA<String>());
        expect((data['user']! as AccordUser).id, alice.userId);
      });

      test('a bad password is rejected without a token', () async {
        final result = await alice.client.auth.login({
          'username': alice.username,
          'password': 'not-the-password',
        });

        expect(result.ok, isFalse);
        expect(result.statusCode, anyOf(400, 401, 403));
      });
    });

    group('spaces and channels', () {
      test('a created space round-trips through fetch', () async {
        final result = await alice.client.spaces.fetch(spaceId);

        expect(result.ok, isTrue, reason: '${result.error}');
        final space = result.data! as AccordSpace;
        expect(space.id, spaceId);
        expect(space.name, 'Integration Space');
      });

      test('the channel list contains the created channel', () async {
        final result = await alice.client.spaces.listChannels(spaceId);

        expect(result.ok, isTrue, reason: '${result.error}');
        final channels = (result.data! as List).cast<AccordChannel>();
        final general = channels.firstWhere((c) => c.id == channelId);
        expect(general.name, 'general');
        expect(general.type, 'text');
        expect(general.spaceId, spaceId);
      });

      test('a joined member appears in the space member list', () async {
        final result = await alice.client.members.list(spaceId);

        expect(result.ok, isTrue, reason: '${result.error}');
        final members = (result.data! as List).cast<AccordMember>();
        expect(
          members.map((m) => m.user?.id ?? m.userId),
          contains(bob.userId),
        );
      });
    });

    group('messages', () {
      test('create, list, edit, and delete round-trip', () async {
        final created = await alice.client.messages.create(channelId, {
          'content': 'hello from the integration suite',
        });
        expect(created.ok, isTrue, reason: '${created.error}');
        final message = created.data! as AccordMessage;
        expect(message.content, 'hello from the integration suite');
        expect(message.authorId, alice.userId);
        expect(message.channelId, channelId);

        final listed = await alice.client.messages.list(channelId);
        expect(listed.ok, isTrue, reason: '${listed.error}');
        expect(
          (listed.data! as List).cast<AccordMessage>().map((m) => m.id),
          contains(message.id),
        );

        final edited = await alice.client.messages.edit(
          channelId,
          message.id,
          {'content': 'edited by the integration suite'},
        );
        expect(edited.ok, isTrue, reason: '${edited.error}');
        expect((edited.data! as AccordMessage).content,
            'edited by the integration suite');

        final deleted =
            await alice.client.messages.delete(channelId, message.id);
        expect(deleted.ok, isTrue, reason: '${deleted.error}');

        final after = await alice.client.messages.list(channelId);
        expect(
          (after.data! as List).cast<AccordMessage>().map((m) => m.id),
          isNot(contains(message.id)),
        );
      });
    });

    group('gateway fan-out', () {
      test("alice's message reaches bob's onMessageCreate", () async {
        const content = 'fan-out probe';
        final received = waitForEvent<AccordMessage>(
          bob.client.onMessageCreate,
          (m) => m.content == content,
          description: 'message.create',
        );

        final created =
            await alice.client.messages.create(channelId, {'content': content});
        expect(created.ok, isTrue, reason: '${created.error}');

        final event = await received;
        expect(event.channelId, channelId);
        expect(event.authorId, alice.userId);
        expect(event.id, (created.data! as AccordMessage).id);
      });

      test('an edit reaches bob as onMessageUpdate', () async {
        final created = await alice.client.messages
            .create(channelId, {'content': 'before edit'});
        final id = (created.data! as AccordMessage).id;

        final received = waitForEvent<AccordMessage>(
          bob.client.onMessageUpdate,
          (m) => m.id == id,
          description: 'message.update',
        );

        await alice.client.messages
            .edit(channelId, id, {'content': 'after edit'});

        expect((await received).content, 'after edit');
      });

      test('a delete reaches bob as onMessageDelete', () async {
        final created = await alice.client.messages
            .create(channelId, {'content': 'to be deleted'});
        final id = (created.data! as AccordMessage).id;

        final received = waitForEvent<Map<String, dynamic>>(
          bob.client.onMessageDelete,
          (e) => e['id']?.toString() == id,
          description: 'message.delete',
        );

        await alice.client.messages.delete(channelId, id);
        await received;
      });

      test('typing from alice reaches bob as onTypingStart', () async {
        final received = waitForEvent<Map<String, dynamic>>(
          bob.client.onTypingStart,
          (e) => e['user_id']?.toString() == alice.userId,
          description: 'typing.start',
        );

        await alice.client.messages.typing(channelId);

        expect((await received)['channel_id']?.toString(), channelId);
      });

      test('a new channel reaches bob as onChannelCreate', () async {
        final received = waitForEvent<AccordChannel>(
          bob.client.onChannelCreate,
          (c) => c.name == 'fan-out-channel',
          description: 'channel.create',
        );

        final created = await alice.client.spaces.createChannel(spaceId, {
          'name': 'fan-out-channel',
          'type': 'text',
        });
        expect(created.ok, isTrue, reason: '${created.error}');

        expect((await received).spaceId, spaceId);
      });
    });
    group('membership changes mid-session', () {
      // Regression test for #218: the server used to snapshot a session's
      // space memberships at IDENTIFY and never refresh them, so a space
      // joined while connected fanned out nothing until the gateway
      // reconnected. Fixed server-side in accordserver#55, shipped in
      // accordserver v0.1.31.
      //
      // This needs a server at or past that version. If it fails with a
      // timeout waiting for message.create, check the server image is current
      // before suspecting the client.
      test('a space joined after connecting still receives messages', () async {
        final carol = await harness.newAccount('carol');
        final joined = await carol.client.spaces.join(spaceId);
        expect(joined.ok, isTrue, reason: '${joined.error}');

        const content = 'sent after carol joined';
        final received = waitForEvent<AccordMessage>(
          carol.client.onMessageCreate,
          (m) => m.content == content,
          description: 'message.create after mid-session join',
        );

        await alice.client.messages.create(channelId, {'content': content});

        expect((await received).channelId, channelId);
      });
    });
  }, skip: harness.skipReason);
}
