import 'package:bonfire/features/messaging/utils/emoticons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the conversion table', () {
    const cases = <String, String>{
      ':)': '🙂',
      ':-)': '🙂',
      '(:': '🙂',
      ':(': '🙁',
      ':-(': '🙁',
      ":'(": '😢',
      ':D': '😃',
      ':-D': '😃',
      ';)': '😉',
      ';-)': '😉',
      ':P': '😛',
      ':p': '😛',
      ':-P': '😛',
      ':O': '😮',
      ':o': '😮',
      ':/': '😕',
      ':-/': '😕',
      ':|': '😐',
      '>:(': '😠',
      'xD': '😆',
      'XD': '😆',
      '<3': '❤️',
      '</3': '💔',
      ':*': '😘',
      'o/': '👋',
      r'\o': '👋',
    };

    for (final entry in cases.entries) {
      test('${entry.key} on its own converts to ${entry.value}', () {
        expect(applyEmoticons(entry.key), entry.value);
      });

      test('${entry.key} converts surrounded by whitespace', () {
        expect(
          applyEmoticons('hey ${entry.key} there'),
          'hey ${entry.value} there',
        );
      });
    }

    test('every mapping resolves to a real catalog glyph', () {
      for (final entry in kEmoticons.entries) {
        expect(
          entry.value.runes.any((r) => r > 0x7F),
          isTrue,
          reason:
              '${entry.key} → "${entry.value}" is not an emoji glyph; is '
              '"${kEmoticonNames[entry.key]}" missing from kEmojiCatalog?',
        );
      }
    });

    test('longest match wins over its prefix', () {
      expect(applyEmoticons(":'("), '😢');
      expect(applyEmoticons('</3'), '💔');
      expect(applyEmoticons('>:('), '😠');
      expect(applyEmoticons(':-)'), '🙂');
    });

    test('converts at the start, middle and end of a line', () {
      expect(applyEmoticons(':) ok :( done :D'), '🙂 ok 🙁 done 😃');
    });

    test('converts across newlines', () {
      expect(applyEmoticons('one :)\ntwo :('), 'one 🙂\ntwo 🙁');
    });

    test('allows trailing punctuation after an emoticon', () {
      expect(applyEmoticons('nice :).'), 'nice 🙂.');
      expect(applyEmoticons('really :)!'), 'really 🙂!');
      expect(applyEmoticons('(spotted <3)'), '(spotted ❤️)');
    });

    test('needs whitespace (not just punctuation) before the emoticon', () {
      expect(applyEmoticons('(<3)'), '(<3)');
    });

    test('leaves plain text alone', () {
      expect(applyEmoticons('hello world'), 'hello world');
      expect(applyEmoticons(''), '');
    });
  });

  group('code is never converted', () {
    test('inline code spans survive', () {
      expect(applyEmoticons('use `:)` here'), 'use `:)` here');
    });

    test('multi-backtick code spans survive', () {
      expect(applyEmoticons('``a :) b``'), '``a :) b``');
    });

    test('fenced code blocks survive', () {
      const input = '```\nif (x) {:P}\n```';
      expect(applyEmoticons(input), input);
    });

    test('fenced blocks with an info string survive', () {
      const input = '```dart\nvoid f() {:D}\n```';
      expect(applyEmoticons(input), input);
    });

    test('tilde fences survive', () {
      const input = '~~~\nfoo :( bar\n~~~';
      expect(applyEmoticons(input), input);
    });

    test('an unterminated fence protects the rest of the message', () {
      const input = '```\nstill code :)';
      expect(applyEmoticons(input), input);
    });

    test('text around a fenced block still converts', () {
      expect(
        applyEmoticons('before :)\n```\ncode :(\n```\nafter :D'),
        'before 🙂\n```\ncode :(\n```\nafter 😃',
      );
    });

    test('text around an inline code span still converts', () {
      expect(applyEmoticons(':) `:(` :D'), '🙂 `:(` 😃');
    });
  });

  group('URLs are never converted', () {
    test('https URL with an emoticon-looking tail', () {
      const input = 'see https://example.com/foo:)bar';
      expect(applyEmoticons(input), input);
    });

    test('http URL with :( inside the path', () {
      const input = 'http://x/a:(b';
      expect(applyEmoticons(input), input);
    });

    test('a URL followed by a real emoticon still converts the emoticon', () {
      expect(
        applyEmoticons('https://example.com/a:)b :)'),
        'https://example.com/a:)b 🙂',
      );
    });

    test('bare www links are protected', () {
      const input = 'www.example.com/x:/y';
      expect(applyEmoticons(input), input);
    });

    test('markdown link destinations are protected', () {
      const input = '[docs](https://example.com/p:D)';
      expect(applyEmoticons(input), input);
    });
  });

  group('mid-word sequences are never converted', () {
    test('no whitespace before the emoticon', () {
      expect(applyEmoticons('a:)'), 'a:)');
      expect(applyEmoticons('foo<3'), 'foo<3');
    });

    test('no boundary after the emoticon', () {
      expect(applyEmoticons('foo:Dbar'), 'foo:Dbar');
      expect(applyEmoticons(':Dbar'), ':Dbar');
    });

    test('xD only converts as its own word', () {
      expect(applyEmoticons('axD'), 'axD');
      expect(applyEmoticons('xDx'), 'xDx');
      expect(applyEmoticons('lol xD'), 'lol 😆');
    });

    test('o/ and \\o only convert as their own word', () {
      expect(applyEmoticons('foo/bar'), 'foo/bar');
      expect(applyEmoticons('hello o/bar'), 'hello o/bar');
      expect(applyEmoticons('hi o/'), 'hi 👋');
    });
  });

  group('emoji shortcodes are never converted', () {
    test(':name: shortcodes survive', () {
      expect(applyEmoticons('nice :party_parrot:'), 'nice :party_parrot:');
      expect(applyEmoticons(':Pepe: hi'), ':Pepe: hi');
      expect(applyEmoticons(':ok_hand:'), ':ok_hand:');
    });

    test('custom <a:name:id> tags survive', () {
      const input = 'look <:party:123456> and <a:dance:987>';
      expect(applyEmoticons(input), input);
    });

    test('name:id reaction tokens survive', () {
      expect(applyEmoticons('wave:123456'), 'wave:123456');
    });

    test('a shortcode next to an emoticon still converts the emoticon', () {
      expect(applyEmoticons(':tada: :)'), ':tada: 🙂');
    });
  });

  group('ratios and timestamps are never converted', () {
    test('clock times survive', () {
      expect(applyEmoticons('meet at 10:00'), 'meet at 10:00');
      expect(applyEmoticons('10:00-11:30 works'), '10:00-11:30 works');
    });

    test('ratios survive', () {
      expect(applyEmoticons('a 1:1 call'), 'a 1:1 call');
      expect(applyEmoticons('scaled 16:9'), 'scaled 16:9');
    });

    test('path-like text survives', () {
      expect(applyEmoticons('foo:/bar'), 'foo:/bar');
      expect(applyEmoticons('C:/Users/me'), 'C:/Users/me');
    });

    test('an emoji glyph already in the text is untouched', () {
      expect(applyEmoticons('already 🙂 here'), 'already 🙂 here');
    });
  });
}
