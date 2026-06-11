import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEmojiToken', () {
    test('splits name:numericId into name and id', () {
      final ref = parseEmojiToken('wave:123456');
      expect(ref.name, 'wave');
      expect(ref.id, '123456');
    });

    test('returns bare name unchanged when there is no numeric suffix', () {
      final ref = parseEmojiToken('hamburger');
      expect(ref.name, 'hamburger');
      expect(ref.id, isNull);
    });

    test('ignores trailing colon (colon-wrapped shortcode form)', () {
      final ref = parseEmojiToken(':hamburger:');
      expect(ref.name, ':hamburger:');
      expect(ref.id, isNull);
    });

    test('ignores non-numeric suffix', () {
      final ref = parseEmojiToken('emoji:notanumber');
      expect(ref.name, 'emoji:notanumber');
      expect(ref.id, isNull);
    });

    test('handles empty string', () {
      final ref = parseEmojiToken('');
      expect(ref.name, '');
      expect(ref.id, isNull);
    });
  });

  group('resolveEmojiGlyph', () {
    test('resolves known shortcode to glyph', () {
      expect(resolveEmojiGlyph('joy'), '😂');
    });

    test('passes through an already-unicode glyph unchanged', () {
      expect(resolveEmojiGlyph('😂'), '😂');
    });

    test('strips surrounding colons before lookup', () {
      expect(resolveEmojiGlyph(':joy:'), '😂');
    });

    test('returns unknown shortcode as-is', () {
      expect(resolveEmojiGlyph('notarealemoji'), 'notarealemoji');
    });

    test('returns empty string unchanged', () {
      expect(resolveEmojiGlyph(''), '');
    });
  });

  group('mute-list channel_id extraction', () {
    // Mirrors the logic in channel_context_menu.dart and _MuteButtonState._load.
    Set<String> extractMutedIds(List<dynamic> data) {
      return data
          .map((e) => e is Map ? e['channel_id']?.toString() : e?.toString())
          .whereType<String>()
          .toSet();
    }

    test('extracts channel_id from structured mute entries', () {
      final ids = extractMutedIds([
        {'channel_id': '111', 'other': 'ignored'},
        {'channel_id': '222'},
      ]);
      expect(ids, {'111', '222'});
    });

    test('falls back to toString for plain-string entries', () {
      final ids = extractMutedIds(['333', '444']);
      expect(ids, {'333', '444'});
    });

    test('skips entries where channel_id is absent', () {
      final ids = extractMutedIds([
        {'other_key': 'value'},
        {'channel_id': '555'},
      ]);
      expect(ids, {'555'});
    });

    test('handles empty list', () {
      expect(extractMutedIds([]), isEmpty);
    });
  });
}
