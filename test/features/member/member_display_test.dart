import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('accordInitial', () {
    test('returns ? for empty string', () {
      expect(accordInitial(''), '?');
    });

    test('returns ? for null', () {
      expect(accordInitial(null), '?');
    });

    test('returns ? for whitespace-only string', () {
      expect(accordInitial('   '), '?');
    });

    test('returns uppercase first character of a simple name', () {
      expect(accordInitial('alice'), 'A');
    });

    test('preserves uppercase when already uppercase', () {
      expect(accordInitial('Bob'), 'B');
    });

    test('trims leading whitespace before taking first character', () {
      expect(accordInitial('  carol'), 'C');
    });

    test('works with a single character', () {
      expect(accordInitial('z'), 'Z');
    });
  });
}
