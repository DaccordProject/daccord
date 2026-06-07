import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/hive.dart';
import 'package:bonfire/features/notifications/controllers/notification.dart';
import 'package:bonfire/features/notifications/controllers/sound.dart';
import 'package:bonfire/features/profiles/views/app_restart.dart';
import 'package:bonfire/features/profiles/views/profile_gate.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/developer/controllers/mcp_server_controller.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/router/controller.dart';
import 'package:bonfire/theme/app_theme.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_size/flutter_keyboard_size.dart';
import 'package:hive_ce/hive.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:bonfire/shared/utils/web_utils/web_utils.dart'
    if (dart.library.io) 'package:bonfire/shared/utils/web_utils/non_web_utils.dart';

void main() async {
  debugPrint("Starting app...");

  // #68: on Linux, make livekit_client *leak* native WebRTC resources instead of
  // freeing them on disconnect. Freeing the native MediaStreamTrack / audio
  // source / PeerConnection tears down state inside the prebuilt libwebrtc.so
  // that heap-corrupts on Linux (use-after-free in the PulseAudio capture thread;
  // "corrupted size vs. prev_size" on PeerConnection dispose), crashing the app
  // on every voice channel leave/switch. The leak is bounded per session and
  // reclaimed by the OS at process exit — a far better trade than a hard crash.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    lk.kLiveKitSkipNativeRelease = true;
  }

  _silenceFlutterWebrtcStreamCancelNoise();
  _silenceLiveKitAsyncErrors();

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

  runApp(
    const AppRestart(
      child: ProviderScope(
        child: MaterialApp(home: ProfileGate(child: MainWindow())),
      ),
    ),
  );
}

/// flutter_webrtc throws an uncaught `PlatformException("No active stream to
/// cancel")` from inside its own EventChannel teardown when a PeerConnection's
/// event stream is cancelled after the native sink is already gone — a known
/// upstream bug that's harmless (the stream is being disposed anyway). It fires
/// on every voice disconnect / LiveKit room dispose and otherwise dumps a full
/// stack to the console each time. Swallow exactly that error and forward
/// everything else to the default handler.
void _silenceFlutterWebrtcStreamCancelNoise() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final exception = details.exception;
    if (exception is PlatformException &&
        exception.message == 'No active stream to cancel') {
      return;
    }
    previous?.call(details);
  };
}

/// The LiveKit SDK fires internal timeouts as uncaught async errors when the
/// SFU accepts the socket but never completes the join handshake — e.g.
/// `Room._onParticipantUpdateEvent` waits up to 10s for a `RoomConnectedEvent`
/// and a stalled publish raises a `TrackPublishException`. These escape to the
/// root zone (not [FlutterError.onError]) and would otherwise dump a full stack
/// on every flaky connect. We've already degraded the voice flow to stay
/// responsive (bounded connect, non-blocking media setup), so swallow exactly
/// the SDK's own [lk.LiveKitException]s here and forward everything else.
void _silenceLiveKitAsyncErrors() {
  final previous = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is lk.LiveKitException) {
      debugPrint('Swallowed LiveKit async error: $error');
      return true;
    }
    return previous?.call(error, stack) ?? false;
  };
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
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    final settings = ref.watch(settingsControllerProvider);
    // Keep the local MCP server controller alive so it starts/stops with the
    // Developer Mode + MCP settings (desktop-only; a no-op on web).
    ref.watch(mcpServerControllerProvider);
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
                    // Apply accessibility prefs app-wide: scale all text by the
                    // UI scale and honour reduced-motion. Done in the router
                    // app's builder so the override sits above every route.
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(settings.uiScale),
                        disableAnimations: settings.reducedMotion,
                      ),
                      child: child ?? const SizedBox.shrink(),
                    ),
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
