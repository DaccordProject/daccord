import 'dart:io';

import 'package:bonfire/features/onboarding/controllers/onboarding_controller.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

late Directory _tempDir;

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

OnboardingController _notifier(ProviderContainer c) =>
    c.read(onboardingControllerProvider.notifier);

void main() {
  // The seen-marker lives in the existing `accord-settings` box under its own
  // key (not inside AccordSettings) — see OnboardingController.
  setUp(() async {
    _tempDir = Directory.systemTemp.createTempSync('onboarding-test');
    Hive.init(_tempDir.path);
    await Hive.openBox('accord-settings');
    await Hive.openBox('accord-session');
    await Hive.openBox('space-cache');
    kAppVersion = '1.2.3';
  });

  tearDown(() async {
    kAppVersion = '0.0.0';
    for (final box in ['accord-settings', 'accord-session', 'space-cache']) {
      await Hive.deleteBoxFromDisk(box);
    }
    await Hive.close();
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  group('onboardingTrigger', () {
    test('no marker and no prior traces is a first launch', () {
      expect(
        onboardingTrigger(hasSeen: false, existingUser: false),
        OnboardingTrigger.firstLaunch,
      );
    });

    test('a stamped marker suppresses the tour', () {
      expect(
        onboardingTrigger(hasSeen: true, existingUser: false),
        OnboardingTrigger.alreadySeen,
      );
    });

    test('an unmarked but already-used install is an existing user', () {
      expect(
        onboardingTrigger(hasSeen: false, existingUser: true),
        OnboardingTrigger.existingUser,
      );
    });

    test('force wins over both the marker and prior traces', () {
      expect(
        onboardingTrigger(hasSeen: true, existingUser: true, force: true),
        OnboardingTrigger.replay,
      );
    });
  });

  group('onboardingLooksLikeExistingUser', () {
    test('a truly fresh install has no traces', () {
      expect(
        onboardingLooksLikeExistingUser(
          hasPersistedSession: false,
          hasSavedAccounts: false,
          hasCachedSpaces: false,
          hasPriorSelection: false,
        ),
        isFalse,
      );
    });

    test('any single trace is conclusive', () {
      for (var i = 0; i < 4; i++) {
        expect(
          onboardingLooksLikeExistingUser(
            hasPersistedSession: i == 0,
            hasSavedAccounts: i == 1,
            hasCachedSpaces: i == 2,
            hasPriorSelection: i == 3,
          ),
          isTrue,
          reason: 'trace $i should be enough on its own',
        );
      }
    });
  });

  group('seen marker', () {
    test('is absent on a fresh install and stamps the running version', () {
      final controller = _notifier(_container());
      expect(controller.hasSeenTour, isFalse);
      expect(controller.seenVersion, isEmpty);

      controller.markSeen();

      expect(controller.hasSeenTour, isTrue);
      expect(controller.seenVersion, '1.2.3');
      expect(
        Hive.box('accord-settings').get(OnboardingController.seenKey),
        '1.2.3',
      );
    });

    test('survives a rebuilt controller (the second launch)', () {
      _notifier(_container()).markSeen();
      // A new container is a new launch reading the same box.
      expect(_notifier(_container()).hasSeenTour, isTrue);
    });

    test('clearSeen re-arms the tour', () {
      final controller = _notifier(_container());
      controller.markSeen();
      controller.clearSeen();
      expect(controller.hasSeenTour, isFalse);
    });
  });

  group('startup gating', () {
    test('first launch shows the tour, the second does not', () {
      final first = _notifier(_container());
      expect(first.consumeStartupTrigger(), OnboardingTrigger.firstLaunch);
      // The tour route stamps the marker when it closes.
      first.markSeen();

      final second = _notifier(_container());
      expect(second.consumeStartupTrigger(), OnboardingTrigger.alreadySeen);
    });

    test('only decides once per launch', () {
      final controller = _notifier(_container());
      expect(controller.consumeStartupTrigger(), OnboardingTrigger.firstLaunch);
      expect(controller.consumeStartupTrigger(), isNull);
    });

    test('a persisted session means an existing user — no tour', () {
      Hive.box('accord-session').put('session', {'token': 'x'});
      final controller = _notifier(_container());
      expect(
        controller.consumeStartupTrigger(),
        OnboardingTrigger.existingUser,
      );
    });

    test('saved accounts mean an existing user, even after a log out', () {
      Hive.box('accord-session').put('accounts', {
        'user@server': {'token': 'x'},
      });
      final controller = _notifier(_container());
      expect(
        controller.consumeStartupTrigger(),
        OnboardingTrigger.existingUser,
      );
    });

    test('cached spaces from a previous session mean an existing user', () {
      Hive.box('space-cache').put('server-key', ['space-1']);
      final controller = _notifier(_container());
      expect(
        controller.consumeStartupTrigger(),
        OnboardingTrigger.existingUser,
      );
    });

    test('a restored last space/channel selection means an existing user', () {
      Hive.box('accord-settings').put('settings', {
        'lastSpaceId': 'space-1',
        'lastChannelId': 'channel-1',
      });
      final controller = _notifier(_container());
      expect(
        controller.consumeStartupTrigger(),
        OnboardingTrigger.existingUser,
      );
    });

    test('empty persisted settings are not mistaken for prior use', () {
      Hive.box(
        'accord-settings',
      ).put('settings', {'lastSpaceId': '', 'lastChannelId': ''});
      final controller = _notifier(_container());
      expect(controller.consumeStartupTrigger(), OnboardingTrigger.firstLaunch);
    });

    test(
      'the existing-user answer is frozen at launch, so signing in mid-launch '
      'cannot flip a fresh user into an old one',
      () {
        final controller = _notifier(_container());
        controller.captureLaunchState();
        // Sign-in persists a session moments later.
        Hive.box('accord-session').put('session', {'token': 'x'});
        expect(controller.existingUserAtLaunch, isFalse);
        expect(controller.startupTrigger, OnboardingTrigger.firstLaunch);
        // ...but a launch that starts with the session already there is old.
        controller.resetStartupGuard();
        expect(controller.existingUserAtLaunch, isTrue);
      },
    );
  });

  group('active state', () {
    test('tracks whether the tour route is on screen', () {
      final container = _container();
      final controller = _notifier(container);
      expect(container.read(onboardingControllerProvider), isFalse);
      controller.setActive(true);
      expect(container.read(onboardingControllerProvider), isTrue);
      controller.setActive(false);
      expect(container.read(onboardingControllerProvider), isFalse);
    });
  });
}
