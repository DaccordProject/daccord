/// Controller-seam coverage: the app's own Riverpod caches and gateway event
/// handler, driven by real server traffic.
///
/// Where `accordkit_protocol_test.dart` asserts that the SDK and the server
/// agree, this asserts that *the client* reacts correctly — that a gateway
/// event actually lands in the cache a screen reads from. That wiring
/// (`handleAccordEvents` → `accordMessagesControllerProvider`) is where the
/// stale-UI class of bug lives, and no widget test covers it.
library;

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

Future<void> main() async {
  final harness = await IntegrationHarness.resolve();

  group('message cache ← gateway', () {
    late TestAccount alice;
    late TestAccount bob;
    late ProviderContainer container;
    late String spaceId;
    late String channelId;

    setUpAll(() async {
      await harness.setupHive();

      // Gateways open last, once both accounts are members — see
      // [IntegrationHarness.connectGateway].
      alice = await harness.newAccount('alice', connect: false);
      bob = await harness.newAccount('bob', connect: false);

      final space = await alice.client.spaces.create({
        'name': 'Cache Space',
        'public': true,
      });
      spaceId = (space.data! as AccordSpace).id;

      final channel = await alice.client.spaces.createChannel(spaceId, {
        'name': 'general',
        'type': 'text',
      });
      channelId = (channel.data! as AccordChannel).id;

      final joined = await bob.client.spaces.join(spaceId);
      expect(joined.ok, isTrue, reason: 'bob could not join: ${joined.error}');

      await harness.connectGateway(alice);
      await harness.connectGateway(bob);

      // Alice's session, with the real gateway event handler attached.
      container = harness.containerFor(alice);

      // Keeping a listener open is what marks the channel active — the handler
      // only writes to channels the UI is actually showing (see
      // `activeMessageChannels`), so without this the cache never updates.
      container.listen(
        accordMessagesControllerProvider('', channelId),
        (_, _) {},
        fireImmediately: true,
      );
    });

    tearDownAll(harness.dispose);

    List<AccordMessage>? read() =>
        container.read(accordMessagesControllerProvider('', channelId));

    test('the controller loads channel history from the server', () async {
      final created = await alice.client.messages
          .create(channelId, {'content': 'seeded history'});
      expect(created.ok, isTrue, reason: '${created.error}');

      await container
          .read(accordMessagesControllerProvider('', channelId).notifier)
          .reload(alice.client);

      final messages = await waitForState(
        read,
        (m) => m != null && m.any((msg) => msg.content == 'seeded history'),
        description: 'message history',
      );
      expect(messages, isNotNull);
    });

    test("bob's message lands in alice's cache without a refetch", () async {
      const content = 'sent by bob over the gateway';

      final created =
          await bob.client.messages.create(channelId, {'content': content});
      expect(created.ok, isTrue, reason: '${created.error}');

      final messages = await waitForState(
        read,
        (m) => m != null && m.any((msg) => msg.content == content),
        description: 'gateway-delivered message',
      );

      final delivered = messages!.firstWhere((m) => m.content == content);
      expect(delivered.authorId, bob.userId);
      expect(delivered.channelId, channelId);
    });

    test("an edit by bob updates the message already in alice's cache",
        () async {
      final created = await bob.client.messages
          .create(channelId, {'content': 'bob before edit'});
      final id = (created.data! as AccordMessage).id;

      await waitForState(
        read,
        (m) => m != null && m.any((msg) => msg.id == id),
        description: 'message to edit',
      );

      await bob.client.messages
          .edit(channelId, id, {'content': 'bob after edit'});

      await waitForState(
        read,
        (m) =>
            m != null &&
            m.any((msg) => msg.id == id && msg.content == 'bob after edit'),
        description: 'edited message',
      );
    });

    test("a delete by bob removes the message from alice's cache", () async {
      final created = await bob.client.messages
          .create(channelId, {'content': 'bob will delete this'});
      final id = (created.data! as AccordMessage).id;

      await waitForState(
        read,
        (m) => m != null && m.any((msg) => msg.id == id),
        description: 'message to delete',
      );

      await bob.client.messages.delete(channelId, id);

      await waitForState(
        read,
        (m) => m != null && m.every((msg) => msg.id != id),
        description: 'deleted message',
      );
    });
  }, skip: harness.skipReason);
}
