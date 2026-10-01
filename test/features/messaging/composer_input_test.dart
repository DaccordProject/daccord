import 'package:bonfire/features/messaging/utils/composer_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextSelection _caret(int offset) => TextSelection.collapsed(offset: offset);

void main() {
  group('findMentionTrigger', () {
    test('finds the query between the @ and the caret', () {
      const text = 'hi @Bo';
      expect(findMentionTrigger(text, _caret(text.length)), (
        start: 3,
        end: 6,
        query: 'bo',
      ));
    });

    test('accepts a bare @ at the start', () {
      expect(findMentionTrigger('@', _caret(1)), (start: 0, end: 1, query: ''));
    });

    test('ignores an @ inside a word and stops at whitespace', () {
      expect(findMentionTrigger('email@host', _caret(10)), isNull);
      expect(findMentionTrigger('@bob hi', _caret(7)), isNull);
    });

    test('needs a collapsed selection', () {
      expect(
        findMentionTrigger(
          '@bob',
          const TextSelection(baseOffset: 1, extentOffset: 4),
        ),
        isNull,
      );
    });
  });

  test('isMentionWordChar treats ASCII alphanumerics, _ and non-ASCII as '
      'word characters', () {
    for (final ch in ['a', 'Z', '0', '_', 'é']) {
      expect(isMentionWordChar(ch.codeUnitAt(0)), isTrue, reason: ch);
    }
    for (final ch in [' ', '.', '(', '#']) {
      expect(isMentionWordChar(ch.codeUnitAt(0)), isFalse, reason: ch);
    }
  });

  group('insertAtSelection', () {
    test('replaces the selection and places the caret after the insert', () {
      final next = insertAtSelection(
        const TextEditingValue(
          text: 'hello world',
          selection: TextSelection(baseOffset: 6, extentOffset: 11),
        ),
        'there',
      );
      expect(next.text, 'hello there');
      expect(next.selection, _caret(11));
    });

    test('appends when there is no selection', () {
      final next = insertAtSelection(const TextEditingValue(text: 'hi'), '!');
      expect(next.text, 'hi!');
      expect(next.selection, _caret(3));
    });
  });
}
