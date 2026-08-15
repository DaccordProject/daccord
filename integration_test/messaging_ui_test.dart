/// UI end-to-end: the real app shell, on a real device, against a real
/// accordserver.
///
/// Layer 1 (`integration/`) proves the caches update. This proves the *screen*
/// does — the class of bug where the data is right and the UI never shows it:
/// a list that doesn't rebuild, a route that doesn't resolve, a channel that
/// renders empty.
///
/// See `integration_test/README.md`.
library;

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/main.dart';
import 'package:bonfire/router/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../integration/support/harness.dart';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final harness = await IntegrationHarness.resolve();

  group('messaging UI', () {
    late TestAccount alice;
    late TestAccount bob;
    late String spaceId;
    late String channelId;

    setUpAll(() async {
      await harness.setupHive();

      alice = await harness.newAccount('alice', connect: false);
      bob = await harness.newAccount('bob', connect: false);

      final space = await alice.client.spaces.create({
        'name': 'UI Space',
        'public': true,
      });
      spaceId = (space.data! as AccordSpace).id;

      // Use the channel the server seeds with every new space, which is also
      // the one the shell opens by default. Creating an extra channel here
      // would post into a channel the UI isn't showing.
      final channels = await alice.client.spaces.listChannels(spaceId);
      expect(channels.ok, isTrue, reason: '${channels.error}');
      channelId = (channels.data! as List)
          .cast<AccordChannel>()
          .firstWhere((c) => c.type == 'text' && c.name == 'general')
          .id;

      final joined = await bob.client.spaces.join(spaceId);
      expect(joined.ok, isTrue, reason: 'bob could not join: ${joined.error}');

      await harness.connectGateway(alice);
      await harness.connectGateway(bob);
    });

    tearDownAll(harness.dispose);

    /// Pumps the real app shell signed in as [alice], wires the gateway event
    /// handler to the tree's own container, and lands on the space.
    Future<void> pumpApp(WidgetTester tester) async {
      // A desktop-sized surface: the shell collapses the channel sidebar on
      // narrow viewports, and these tests drive it by tapping.
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        harness.scopeFor(alice, child: const MainWindow()),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MainWindow)),
      );
      addTearDown(harness.wireEvents(container, alice));

      // Cycle alice's gateway now that this tree is listening, so READY — and
      // the hydration it drives — arrives with the handler attached. A tree
      // that misses its own READY renders an empty shell.
      await alice.client.logout();
      await harness.connectGateway(alice);

      routerController.go('/spaces?space=$spaceId');
      await tester.pumpAndSettle();
    }

    /// `pumpAndSettle` can't wait on network or gateway traffic — it settles as
    /// soon as animations stop, which happens long before the server answers.
    Future<void> pumpUntilFound(
      WidgetTester tester,
      Finder finder, {
      Duration timeout = const Duration(seconds: 15),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
      }
      fail('$finder never appeared within $timeout');
    }

    testWidgets('renders the space shell for the signed-in user',
        (tester) async {
      await pumpApp(tester);

      // The channel sidebar lists the space's channel…
      await pumpUntilFound(tester, find.text('general'));
      // …the shell opens it, so the composer addresses it…
      await pumpUntilFound(tester, find.text('Message #general'));
      // …and the member list shows who we signed in as.
      await pumpUntilFound(tester, find.text(alice.username));
    });

    testWidgets('opens a channel and renders its history', (tester) async {
      final created = await alice.client.messages.create(channelId, {
        'content': 'rendered from history',
      });
      expect(created.ok, isTrue, reason: '${created.error}');

      await pumpApp(tester);

      // The channel sidebar must list the channel…
      await pumpUntilFound(tester, find.text('general'));

      // …and opening it must render the message that was already there.
      // findRichText: message bodies go through the markdown renderer, so the
      // content lands in a RichText span rather than a Text widget.
      await pumpUntilFound(
        tester,
        find.text('rendered from history', findRichText: true),
      );
    });

    testWidgets('a message sent by someone else appears live', (tester) async {
      await pumpApp(tester);

      await pumpUntilFound(tester, find.text('general'));

      // Nothing refetches here — this can only arrive over the gateway.
      const content = 'live from bob';
      final sent =
          await bob.client.messages.create(channelId, {'content': content});
      expect(sent.ok, isTrue, reason: '${sent.error}');

      await pumpUntilFound(tester, find.text(content, findRichText: true));
    });
  }, skip: harness.skipReason);
}
