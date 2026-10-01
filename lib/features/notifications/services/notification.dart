import 'package:bonfire/features/channels/utils/message_position.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:universal_platform/universal_platform.dart';

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

const _androidChannel = AndroidNotificationChannel(
  'mentions',
  'Mentions',
  description: 'Notifications for messages that mention you.',
  importance: Importance.high,
  playSound: true,
);

bool _initialized = false;
bool _permissionRequested = false;
int _nextNotificationId = DateTime.now().millisecondsSinceEpoch.remainder(
  100000,
);
final _messageNotifications =
    <int, ({String serverKey, String channelId, String messageId})>{};

/// Remove delivered banners when this channel is read here or on another device.
Future<void> dismissReadNotifications({
  required String serverKey,
  required String channelId,
  String? messageId,
}) async {
  final ids = _messageNotifications.entries
      .where(
        (entry) =>
            entry.value.serverKey == serverKey &&
            entry.value.channelId == channelId &&
            (messageId == null ||
                compareMessageIds(entry.value.messageId, messageId) <= 0),
      )
      .map((entry) => entry.key)
      .toList();
  for (final id in ids) {
    _messageNotifications.remove(id);
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (error) {
      debugPrint('Failed to dismiss notification: $error');
    }
  }
}

/// Initializes local notifications for every supported platform. No-ops on web
/// (the plugin is unsupported there).
///
/// Deliberately asks for **no** permission: init runs from `main()` before
/// sign-in, and an OS alert over the terms gate falls foul of App Review
/// (guideline 1.2). [requestNotificationPermissions] asks once an account is
/// connected.
Future<void> initializeNotifications() async {
  if (UniversalPlatform.isWeb) return;

  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('app_icon'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
    macOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
    linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    windows: WindowsInitializationSettings(
      appName: 'Daccord',
      appUserModelId: 'com.daccord.app',
      guid: 'd74fd681-d4f2-4320-9820-4395f4226dce',
    ),
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await androidPlugin?.createNotificationChannel(_androidChannel);

  _initialized = true;
}

/// Asks the OS for permission to post notifications, once per app run. Called
/// when a server connection is established, not at startup (see
/// [initializeNotifications]).
///
/// No-ops on web, before [initializeNotifications], and on repeat calls; the
/// OS itself only prompts once per install.
Future<void> requestNotificationPermissions() async {
  if (UniversalPlatform.isWeb || !_initialized || _permissionRequested) return;
  _permissionRequested = true;

  try {
    // Android 13+ gates notifications behind a runtime permission; without this
    // request nothing the app posts (mentions, the background-connection
    // service's status notification) is ever shown.
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  } catch (error, stackTrace) {
    // A denied or unavailable permission must never take down a sign-in.
    debugPrint('requestNotificationPermissions failed: $error\n$stackTrace');
  }
}

/// Shows a single mention notification with [title] and [body]. Safe to call on
/// any platform — no-ops on web or before [initializeNotifications].
Future<void> showMentionNotification({
  required String title,
  required String body,
  required String serverKey,
  required String channelId,
  required String messageId,
}) async {
  if (UniversalPlatform.isWeb || !_initialized) return;

  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'mentions',
      'Mentions',
      channelDescription: 'Notifications for messages that mention you.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
  );

  final id = _nextNotificationId++;
  _messageNotifications[id] = (
    serverKey: serverKey,
    channelId: channelId,
    messageId: messageId,
  );
  try {
    await flutterLocalNotificationsPlugin.show(id, title, body, details);
    // A read event may race the platform's asynchronous delivery.
    if (!_messageNotifications.containsKey(id)) {
      await flutterLocalNotificationsPlugin.cancel(id);
    }
  } catch (error) {
    _messageNotifications.remove(id);
    debugPrint('Failed to show notification: $error');
  }
}
