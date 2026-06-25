import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:flutter_test/flutter_test.dart';

// Cross-server DM open (#163): a qualified recipient steers the server onto its
// federation path; a bare recipient stays a same-server DM. The handle the user
// types must be validated as a qualified remote id before we attempt the open.

void main() {
  group('dmCreateBody', () {
    test('a qualified recipient uses the single recipient_id field', () {
      expect(
        dmCreateBody('123@b.example'),
        {'recipient_id': '123@b.example'},
      );
    });

    test('a bare recipient uses the recipients list (same-server DM)', () {
      expect(
        dmCreateBody('123'),
        {
          'recipients': ['123'],
        },
      );
    });
  });

  group('isValidRemoteHandle', () {
    test('accepts a qualified handle', () {
      expect(isValidRemoteHandle('123@b.example'), isTrue);
      expect(isValidRemoteHandle('  123@b.example  '), isTrue);
    });

    test('rejects a bare local id', () {
      expect(isValidRemoteHandle('123'), isFalse);
    });

    test('rejects a handle missing the local part or the domain', () {
      expect(isValidRemoteHandle('@b.example'), isFalse);
      expect(isValidRemoteHandle('123@'), isFalse);
      expect(isValidRemoteHandle(''), isFalse);
    });

    test('keeps the final @ so an already-qualified id is still valid', () {
      // A recipient id that arrives doubly qualified still splits on the last @.
      expect(isValidRemoteHandle('123@old.example@new.example'), isTrue);
    });
  });
}
