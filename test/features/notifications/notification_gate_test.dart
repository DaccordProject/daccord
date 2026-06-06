import 'package:bonfire/features/notifications/utils/notification_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Thin wrapper defaulting the "enabled & not-own & not-visible" knobs most
  // cases share, so each test reads as the decision under test.
  bool notify({
    bool notificationsEnabled = true,
    bool suppressEveryone = false,
    bool isOwnMessage = false,
    bool isVisibleChannel = false,
    bool mentionsMe = false,
    bool mentionEveryone = false,
    String? channelLevel,
  }) =>
      MessageNotificationGate.shouldNotify(
        notificationsEnabled: notificationsEnabled,
        suppressEveryone: suppressEveryone,
        isOwnMessage: isOwnMessage,
        isVisibleChannel: isVisibleChannel,
        mentionsMe: mentionsMe,
        mentionEveryone: mentionEveryone,
        channelLevel: channelLevel,
      );

  group('MessageNotificationGate.shouldNotify', () {
    test('a direct mention notifies', () {
      expect(notify(mentionsMe: true), isTrue);
    });

    test('a message with no mention does not notify', () {
      expect(notify(), isFalse);
    });

    group('@everyone', () {
      test('notifies when suppressEveryone is false', () {
        expect(notify(mentionEveryone: true, suppressEveryone: false), isTrue);
      });

      test('does NOT notify when suppressEveryone is true', () {
        expect(notify(mentionEveryone: true, suppressEveryone: true), isFalse);
      });

      test('a direct mention still notifies even with suppressEveryone', () {
        expect(
          notify(mentionsMe: true, mentionEveryone: true, suppressEveryone: true),
          isTrue,
        );
      });
    });

    group('per-channel level', () {
      test('"all" notifies on any non-mention message', () {
        expect(notify(channelLevel: 'all'), isTrue);
      });

      test('"nothing" suppresses even direct mentions', () {
        expect(notify(channelLevel: 'nothing', mentionsMe: true), isFalse);
        expect(notify(channelLevel: 'nothing', mentionEveryone: true), isFalse);
      });

      test('"mentions" matches the default mention-only behaviour', () {
        expect(notify(channelLevel: 'mentions'), isFalse);
        expect(notify(channelLevel: 'mentions', mentionsMe: true), isTrue);
      });

      test('"all" still respects own/visible/disabled gates', () {
        expect(notify(channelLevel: 'all', isOwnMessage: true), isFalse);
        expect(notify(channelLevel: 'all', isVisibleChannel: true), isFalse);
        expect(
            notify(channelLevel: 'all', notificationsEnabled: false), isFalse);
      });
    });

    group('suppression', () {
      test('own messages never notify, even when mentioning self', () {
        expect(notify(isOwnMessage: true, mentionsMe: true), isFalse);
        expect(notify(isOwnMessage: true, mentionEveryone: true), isFalse);
      });

      test('the visible channel never notifies, even for a mention', () {
        expect(notify(isVisibleChannel: true, mentionsMe: true), isFalse);
        expect(notify(isVisibleChannel: true, mentionEveryone: true), isFalse);
      });

      test('notificationsEnabled == false suppresses any notification', () {
        expect(notify(notificationsEnabled: false, mentionsMe: true), isFalse);
        expect(
          notify(notificationsEnabled: false, mentionEveryone: true),
          isFalse,
        );
      });
    });
  });
}
