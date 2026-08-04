import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/channels/controllers/global_unread.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ReadStateSnapshot _snapshot(List<ReadEntry> entries) => ReadStateSnapshot(
      entries: {for (final e in entries) e.channelId: e},
    );

/// Keeps the aggregator off Hive (the real settings controller reads the
/// `accord-settings` box in `build`) while still allowing mid-test mutes.
class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this._initial);

  final AccordSettings _initial;

  @override
  AccordSettings build() => _initial;

  void set(AccordSettings next) => state = next;
}

ProviderContainer _container({AccordSettings? settings}) {
  final container = ProviderContainer(
    overrides: [
      settingsControllerProvider.overrideWith(
        () => _FakeSettingsController(settings ?? const AccordSettings()),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AccordSession _session(String userId, String baseUrl) => AccordSession(
      server: AccordServer.fromBaseUrl(baseUrl),
      token: 't',
      userId: userId,
      username: userId,
    );

/// Registers [baseUrl] as a connection and returns its `serverKey`.
String _connect(ProviderContainer c, String userId, String baseUrl) {
  final session = _session(userId, baseUrl);
  c.read(connectionsControllerProvider.notifier).register(session);
  return session.key;
}

void _markUnread(
  ProviderContainer c,
  String serverKey,
  String channelId, {
  String? spaceId,
  int mentions = 0,
}) {
  final notifier = c.read(readStateControllerProvider(serverKey).notifier);
  if (mentions == 0) {
    notifier.markUnread(channelId, spaceId: spaceId);
    return;
  }
  for (var i = 0; i < mentions; i++) {
    notifier.markUnread(channelId, spaceId: spaceId, isMention: true);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('foldGlobalUnread', () {
    test('nothing unread anywhere is empty', () {
      final unread = foldGlobalUnread([_snapshot(const []), _snapshot(const [])]);
      expect(unread, GlobalUnread.none);
      expect(unread.isEmpty, isTrue);
    });

    test('sums mentions across every connection', () {
      final unread = foldGlobalUnread([
        _snapshot(const [
          ReadEntry(channelId: 'c1', spaceId: 's1', mentions: 2),
          ReadEntry(channelId: 'c2', spaceId: 's1', mentions: 1),
        ]),
        _snapshot(const [
          ReadEntry(channelId: 'c3', spaceId: 's9', mentions: 4),
        ]),
      ]);
      expect(unread.mentionCount, 7);
      expect(unread.hasUnread, isTrue);
    });

    test('unread with no mentions is a dot, not a count', () {
      final unread = foldGlobalUnread([
        _snapshot(const [ReadEntry(channelId: 'c1', spaceId: 's1')]),
      ]);
      expect(unread.hasUnread, isTrue);
      expect(unread.mentionCount, 0);
      expect(unread.isEmpty, isFalse);
    });

    test('DMs (no space) count — they can never be space-muted', () {
      final unread = foldGlobalUnread([
        _snapshot(const [ReadEntry(channelId: 'dm1', mentions: 3)]),
      ]);
      expect(unread, const GlobalUnread(hasUnread: true, mentionCount: 3));
    });

    group('mute filter (shared with the rail via UnreadIndicatorGate)', () {
      test('a muted space contributes to neither the count nor the dot', () {
        final unread = foldGlobalUnread(
          [
            _snapshot(const [
              ReadEntry(channelId: 'c1', spaceId: 'muted', mentions: 5),
            ]),
          ],
          mutedSpaces: const ['muted'],
        );
        expect(unread, GlobalUnread.none);
      });

      test('a channel set to `nothing` contributes to neither', () {
        final unread = foldGlobalUnread(
          [
            _snapshot(const [
              ReadEntry(channelId: 'c1', spaceId: 's1', mentions: 5),
            ]),
          ],
          channelLevels: const {'c1': AccordSettings.channelNotifNothing},
        );
        expect(unread, GlobalUnread.none);
      });

      test('a silenced DM contributes to neither', () {
        final unread = foldGlobalUnread(
          [
            _snapshot(const [ReadEntry(channelId: 'dm1', mentions: 2)]),
          ],
          channelLevels: const {'dm1': AccordSettings.channelNotifNothing},
        );
        expect(unread, GlobalUnread.none);
      });

      test('`all` and `mentions` channels still contribute', () {
        final unread = foldGlobalUnread(
          [
            _snapshot(const [
              ReadEntry(channelId: 'c1', spaceId: 's1', mentions: 1),
              ReadEntry(channelId: 'c2', spaceId: 's1', mentions: 2),
            ]),
          ],
          channelLevels: const {
            'c1': AccordSettings.channelNotifAll,
            'c2': AccordSettings.channelNotifMentions,
          },
        );
        expect(unread, const GlobalUnread(hasUnread: true, mentionCount: 3));
      });

      test('muting one space leaves the others counting', () {
        final unread = foldGlobalUnread(
          [
            _snapshot(const [
              ReadEntry(channelId: 'c1', spaceId: 'muted', mentions: 5),
              ReadEntry(channelId: 'c2', spaceId: 'loud', mentions: 2),
            ]),
          ],
          mutedSpaces: const ['muted'],
        );
        expect(unread, const GlobalUnread(hasUnread: true, mentionCount: 2));
      });

      test(
        'a muted space with unread but no mentions does not light the dot',
        () {
          final unread = foldGlobalUnread(
            [
              _snapshot(const [ReadEntry(channelId: 'c1', spaceId: 'muted')]),
            ],
            mutedSpaces: const ['muted'],
          );
          expect(unread.hasUnread, isFalse);
        },
      );
    });
  });

  group('globalUnreadProvider', () {
    test('starts empty with no connections', () {
      final container = _container();
      expect(container.read(globalUnreadProvider), GlobalUnread.none);
    });

    test('sums mentions across two connected servers', () {
      final container = _container();
      final a = _connect(container, 'u1', 'a.test');
      final b = _connect(container, 'u2', 'b.test');

      _markUnread(container, a, 'c1', spaceId: 's1', mentions: 2);
      _markUnread(container, b, 'c1', spaceId: 's2', mentions: 3);

      expect(
        container.read(globalUnreadProvider),
        const GlobalUnread(hasUnread: true, mentionCount: 5),
      );
    });

    test('same channel id on two servers is counted once per server', () {
      final container = _container();
      final a = _connect(container, 'u1', 'a.test');
      final b = _connect(container, 'u1', 'b.test');

      // Snowflakes collide across servers; read state is keyed per server, so
      // the roll-up must see both.
      _markUnread(container, a, 'shared-id', spaceId: 's1', mentions: 1);
      _markUnread(container, b, 'shared-id', spaceId: 's2', mentions: 1);

      expect(container.read(globalUnreadProvider).mentionCount, 2);
    });

    test('unread with no mentions is a dot', () {
      final container = _container();
      final key = _connect(container, 'u1', 'a.test');
      _markUnread(container, key, 'c1', spaceId: 's1');

      final unread = container.read(globalUnreadProvider);
      expect(unread.hasUnread, isTrue);
      expect(unread.mentionCount, 0);
    });

    test('clears once every channel is read', () {
      final container = _container();
      final key = _connect(container, 'u1', 'a.test');
      _markUnread(container, key, 'c1', spaceId: 's1', mentions: 2);
      _markUnread(container, key, 'c2', spaceId: 's1');
      expect(container.read(globalUnreadProvider).isEmpty, isFalse);

      final notifier = container.read(readStateControllerProvider(key).notifier);
      notifier.markRead('c1');
      expect(
        container.read(globalUnreadProvider),
        const GlobalUnread(hasUnread: true, mentionCount: 0),
      );

      notifier.markRead('c2');
      expect(container.read(globalUnreadProvider), GlobalUnread.none);
    });

    test('honours the mute settings live, in both directions', () {
      final container = _container(
        settings: const AccordSettings(mutedSpaces: ['s1']),
      );
      final key = _connect(container, 'u1', 'a.test');
      // Kept alive so the provider recomputes on settings changes rather than
      // only when read.
      container.listen(globalUnreadProvider, (_, _) {});
      _markUnread(container, key, 'c1', spaceId: 's1', mentions: 4);

      expect(container.read(globalUnreadProvider), GlobalUnread.none);

      // Unmuting reveals what arrived while muted immediately — the read state
      // stayed truthful, only the indicator was gated.
      final settings =
          container.read(settingsControllerProvider.notifier)
              as _FakeSettingsController;
      settings.set(const AccordSettings());
      expect(
        container.read(globalUnreadProvider),
        const GlobalUnread(hasUnread: true, mentionCount: 4),
      );

      settings.set(const AccordSettings(mutedSpaces: ['s1']));
      expect(container.read(globalUnreadProvider), GlobalUnread.none);
    });

    test('a disconnected server stops contributing', () {
      final container = _container();
      final a = _connect(container, 'u1', 'a.test');
      final b = _connect(container, 'u2', 'b.test');
      _markUnread(container, a, 'c1', spaceId: 's1', mentions: 1);
      _markUnread(container, b, 'c2', spaceId: 's2', mentions: 1);
      expect(container.read(globalUnreadProvider).mentionCount, 2);

      container.read(connectionsControllerProvider.notifier).remove(b);
      expect(container.read(globalUnreadProvider).mentionCount, 1);
    });
  });
}
