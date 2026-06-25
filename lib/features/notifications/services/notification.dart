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

/// Initializes local notifications for every supported platform. No-ops on web
/// (the plugin is unsupported there).
Future<void> initializeNotifications() async {
  if (UniversalPlatform.isWeb) return;

  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('app_icon'),
    iOS: DarwinInitializationSettings(),
    macOS: DarwinInitializationSettings(),
    linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    windows: WindowsInitializationSettings(
      appName: 'Daccord',
      appUserModelId: 'com.daccord.app',
      guid: 'd74fd681-d4f2-4320-9820-4395f4226dce',
    ),
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  final androidPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(_androidChannel);
  // Android 13+ gates notifications behind a runtime permission; without this
  // request nothing the app posts (mentions, the background-connection
  // service's status notification) is ever shown.
  await androidPlugin?.requestNotificationsPermission();

  _initialized = true;
}

/// Shows a single mention notification with [title] and [body]. Safe to call on
/// any platform — no-ops on web or before [initializeNotifications].
Future<void> showMentionNotification({
  required String title,
  required String body,
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

  // A rolling id keeps successive notifications from overwriting each other.
  final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
  await flutterLocalNotificationsPlugin.show(id, title, body, details);
}
