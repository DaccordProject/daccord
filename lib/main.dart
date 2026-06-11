import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/hive.dart';
import 'package:bonfire/features/notifications/controllers/background_connection.dart';
import 'package:bonfire/features/notifications/controllers/notification.dart';
import 'package:bonfire/features/notifications/controllers/sound.dart';
import 'package:bonfire/features/profiles/views/app_restart.dart';
import 'package:bonfire/features/profiles/views/profile_gate.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/developer/controllers/mcp_server_controller.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/error_reporting/controllers/error_reporting.dart';
import 'package:bonfire/router/controller.dart';
import 'package:bonfire/shared/utils/desktop_window.dart';
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

  // Local storage must be ready before the widget tree reads its boxes, so this
  // stays awaited — but guard it. A throw here (e.g. a corrupt Hive box) would
  // otherwise abort main() before runApp(), so the OS never gets a first frame
  // and the launch splash hangs forever with nothing surfaced. Catching lets
  // the UI render and report instead of silently sticking on the splash.
  try {
    await setupHive();
  } catch (e, st) {
    debugPrint('setupHive failed during startup: $e\n$st');
  }

  // Restore the last desktop window size/position before the first frame
  // (no-op on web/mobile). Guarded so a window-manager failure can't block
  // startup.
  try {
    await setupDesktopWindow();
  } catch (e, st) {
    debugPrint('setupDesktopWindow failed during startup: $e\n$st');
  }

  runApp(
    const AppRestart(
      child: ProviderScope(
        child: MaterialApp(home: ProfileGate(child: MainWindow())),
      ),
    ),
  );

  // Non-critical platform init runs *after* the first frame so a slow or
  // throwing platform channel can never block startup. This is the failure mode
  // that stuck Windows (#70) and Android on the launch splash: main() awaited
  // initializeNotifications() before runApp(), so one plugin throw hung the app.
  unawaited(_initBackgroundServices());
}

/// Best-effort init for services the UI doesn't need to render its first frame.
/// Each step is isolated so one failing plugin can't take down the others — or
/// startup. Both call sites already no-op until their service is initialized.
Future<void> _initBackgroundServices() async {
  try {
    await initializeNotifications();
  } catch (e, st) {
    debugPrint('initializeNotifications failed: $e\n$st');
  }
  try {
    soundManager.init();
  } catch (e, st) {
    debugPrint('soundManager.init failed: $e\n$st');
  }
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
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Mobile OSes freeze the process while backgrounded: heartbeats stop, the
    // gateway sockets die, and the automatic reconnect budget can burn out
    // before the user comes back. Verify/revive every connection on resume.
    _lifecycle = AppLifecycleListener(
      onResume: () =>
          ref.read(accordAuthProvider.notifier).ensureConnectedAll(),
    );
    _initDeepLinks();
    // Every route change becomes an error-reporting breadcrumb (a no-op until
    // the user opts in).
    routerController.routerDelegate.addListener(_onRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowErrorReportingConsent(),
    );
  }

  @override
  void dispose() {
    routerController.routerDelegate.removeListener(_onRouteChanged);
    _lifecycle?.dispose();
    _linkSub?.cancel();
    super.dispose();
  }

  void _onRouteChanged() {
    final path = routerController.routerDelegate.currentConfiguration.uri.path;
    ref
        .read(errorReportingControllerProvider.notifier)
        .addBreadcrumb('Navigated: $path', 'navigation');
  }

  /// First-launch error-reporting consent, mirroring the reference client's
  /// `main_window._show_consent_dialog`: asked once, never reshown (answering
  /// — or toggling the switch in Settings — stamps the preference).
  Future<void> _maybeShowErrorReportingConsent() async {
    if (ref.read(settingsControllerProvider).errorReportingConsentShown) {
      return;
    }
    // Give the router a moment to mount its navigator so the dialog has a
    // context to attach to.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    if (ref.read(settingsControllerProvider).errorReportingConsentShown) {
      return;
    }
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final enable = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Help improve daccord'),
        content: const Text(
          'Help improve daccord by sending anonymous crash and error '
          'reports? No personal data is included. You can change this in '
          'Settings at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('No thanks'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    ref
        .read(settingsControllerProvider.notifier)
        .setErrorReportingEnabled(enable == true);
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
    // Keep the Android background-connection service in sync with its setting
    // and the login state (a no-op everywhere but Android).
    ref.watch(backgroundConnectionControllerProvider);
    // Keep opt-in error reporting alive; it activates/deactivates with the
    // persisted consent toggle.
    ref.watch(errorReportingControllerProvider);
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
