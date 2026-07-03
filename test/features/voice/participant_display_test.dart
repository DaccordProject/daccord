import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/voice/utils/participant_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('participantDisplay', () {
    test('prefers the member nickname and per-space avatar over the user', () {
      final user = AccordUser(
        id: 'u1',
        username: 'raw_username',
        displayName: 'Display Name',
        avatar: 'user-avatar-hash',
      );
      final member = AccordMember(
        userId: 'u1',
        user: user,
        nickname: 'Space Nick',
        avatar: 'member-avatar-hash',
      );
      final display = participantDisplay(
        'u1',
        members: {'u1': member},
        users: {'u1': user},
        cdnUrl: 'https://cdn.example',
      );

      expect(display.name, 'Space Nick');
      expect(display.avatarUrl, isNotNull);
      expect(display.avatarUrl, contains('member-avatar-hash'));
    });

    test('falls back to the bare user when no member entry is cached', () {
      final user = AccordUser(
        id: 'u2',
        username: 'raw_username',
        displayName: 'Display Name',
        avatar: 'user-avatar-hash',
      );
      final display = participantDisplay(
        'u2',
        members: const {},
        users: {'u2': user},
        cdnUrl: 'https://cdn.example',
      );

      expect(display.name, 'Display Name');
      expect(display.avatarUrl, isNotNull);
      expect(display.avatarUrl, contains('user-avatar-hash'));
    });

    test('falls back to the raw user id when neither cache has resolved', () {
      final display = participantDisplay(
        'unresolved-id',
        members: const {},
        users: const {},
        cdnUrl: 'https://cdn.example',
      );

      expect(display.name, 'unresolved-id');
      expect(display.avatarUrl, isNull);
    });

    test(
      'derives the avatar color from the embedded user on a member row',
      () {
        final userWithAccent = AccordUser(id: 'u3', accentColor: 0xFF00FF);
        final member = AccordMember(userId: 'u3', user: userWithAccent);
        final display = participantDisplay(
          'u3',
          members: {'u3': member},
          users: const {},
          cdnUrl: null,
        );

        expect(display.color, const Color(0xFFFF00FF));
      },
    );

    test(
      'falls through to the cached bare user for color when the member has '
      'no embedded user',
      () {
        final userWithAccent = AccordUser(id: 'u4', accentColor: 0x123456);
        final member = AccordMember(userId: 'u4');
        final display = participantDisplay(
          'u4',
          members: {'u4': member},
          users: {'u4': userWithAccent},
          cdnUrl: null,
        );

        expect(display.color, const Color(0xFF123456));
      },
    );

    test('two different unresolved ids get different fallback colors', () {
      final a = participantDisplay(
        'id-a',
        members: const {},
        users: const {},
        cdnUrl: null,
      );
      final b = participantDisplay(
        'id-b',
        members: const {},
        users: const {},
        cdnUrl: null,
      );

      expect(a.color, isNot(b.color));
    });
  });
}
