import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/components/forum_view.dart';
import 'package:bonfire/features/messaging/components/thread_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveForumPostTitle', () {
    test('uses title when present', () {
      final m = AccordMessage(title: 'My title', content: 'body text');
      expect(resolveForumPostTitle(m), 'My title');
    });

    test('trims whitespace from title', () {
      final m = AccordMessage(title: '  trimmed  ', content: 'body');
      expect(resolveForumPostTitle(m), 'trimmed');
    });

    test('falls back to first non-empty content line when title absent', () {
      final m = AccordMessage(title: null, content: '\nfirst line\nsecond');
      expect(resolveForumPostTitle(m), 'first line');
    });

    test('falls back to first non-empty content line when title is empty', () {
      final m = AccordMessage(title: '', content: 'only line');
      expect(resolveForumPostTitle(m), 'only line');
    });

    test('falls back to first non-empty content line when title is whitespace', () {
      final m = AccordMessage(title: '   ', content: 'body');
      expect(resolveForumPostTitle(m), 'body');
    });

    test('returns "Untitled post" when title and content are both empty', () {
      final m = AccordMessage(title: null, content: '');
      expect(resolveForumPostTitle(m), 'Untitled post');
    });

    test('returns "Untitled post" when content has only blank lines', () {
      final m = AccordMessage(title: null, content: '\n  \n');
      expect(resolveForumPostTitle(m), 'Untitled post');
    });

    test('non-String title (e.g. null object field) falls back to content', () {
      // AccordMessage.title is Object? — a non-String value should fall through
      final m = AccordMessage(title: 42, content: 'body');
      expect(resolveForumPostTitle(m), 'body');
    });
  });

  group('ThreadResult', () {
    test('edited carries the updated root', () {
      final msg = AccordMessage(id: 'abc', content: 'hi');
      final result = ThreadResult.edited(msg);
      expect(result.root, same(msg));
      expect(result.deleted, isFalse);
    });

    test('deleted has no root and deleted=true', () {
      const result = ThreadResult.deleted();
      expect(result.root, isNull);
      expect(result.deleted, isTrue);
    });
  });
}
