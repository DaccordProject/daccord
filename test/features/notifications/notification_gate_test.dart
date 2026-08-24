import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/notifications/utils/notification_gate.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/shared/models/server_entity_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    bool spaceMuted = false,
    String? channelLevel,
  }) =>
      MessageNotificationGate.shouldNotify(
        notificationsEnabled: notificationsEnabled,
        suppressEveryone: suppressEveryone,
        isOwnMessage: isOwnMessage,
        isVisibleChannel: isVisibleChannel,
        mentionsMe: mentionsMe,
        mentionEveryone: mentionEveryone,
        spaceMuted: spaceMuted,
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

      test('a muted space suppresses any notification, even mentions', () {
        expect(notify(spaceMuted: true, mentionsMe: true), isFalse);
        expect(notify(spaceMuted: true, mentionEveryone: true), isFalse);
        expect(notify(spaceMuted: true, channelLevel: 'all'), isFalse);
      });
    });
  });

  // The unread indicator (rail dot / mention badge / channel pip) must agree
  // with the notification gate above — hence living in the same file. The
  // policy is applied when the indicator is *read*, so the stored read state
  // stays truthful and unmuting reveals it without a reconnect.
  group('unread indicators respect mutes', () {
    const spaceId = 's1';
    const channelId = 'c1';
    const otherChannelId = 'c2';
    const serverKey = 'server';

    /// Read state with one unread, 2-mention channel in [spaceId] (plus an
    /// unrelated unread channel in another space, which must never leak into
    /// [spaceId]'s roll-up).
    const state = ReadStateSnapshot(entries: {
      channelId: ReadEntry(channelId: channelId, spaceId: spaceId, mentions: 2),
      'other': ReadEntry(channelId: 'other', spaceId: 's2', mentions: 5),
    });

    AccordSettings settings({
      bool spaceMuted = false,
      String? channelLevel,
    }) =>
        AccordSettings(
          mutedSpaces: spaceMuted
              ? [ServerEntityKey(serverKey, spaceId).encoded]
              : const [],
          channelNotifications: channelLevel == null
              ? const {}
              : {ServerEntityKey(serverKey, channelId).encoded: channelLevel},
        );

    /// What the UI would render for [spaceId] / [channelId] under [s].
    ({bool railDot, int railBadge, bool channelPip, int channelBadge})
        indicators(AccordSettings s, {ReadStateSnapshot from = state}) => (
              railDot: from.spaceShowsUnread(
                spaceId,
                spaceMuted: s.isSpaceMuted(serverKey, spaceId),
                channelLevels: s.channelNotificationsFor(serverKey),
              ),
              railBadge: from.visibleMentionsInSpace(
                spaceId,
                spaceMuted: s.isSpaceMuted(serverKey, spaceId),
                channelLevels: s.channelNotificationsFor(serverKey),
              ),
              channelPip: from.isUnreadVisible(
                channelId,
                channelLevels: s.channelNotificationsFor(serverKey),
              ),
              channelBadge: from.visibleMentionCount(
                channelId,
                channelLevels: s.channelNotificationsFor(serverKey),
              ),
            );

    test('unmuted, default level: dot and badge both show', () {
      final i = indicators(settings());
      expect(i.railDot, isTrue);
      expect(i.railBadge, 2);
      expect(i.channelPip, isTrue);
      expect(i.channelBadge, 2);
    });

    test('a muted space shows no rail dot and no mention badge', () {
      final i = indicators(settings(spaceMuted: true));
      expect(i.railDot, isFalse);
      expect(i.railBadge, 0);
    });

    test('a muted space still shows unread inside the space', () {
      // Muting suppresses the rail roll-up only — the channel list keeps
      // showing which channels moved on.
      final i = indicators(settings(spaceMuted: true));
      expect(i.channelPip, isTrue);
      expect(i.channelBadge, 2);
    });

    test('channel level "nothing": no pip, and no space roll-up', () {
      final i = indicators(settings(channelLevel: 'nothing'));
      expect(i.railDot, isFalse);
      expect(i.railBadge, 0);
      expect(i.channelPip, isFalse);
      expect(i.channelBadge, 0);
    });

    test('channel level "mentions" (the default) shows dot and badge', () {
      final i = indicators(settings(channelLevel: 'mentions'));
      expect(i.railDot, isTrue);
      expect(i.railBadge, 2);
      expect(i.channelPip, isTrue);
      expect(i.channelBadge, 2);
    });

    test('channel level "all" shows dot and badge', () {
      final i = indicators(settings(channelLevel: 'all'));
      expect(i.railDot, isTrue);
      expect(i.railBadge, 2);
      expect(i.channelPip, isTrue);
      expect(i.channelBadge, 2);
    });

    test('a space mute beats an explicit "all" channel level', () {
      final s = AccordSettings(
        mutedSpaces: [ServerEntityKey(serverKey, spaceId).encoded],
        channelNotifications: {
          ServerEntityKey(serverKey, channelId).encoded: 'all',
        },
      );
      final i = indicators(s);
      expect(i.railDot, isFalse);
      expect(i.railBadge, 0);
    });

    test('a silenced channel does not hide its space\'s other unread', () {
      const mixed = ReadStateSnapshot(entries: {
        channelId:
            ReadEntry(channelId: channelId, spaceId: spaceId, mentions: 2),
        otherChannelId:
            ReadEntry(channelId: otherChannelId, spaceId: spaceId, mentions: 1),
      });
      final i = indicators(settings(channelLevel: 'nothing'), from: mixed);
      expect(i.railDot, isTrue, reason: '$otherChannelId is still unread');
      expect(i.railBadge, 1, reason: 'only the silenced channel is excluded');
      expect(i.channelPip, isFalse);
    });

    test('muting is a pure read-side filter: unmuting reveals prior unread',
        () {
      // Same snapshot, different settings — no new message, no reconnect.
      expect(indicators(settings(spaceMuted: true)).railDot, isFalse);
      expect(indicators(settings()).railDot, isTrue);
      expect(indicators(settings()).railBadge, 2);
    });

    test('the READY hydrate path yields the same mute-aware result', () {
      // The gateway seed is deliberately unfiltered, so verify the filter still
      // lands on hydrated state (a reconnect must not re-light a muted space).
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const key = 'u1@server.test';
      container.read(readStateControllerProvider(key).notifier).hydrate(const [
        ReadEntry(channelId: channelId, spaceId: spaceId, mentions: 2),
      ]);
      final hydrated = container.read(readStateControllerProvider(key));

      expect(indicators(settings(spaceMuted: true), from: hydrated).railDot,
          isFalse);
      expect(indicators(settings(spaceMuted: true), from: hydrated).railBadge,
          0);
      expect(indicators(settings(channelLevel: 'nothing'), from: hydrated)
          .channelPip,
          isFalse);
      expect(indicators(settings(), from: hydrated).railDot, isTrue);
      expect(indicators(settings(), from: hydrated).railBadge, 2);
    });

    test('markUnread stays truthful while muted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const key = 'u1@server.test';
      container
          .read(readStateControllerProvider(key).notifier)
          .markUnread(channelId, spaceId: spaceId, isMention: true);
      final live = container.read(readStateControllerProvider(key));

      expect(live.isUnread(channelId), isTrue,
          reason: 'the write path never filters');
      expect(indicators(settings(spaceMuted: true), from: live).railDot,
          isFalse);
      expect(indicators(settings(), from: live).railBadge, 1);
    });
  });

  group('MessageNotificationGate.countsAsMention', () {
    test('suppresses broadcast mentions when requested', () {
      expect(
        MessageNotificationGate.countsAsMention(
          mentionsMe: false,
          mentionEveryone: true,
          suppressEveryone: true,
        ),
        isFalse,
      );
    });

    test('counts broadcasts when suppression is off', () {
      expect(
        MessageNotificationGate.countsAsMention(
          mentionsMe: false,
          mentionEveryone: true,
          suppressEveryone: false,
        ),
        isTrue,
      );
    });

    test('direct and role mentions are unaffected by suppression', () {
      expect(
        MessageNotificationGate.countsAsMention(
          mentionsMe: true,
          mentionEveryone: false,
          suppressEveryone: true,
        ),
        isTrue,
      );
      expect(
        MessageNotificationGate.countsAsMention(
          mentionsMe: true,
          mentionEveryone: true,
          suppressEveryone: true,
        ),
        isTrue,
      );
    });
  });
}
