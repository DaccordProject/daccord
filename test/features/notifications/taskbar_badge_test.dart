import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/channels/controllers/global_unread.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/notifications/services/taskbar_badge.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps the badge controller off Hive (the real settings controller reads the
/// `accord-settings` box in `build`).
class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this._initial);

  final AccordSettings _initial;

  @override
  AccordSettings build() => _initial;

  void set(AccordSettings next) => state = next;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(taskbarBadgeChannel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(taskbarBadgeChannel, null);
  });

  /// Lets the fire-and-forget platform call settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  ProviderContainer container({AccordSettings? settings}) {
    final c = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(
          () => _FakeSettingsController(settings ?? const AccordSettings()),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  String connect(ProviderContainer c) {
    final session = AccordSession(
      server: AccordServer(
        baseUrl: 'https://a.test',
        gatewayUrl: 'wss://a.test/ws',
        cdnUrl: 'https://a.test/cdn',
      ),
      token: 't',
      userId: 'u1',
      username: 'u1',
    );
    c.read(connectionsControllerProvider.notifier).register(session);
    return session.key;
  }

  Map<Object?, Object?> lastArgs() =>
      calls.last.arguments as Map<Object?, Object?>;

  group('pushTaskbarBadge', () {
    test('sends the mention count and visibility', () async {
      await pushTaskbarBadge(
        const GlobalUnread(hasUnread: true, mentionCount: 3),
      );
      await settle();

      // Desktop-only feature: on a platform without a badge this is a no-op,
      // and there is nothing to assert.
      if (!taskbarBadgeSupported) {
        expect(calls, isEmpty);
        return;
      }
      expect(calls.single.method, 'setBadge');
      expect(lastArgs()['count'], 3);
      expect(lastArgs()['visible'], isTrue);
    });

    test('clears with visible=false when nothing is unread', () async {
      await pushTaskbarBadge(GlobalUnread.none);
      await settle();
      if (!taskbarBadgeSupported) return;
      expect(lastArgs()['count'], 0);
      expect(lastArgs()['visible'], isFalse);
    });

    test('a missing platform implementation is swallowed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(taskbarBadgeChannel, null);
      await expectLater(
        pushTaskbarBadge(const GlobalUnread(hasUnread: true)),
        completes,
      );
    });
  });

  group('TaskbarBadgeController', () {
    test('mirrors unread state onto the platform, live and deduped', () async {
      if (!taskbarBadgeSupported) return;
      final c = container();
      final key = connect(c);
      c.listen(taskbarBadgeControllerProvider, (_, _) {});
      await settle();
      // First push is an explicit clear: Linux launchers persist the last count
      // they were told across restarts, so startup must not inherit it.
      expect(calls.single.method, 'setBadge');
      expect(lastArgs()['visible'], isFalse);
      calls.clear();

      c
          .read(readStateControllerProvider(key).notifier)
          .markUnread('c1', spaceId: 's1', isMention: true);
      await settle();
      expect(calls.length, 1);
      expect(lastArgs()['count'], 1);
      expect(lastArgs()['visible'], isTrue);

      // A second unread channel with no mention leaves the badge identical, so
      // the platform is not touched again.
      c.read(readStateControllerProvider(key).notifier).markUnread(
            'c2',
            spaceId: 's1',
          );
      await settle();
      expect(calls.length, 1);

      c.read(readStateControllerProvider(key).notifier).markRead('c1');
      await settle();
      expect(calls.length, 2);
      expect(lastArgs()['count'], 0);
      expect(lastArgs()['visible'], isTrue);

      c.read(readStateControllerProvider(key).notifier).markRead('c2');
      await settle();
      expect(calls.length, 3);
      expect(lastArgs()['visible'], isFalse);
    });

    test('muted spaces never reach the platform', () async {
      if (!taskbarBadgeSupported) return;
      final c = container(
        settings: const AccordSettings(mutedSpaces: ['s1']),
      );
      final key = connect(c);
      c.listen(taskbarBadgeControllerProvider, (_, _) {});
      await settle();
      calls.clear();
      c
          .read(readStateControllerProvider(key).notifier)
          .markUnread('c1', spaceId: 's1', isMention: true);
      await settle();
      expect(calls, isEmpty);
    });

    test('never clear-then-resets on a change (no badge flicker)', () async {
      if (!taskbarBadgeSupported) return;
      final c = container();
      final key = connect(c);
      c.listen(taskbarBadgeControllerProvider, (_, _) {});
      await settle();
      calls.clear();

      final reads = c.read(readStateControllerProvider(key).notifier);
      reads.markUnread('c1', spaceId: 's1', isMention: true);
      await settle();
      reads.markUnread('c2', spaceId: 's1', isMention: true);
      await settle();

      // One push per distinct state — a rebuild must not emit an intermediate
      // cleared badge (which would flicker the Windows overlay icon).
      expect(calls.length, 2);
      expect(calls.map((c) => (c.arguments as Map)['count']), [1, 2]);
      expect(
        calls.every((c) => (c.arguments as Map)['visible'] == true),
        isTrue,
      );
    });
  });
}
