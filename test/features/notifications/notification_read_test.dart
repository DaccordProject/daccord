import 'dart:async';

import 'package:bonfire/features/notifications/services/notification.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  Completer<void>? delivery;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'show') await delivery?.future;
          return true;
        });
    await initializeNotifications();
    calls.clear();
  });
  tearDown(() async {
    delivery = null;
    for (final key in ['a', 'b']) {
      await dismissReadNotifications(serverKey: key, channelId: 'channel');
    }
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> show(String key, String id) => showMentionNotification(
    title: 'Mention',
    body: 'Hello',
    serverKey: key,
    channelId: 'channel',
    messageId: id,
  );

  test(
    'reading dismisses only older notifications on the matching server',
    () async {
      await show('a', '9');
      await show('a', '10');
      await show('b', '9');
      final shown = calls.where((call) => call.method == 'show').toList();
      final ids = shown.map((call) => (call.arguments as Map)['id']).toList();
      expect(ids.toSet().length, 3);
      calls.clear();
      await dismissReadNotifications(
        serverKey: 'a',
        channelId: 'channel',
        messageId: '9',
      );
      expect(
        calls
            .where((call) => call.method == 'cancel')
            .map((call) => (call.arguments as Map)['id']),
        [ids.first],
      );
    },
  );

  test(
    'a read racing notification delivery still removes the banner',
    () async {
      delivery = Completer<void>();
      final showing = show('a', '20');
      await Future<void>.delayed(Duration.zero);
      await dismissReadNotifications(
        serverKey: 'a',
        channelId: 'channel',
        messageId: '20',
      );
      delivery!.complete();
      await showing;
      expect(calls.where((call) => call.method == 'cancel').length, 2);
    },
  );
}
