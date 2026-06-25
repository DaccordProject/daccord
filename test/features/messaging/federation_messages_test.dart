import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Federation (M3) messaging behaviours that the message cache must preserve:
// remote-homed messages carry qualified IDs, so dedup/update/delete/reactions
// all have to key by the *full* qualified ID — never a bare snowflake that a
// colliding remote ID would alias.

ProviderContainer makeContainer() {
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AccordMessagesController notifier(ProviderContainer c) =>
    c.read(accordMessagesControllerProvider('chan@b.example').notifier);

List<AccordMessage>? messages(ProviderContainer c) =>
    c.read(accordMessagesControllerProvider('chan@b.example'));

AccordMessage _remote({
  String id = 'm1@b.example',
  String author = 'alice@b.example',
  String content = 'hi from b',
}) =>
    AccordMessage(
      id: id,
      channelId: 'chan@b.example',
      authorId: author,
      content: content,
    );

void main() {
  group('remote-homed message parsing (#159)', () {
    test('a qualified author id makes the message remote with a home origin',
        () {
      final m = AccordMessage.fromJson({
        'id': 'm1@b.example',
        'channel_id': 'chan@b.example',
        'author_id': 'alice@b.example',
        'content': 'hi',
      });
      expect(m.isRemote, isTrue);
      // Origin is inferred from the qualified author id when not sent explicitly
      // (the local gateway JSON omits `origin`).
      expect(m.origin, 'b.example');
    });

    test('an explicit origin field wins over the author-id inference', () {
      final m = AccordMessage.fromJson({
        'id': 'm1@b.example',
        'channel_id': 'chan@b.example',
        'author_id': 'alice@b.example',
        'content': 'hi',
        'origin': 'c.example',
      });
      expect(m.origin, 'c.example');
    });

    test('a bare local message is not remote', () {
      final m = AccordMessage.fromJson({
        'id': '1',
        'channel_id': '2',
        'author_id': '3',
        'content': 'hi',
      });
      expect(m.isRemote, isFalse);
      expect(m.origin, isNull);
    });
  });

  group('message cache keys on the qualified id (#159/#160)', () {
    test('addMessage dedups a replica copy by its qualified id', () {
      final c = makeContainer();
      final n = notifier(c);
      n.state = [];

      n.addMessage(_remote());
      n.addMessage(_remote()); // duplicate delivery of the same qualified id

      expect(messages(c)!.length, 1);
    });

    test('a remote id and a colliding local snowflake stay distinct', () {
      final c = makeContainer();
      final n = notifier(c);
      n.state = [];

      n.addMessage(_remote(id: '5@b.example', author: 'x@b.example'));
      n.addMessage(_remote(id: '5', author: 'y')); // same bare snowflake, local

      expect(messages(c)!.length, 2,
          reason: 'qualified id must not alias a bare snowflake');
    });

    test('updateMessage applies a remote edit by qualified id', () {
      final c = makeContainer();
      final n = notifier(c);
      n.state = [_remote(content: 'before')];

      n.updateMessage(_remote(content: 'after'));

      expect(messages(c)!.single.content, 'after');
    });

    test('removeMessage deletes a remote message by qualified id', () {
      final c = makeContainer();
      final n = notifier(c);
      n.state = [_remote()];

      n.removeMessage('m1@b.example');

      expect(messages(c), isEmpty);
    });
  });

  group('federated reaction aggregation (#161)', () {
    test('a remote actor increments the count without claiming it as ours', () {
      final c = makeContainer();
      final n = notifier(c);
      n.state = [_remote()];

      // Gateway echo for a remote reactor: the handler computes isOwn=false
      // (the qualified actor id is not us).
      n.applyReaction('m1@b.example', '👍', added: true, isOwn: false);

      final r = messages(c)!.single.reactions!.single;
      expect(r.count, 1);
      expect(r.includesMe, isFalse);
    });

    test('our own reaction echoed back as own merges, not double-counts', () {
      final c = makeContainer();
      final n = notifier(c);
      n.state = [_remote()];

      // Optimistic local add.
      n.applyReaction('m1@b.example', '👍', added: true, isOwn: true);
      // Echo of our own reaction, recognised as self by the handler
      // (isSameUser) → still isOwn=true → the includesMe guard prevents a
      // second increment.
      n.applyReaction('m1@b.example', '👍', added: true, isOwn: true);

      final r = messages(c)!.single.reactions!.single;
      expect(r.count, 1, reason: 'no double count for our own reaction');
      expect(r.includesMe, isTrue);
    });
  });
}
