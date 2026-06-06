import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/hive.dart';
import 'package:bonfire/features/notifications/controllers/notification.dart';
import 'package:bonfire/features/notifications/controllers/sound.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/router/controller.dart';
import 'package:bonfire/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_size/flutter_keyboard_size.dart';
import 'package:hive_ce/hive.dart';

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
  soundManager.init();

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
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  /// Listens for `daccord://` deep links (cold-start and while running) and
  /// routes them through the Add-a-Server flow. Parsing mirrors the URL field
  /// in the dialog (see [ServerUri]).
  Future<void> _initDeepLinks() async {
    final links = AppLinks();
    try {
      final initial = await links.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (_) {
      // No initial link / unsupported platform.
    }
    _linkSub = links.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'daccord') return;
    final parsed = ServerUri.parseDeepLink(uri.toString());
    if (parsed == null) return;

    final loggedIn = ref.read(accordAuthProvider) is AccordAuthLoggedIn;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (parsed.route) {
        case 'navigate':
          // Target an already-connected server by space id; for now just open
          // the home surface (deep space/channel selection is a follow-up).
          if (loggedIn) routerController.go('/spaces');
          break;
        case 'connect':
        case 'invite':
          if (loggedIn) {
            final ctx = rootNavigatorKey.currentContext;
            if (ctx != null) {
              showAddServerDialog(ctx, initialUrl: uri.toString());
            }
          } else {
            final base = parsed.server?.baseUrl;
            if (base != null) {
              Hive.box('accord-session').put('last-server', base);
            }
            routerController.go('/login');
          }
          break;
      }
    });
  }

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
    soundManager.enabled = settings.soundsEnabled;
    soundManager.volume = settings.sfxVolume;
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
