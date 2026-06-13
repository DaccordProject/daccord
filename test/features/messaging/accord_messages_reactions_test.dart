import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer makeContainer() {
  final container = ProviderContainer(
    overrides: [
      // Prevents AccordAuth.build from touching Hive or opening a gateway.
      accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AccordMessagesController notifier(ProviderContainer c) =>
    c.read(accordMessagesControllerProvider('ch1').notifier);

List<AccordMessage>? messages(ProviderContainer c) =>
    c.read(accordMessagesControllerProvider('ch1'));

AccordMessage _msg({List<AccordReaction>? reactions}) => AccordMessage(
      id: 'm1',
      channelId: 'ch1',
      content: 'hi',
      reactions: reactions,
    );

AccordReaction _reaction(String name, {String? id, int count = 1, bool me = false}) =>
    AccordReaction(emoji: {'name': name, 'id': id}, count: count, includesMe: me);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('applyReaction — unicode emoji dedup', () {
    test('shortcode-keyed optimistic pill and glyph-keyed echo collapse to one',
        () {
      final c = makeContainer();
      final n = notifier(c);

      // Seed the message with no reactions.
      n.state = [_msg()];

      // 1. Optimistic add from picker: the picker passes a shortcode.
      n.applyReaction('m1', 'hamburger', added: true, isOwn: true);

      var reactions = messages(c)!.first.reactions!;
      expect(reactions.length, 1,
          reason: 'one pill after optimistic add');
      // The stored name must be the canonical glyph.
      expect(reactions.first.emoji['name'], '🍔');
      expect(reactions.first.count, 1);
      expect(reactions.first.includesMe, isTrue);

      // 2. Gateway echo arrives with the glyph — must update, not add.
      n.applyReaction('m1', '🍔', added: true, isOwn: true);

      reactions = messages(c)!.first.reactions!;
      expect(reactions.length, 1,
          reason: 'gateway echo must merge into the optimistic pill');
      expect(reactions.first.count, 1,
          reason: 'includesMe guard prevents double-count');
    });

    test('glyph-keyed add from existing pill works correctly', () {
      final c = makeContainer();
      final n = notifier(c);

      // Seed with an existing reaction from another user (stored as glyph).
      n.state = [_msg(reactions: [_reaction('🍔', count: 1)])];

      // Current user taps the pill (passes the glyph).
      n.applyReaction('m1', '🍔', added: true, isOwn: true);

      final reactions = messages(c)!.first.reactions!;
      expect(reactions.length, 1);
      expect(reactions.first.count, 2);
      expect(reactions.first.includesMe, isTrue);
    });

    test('REST-loaded shortcode-named reaction matches a glyph toggle', () {
      final c = makeContainer();
      final n = notifier(c);

      // A reaction loaded from REST might still have the shortcode as its name.
      // It's ours (includesMe) so the own-remove guard lets the toggle proceed —
      // the point under test is that the glyph still matches the shortcode pill.
      n.state = [_msg(reactions: [_reaction('hamburger', count: 1, me: true)])];

      // Toggle off via glyph (what toggleReaction builds the token from).
      n.applyReaction('m1', '🍔', added: false, isOwn: true, emojiId: null);

      // Even though stored as 'hamburger', the remove should match.
      final reactions = messages(c)!.first.reactions ?? [];
      expect(reactions, isEmpty,
          reason: 'count drops to 0 → pill is removed');
    });

    test('custom emoji still keyed by name, not resolved to a glyph', () {
      final c = makeContainer();
      final n = notifier(c);

      n.state = [_msg()];

      // Custom emoji: id is non-null.
      n.applyReaction('m1', 'bonk', added: true, isOwn: true, emojiId: '99');

      final reactions = messages(c)!.first.reactions!;
      expect(reactions.length, 1);
      // Custom emoji keys on name, not glyph.
      expect(reactions.first.emoji['name'], 'bonk');
      expect(reactions.first.emoji['id'], '99');

      // Gateway echo with same name+id merges.
      n.applyReaction('m1', 'bonk', added: true, isOwn: true, emojiId: '99');
      expect(messages(c)!.first.reactions!.length, 1,
          reason: 'custom echo merges via includesMe guard');
    });
  });

  group('clearReactionEmoji — canonicalised match', () {
    test('clears a glyph-stored reaction when given a shortcode', () {
      final c = makeContainer();
      final n = notifier(c);

      // After the PR fix, reactions are stored with the glyph as their name.
      n.state = [_msg(reactions: [_reaction('🍔', count: 2)])];

      // Gateway clear_emoji sends the shortcode (the bug scenario).
      n.clearReactionEmoji('m1', 'hamburger');

      expect(messages(c)!.first.reactions, isEmpty,
          reason: 'shortcode must resolve to glyph before matching');
    });

    test('clears a glyph-stored reaction when given the glyph', () {
      final c = makeContainer();
      final n = notifier(c);

      n.state = [_msg(reactions: [_reaction('🍔', count: 2)])];

      n.clearReactionEmoji('m1', '🍔');

      expect(messages(c)!.first.reactions, isEmpty);
    });

    test('clears a shortcode-stored reaction when given a shortcode', () {
      final c = makeContainer();
      final n = notifier(c);

      // Older REST-loaded reactions might still be stored with the shortcode.
      n.state = [_msg(reactions: [_reaction('hamburger', count: 1)])];

      n.clearReactionEmoji('m1', 'hamburger');

      expect(messages(c)!.first.reactions, isEmpty);
    });

    test('does not clear a different emoji', () {
      final c = makeContainer();
      final n = notifier(c);

      n.state = [
        _msg(reactions: [_reaction('🍔', count: 1), _reaction('👍', count: 3)]),
      ];

      n.clearReactionEmoji('m1', '🍔');

      final remaining = messages(c)!.first.reactions!;
      expect(remaining.length, 1);
      expect(remaining.first.emoji['name'], '👍');
    });
  });

  group('applyReaction — remove path', () {
    test('removes pill when count reaches zero', () {
      final c = makeContainer();
      final n = notifier(c);

      n.state = [_msg(reactions: [_reaction('👍', count: 1, me: true)])];

      n.applyReaction('m1', '👍', added: false, isOwn: true);

      expect(messages(c)!.first.reactions, isEmpty);
    });

    test('decrement by another user leaves includesMe unchanged', () {
      final c = makeContainer();
      final n = notifier(c);

      n.state = [_msg(reactions: [_reaction('👍', count: 3, me: true)])];

      n.applyReaction('m1', '👍', added: false, isOwn: false);

      final r = messages(c)!.first.reactions!.first;
      expect(r.count, 2);
      expect(r.includesMe, isTrue);
    });
  });
}
