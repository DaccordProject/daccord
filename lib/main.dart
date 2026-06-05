import 'package:bonfire/features/authentication/utils/hive.dart';
import 'package:bonfire/features/notifications/controllers/notification.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/router/controller.dart';
import 'package:bonfire/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_size/flutter_keyboard_size.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:bonfire/shared/utils/web_utils/web_utils.dart'
    if (dart.library.io) 'package:bonfire/shared/utils/web_utils/non_web_utils.dart';

void main() async {
  debugPrint("Starting app...");

  initializePlatform();

  VideoPlayerMediaKit.ensureInitialized(
    android: true,
    iOS: true,
    macOS: true,
    windows: true,
    linux: true,
    web: true,
  );

  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [SystemUiOverlay.top],
  );

  await setupHive();
  await initializeNotifications();

  runApp(const ProviderScope(
    child: MaterialApp(
      home: MainWindow(),
    ),
  ));
}

class MainWindow extends ConsumerStatefulWidget {
  const MainWindow({super.key});

  @override
  ConsumerState<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends ConsumerState<MainWindow> {
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ));

    final settings = ref.watch(settingsControllerProvider);
    final theme = buildAppTheme(
      settings.themePreset,
      accent: settings.accentColor == null
          ? null
          : Color(settings.accentColor!),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Column(
            children: [
              Flexible(
                child: KeyboardSizeProvider(
                  child: MaterialApp.router(
                    title: 'Daccord',
                    theme: theme,
                    darkTheme: theme,
                    routerConfig: routerController,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
