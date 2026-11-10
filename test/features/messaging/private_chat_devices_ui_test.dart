import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/private_chat_devices.dart';
import 'package:bonfire/features/messaging/views/private_chat_devices.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2ee_test_server.dart';

/// The device-linking UI over the in-memory v2 server: a pending device sees
/// the setup banner and its code, an approved device gets the approval prompt
/// with the same code, and approving flips the pending device to active.

Widget _app(PrivateChatEncryption encryption, Widget home) => ProviderScope(
  overrides: [privateChatEncryptionProvider.overrideWithValue(encryption)],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    builder: (context, child) => withDeviceApprovalPrompts(child),
    home: Scaffold(body: home),
  ),
);

/// Real crypto and the mock HTTP server complete outside the fake clock.
Future<void> _settle(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Harness h;

  setUp(() async {
    h = Harness();
  });

  tearDown(() async => h.close());

  // The SDK serializes vault access per account in a process-wide queue, so
  // work a finished test left on its (discarded) fake clock would block the
  // next test on the same account forever: each test gets its own account.
  var run = 0;
  late String laptopName;
  late String phoneName;

  Future<void> twoDevices(WidgetTester tester) => tester.runAsync(() async {
    run++;
    laptopName = 'alice$run';
    phoneName = 'alice$run-phone';
    await h.e(laptopName).initialize();
    h.client(phoneName, user: laptopName);
    await h.e(phoneName).initialize();
  });

  testWidgets('a pending device shows its code, then confirms the approval '
      'before it can read', (tester) async {
    await twoDevices(tester);
    final phone = h.e(phoneName);
    expect(phone.setup, PrivateChatSetup.pending);
    final code = (await tester.runAsync(phone.linkCode))!;

    await tester.pumpWidget(_app(phone, const PrivateChatSetupBanner()));
    await _settle(tester);
    expect(find.textContaining('can’t be read on this device'), findsOneWidget);

    await tester.tap(find.text('Set up'));
    await _settle(tester);
    expect(find.text('Set up encrypted chats'), findsOneWidget);
    expect(find.text(code), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);
    expect(find.text('Codes match'), findsNothing);

    // Approved elsewhere: the keys are staged, not used, until the user
    // confirms the code here too.
    await tester.runAsync(() async {
      final laptop = h.e(laptopName);
      final device = (await laptop.listDevices()).firstWhere(
        (d) => d.status == EncryptionDeviceStatus.pending,
      );
      expect(await laptop.linkCodeFor(device), code);
      await laptop.approveDevice(device.deviceId);
      await phone.checkApproval();
    });
    await _settle(tester);
    expect(phone.setup, PrivateChatSetup.approved);
    expect(find.text('Codes match'), findsOneWidget);
    expect(find.text(code), findsOneWidget);

    await tester.tap(find.text('Codes match'));
    await _settle(tester, rounds: 20);
    expect(phone.setup, PrivateChatSetup.active);
    expect(find.text('Set up encrypted chats'), findsNothing);
    expect(find.textContaining('can’t be read on this device'), findsNothing);
  });

  testWidgets('rejecting a mismatched code keeps the device unable to read', (
    tester,
  ) async {
    await twoDevices(tester);
    final phone = h.e(phoneName);
    final firstCode = (await tester.runAsync(phone.linkCode))!;
    await tester.runAsync(() async {
      final laptop = h.e(laptopName);
      final device = (await laptop.listDevices()).firstWhere(
        (d) => d.status == EncryptionDeviceStatus.pending,
      );
      await laptop.linkCodeFor(device);
      await laptop.approveDevice(device.deviceId);
      await phone.checkApproval();
    });
    expect(phone.setup, PrivateChatSetup.approved);

    await tester.pumpWidget(_app(phone, const PrivateChatSetupBanner()));
    await _settle(tester);
    await tester.tap(find.text('Confirm'));
    await _settle(tester);
    await tester.tap(find.text('It showed a different code'));
    await _settle(tester, rounds: 20);

    expect(phone.setup, PrivateChatSetup.pending);
    // A fresh registration: the screen shows a new code, not the old one.
    // (Read from the screen — a real-time call here would queue behind the
    // re-registration still running on the test clock.)
    final shown = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((t) => t.data)
        .whereType<String>()
        .where((t) => RegExp(r'^\d{4} \d{4} \d{4} \d{4}$').hasMatch(t))
        .toList();
    expect(shown, hasLength(1));
    expect(shown.single, isNot(firstCode));
    expect(find.text('Codes match'), findsNothing);
  });

  testWidgets('an approved device is prompted with the same code and can '
      'approve the new one', (tester) async {
    await twoDevices(tester);
    final laptop = h.e(laptopName);
    final phone = h.e(phoneName);
    // Read before the banner starts its own (fake-clock) work on the same
    // account's serialized vault queue.
    final code = (await tester.runAsync(phone.linkCode))!;

    await tester.pumpWidget(_app(laptop, const SizedBox.shrink()));
    await _settle(tester, rounds: 20);
    expect(
      find.text('Let “Device $phoneName” read your encrypted chats?'),
      findsOneWidget,
    );
    expect(find.text(code), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await _settle(tester, rounds: 20);
    expect(find.textContaining('read your encrypted chats?'), findsNothing);

    // Checked on the server rather than through the phone's SDK: a real-time
    // call on this account would queue behind the banner's test-clock work.
    final row = h.server.users[laptopName]!.devices.values
        .where((d) => d['name'] == 'Device $phoneName')
        .single;
    expect(row['status'], 'active');
  });

  testWidgets('declining removes the request', (tester) async {
    await twoDevices(tester);
    final laptop = h.e(laptopName);

    await tester.pumpWidget(_app(laptop, const SizedBox.shrink()));
    await _settle(tester, rounds: 20);
    await tester.tap(find.text('Decline'));
    await _settle(tester, rounds: 20);

    expect(find.textContaining('read your encrypted chats?'), findsNothing);
  });

  testWidgets('the approval overlay keeps the app full-size under loose '
      'constraints', (tester) async {
    // The app shell hands this host loose constraints; a non-positioned child
    // in its Stack once collapsed the whole app to 0×0.
    const app = Key('app');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [privateChatEncryptionProvider.overrideWithValue(null)],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: withDeviceApprovalPrompts(
              const ColoredBox(key: app, color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(app)), const Size(800, 600));
  });
}
