/// Two real app processes, one server, both sides of every interaction
/// asserted (#222).
///
/// Layers 1 and 2 both run inside a single process, so they can only ever
/// check what one client believes. These launch two actual clients and drive
/// them through the MCP surface the app already exposes, which is the only way
/// to assert that what A did is what B sees.
///
/// See `multi_instance/README.md`.
library;

import 'package:accordkit/accordkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_instance.dart';

Future<void> main() async {
  // Always runs, unlike the rest of this file: no fleet, no display, no
  // server. `list_members` flattens the member onto the user, unlike the
  // REST shape which nests it under `user_id` — this is the one piece of
  // parsing logic in the suite worth covering directly.
  group('_memberId', () {
    test('flattened id (the shape list_members actually returns)', () {
      expect(_memberId({'id': 'u1', 'username': 'alice'}), 'u1');
    });

    test('nested user.id (REST shape, kept for resilience)', () {
      expect(
        _memberId({
          'user_id': 'u1',
          'user': {'id': 'u1', 'username': 'alice'},
        }),
        'u1',
      );
    });

    test('user_id fallback with no nested user object', () {
      expect(_memberId({'user_id': 'u1'}), 'u1');
    });

    test('not a map', () {
      expect(_memberId('u1'), isNull);
      expect(_memberId(null), isNull);
    });
  });

  final fleet = await AppFleet.resolve();

  group('two clients', () {
    late AppInstance alice;
    late AppInstance bob;
    late String spaceId;
    late String channelId;

    setUpAll(() async {
      // Accounts and the space are set up over REST first: an app instance
      // that starts before its user is a member would come up with an empty
      // rail, and the point here is to drive UI state, not to test joining.
      final aliceAccount = await fleet.harness.newAccount('alice');
      final bobAccount = await fleet.harness.newAccount('bob');

      final space = await aliceAccount.client.spaces.create({
        'name': 'Fleet Space',
        'public': true,
      });
      expect(space.ok, isTrue, reason: '${space.error}');
      spaceId = (space.data! as AccordSpace).id;

      final channels = await aliceAccount.client.spaces.listChannels(spaceId);
      channelId = (channels.data! as List)
          .cast<AccordChannel>()
          .firstWhere((c) => c.type == 'text')
          .id;

      final joined = await bobAccount.client.spaces.join(spaceId);
      expect(joined.ok, isTrue, reason: '${joined.error}');

      alice = await fleet.spawn('alice', account: aliceAccount);
      bob = await fleet.spawn('bob', account: bobAccount);
    });

    tearDownAll(fleet.dispose);

    /// Opens the shared channel on [client].
    ///
    /// `select_channel` resolves the id against the *selected space's* channel
    /// list, so selecting the space first isn't optional — without it the tool
    /// answers "Channel not found" for a channel that plainly exists.
    Future<void> openChannel(AppInstance client) async {
      await client.call('select_space', {'space_id': spaceId});
      await client.callUntil(
        'get_current_state',
        (r) => r['space_id'] == spaceId,
        description: 'the space to be selected',
      );
      await client.call('select_channel', {'channel_id': channelId});
      await client.callUntil(
        'get_current_state',
        (r) => r['channel_id'] == channelId,
        description: 'the channel to be selected',
      );
    }

    test('both clients come up signed in and see the space', () async {
      for (final client in [alice, bob]) {
        final spaces = await client.callUntil(
          'list_spaces',
          (r) => (r['spaces'] as List?)?.any((s) => s['id'] == spaceId) ?? false,
          description: 'the shared space in list_spaces',
        );
        expect(spaces['ok'], isTrue);
      }
    }, timeout: _generous);

    test('navigation moves the real UI, and the client reports it', () async {
      await openChannel(alice);

      final state = await alice.call('get_current_state');
      expect(state['channel_id'], channelId);
      expect(state['space_id'], spaceId);
    }, timeout: _generous);

    test("a message alice sends arrives in bob's client", () async {
      await openChannel(alice);
      await openChannel(bob);

      const content = 'sent from one app process to another';
      await alice.call('send_message', {
        'channel_id': channelId,
        'content': content,
      });

      // Nothing in bob's process refetched — this arrives over his own
      // gateway connection, into his own cache, in his own process.
      final messages = await bob.callUntil(
        'list_messages',
        (r) => (r['messages'] as List?)
                ?.any((m) => m['content'] == content) ??
            false,
        arguments: {'channel_id': channelId, 'limit': 20},
        description: "alice's message in bob's list_messages",
      );

      final delivered = (messages['messages'] as List)
          .firstWhere((m) => m['content'] == content) as Map;
      expect(delivered['author_id'], alice.account.userId);
    }, timeout: _generous);

    test("a message bob sends arrives in alice's client", () async {
      const content = 'and back the other way';
      await bob.call('send_message', {
        'channel_id': channelId,
        'content': content,
      });

      await alice.callUntil(
        'list_messages',
        (r) => (r['messages'] as List?)
                ?.any((m) => m['content'] == content) ??
            false,
        arguments: {'channel_id': channelId, 'limit': 20},
        description: "bob's message in alice's list_messages",
      );
    }, timeout: _generous);

    test('each client sees the other in the member list', () async {
      final fromAlice = await alice.callUntil(
        'list_members',
        (r) => (r['members'] as List?)
                ?.any((m) => _memberId(m) == bob.account.userId) ??
            false,
        arguments: {'space_id': spaceId},
        description: 'bob in alice\'s member list',
      );
      expect(fromAlice['ok'], isTrue);

      await bob.callUntil(
        'list_members',
        (r) => (r['members'] as List?)
                ?.any((m) => _memberId(m) == alice.account.userId) ??
            false,
        arguments: {'space_id': spaceId},
        description: 'alice in bob\'s member list',
      );
    }, timeout: _generous);

    test('an edit by alice reaches bob, and so does a delete', () async {
      // Self-contained rather than relying on an earlier test having left the
      // channel selected: tests within a group run in declaration order, but
      // nothing here should depend on that order being preserved.
      await openChannel(alice);
      await openChannel(bob);

      const original = 'before the edit';
      const edited = 'after the edit';

      await alice.call('send_message', {
        'channel_id': channelId,
        'content': original,
      });

      final seen = await bob.callUntil(
        'list_messages',
        (r) => (r['messages'] as List?)
                ?.any((m) => m['content'] == original) ??
            false,
        arguments: {'channel_id': channelId, 'limit': 20},
        description: 'the original message in bob\'s client',
      );
      final messageId = ((seen['messages'] as List)
          .firstWhere((m) => m['content'] == original) as Map)['id'] as String;

      await alice.call('edit_message', {
        'message_id': messageId,
        'content': edited,
      });
      await bob.callUntil(
        'list_messages',
        (r) => (r['messages'] as List?)?.any(
              (m) => m['id'] == messageId && m['content'] == edited,
            ) ??
            false,
        arguments: {'channel_id': channelId, 'limit': 20},
        description: 'the edit in bob\'s client',
      );

      await alice.call('delete_message', {'message_id': messageId});
      await bob.callUntil(
        'list_messages',
        (r) =>
            (r['messages'] as List?)?.every((m) => m['id'] != messageId) ??
            false,
        arguments: {'channel_id': channelId, 'limit': 20},
        description: 'the delete in bob\'s client',
      );
    }, timeout: _generous);
  }, skip: fleet.skipReason);
}

/// Cross-process assertions poll two app processes over the gateway, which the
/// 30-second default doesn't comfortably cover.
const _generous = Timeout(Duration(minutes: 3));

/// The user a member entry refers to.
///
/// `list_members` flattens the member onto the user (`id`, `username`,
/// `display_name`, `roles`), unlike the REST shape which nests a `user` object
/// under `user_id`. Both are accepted so this keeps working if the tool is
/// ever changed to match REST.
String? _memberId(Object? member) {
  if (member is! Map) return null;
  final id = member['id'];
  if (id != null) return id.toString();
  final user = member['user'];
  if (user is Map && user['id'] != null) return user['id'].toString();
  return member['user_id']?.toString();
}
