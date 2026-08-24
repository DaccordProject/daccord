import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/hive.dart';
import 'package:bonfire/features/notifications/controllers/background_connection.dart';
import 'package:bonfire/features/notifications/services/notification.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/notifications/services/taskbar_badge.dart';
import 'package:bonfire/features/onboarding/views/onboarding_tour.dart';
import 'package:bonfire/features/updates/views/release_notes_dialog.dart';
import 'package:bonfire/features/profiles/views/app_restart.dart';
import 'package:bonfire/features/profiles/views/profile_gate.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/server/services/federation_join.dart';
import 'package:bonfire/features/developer/controllers/mcp_server_controller.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/views/incoming_call_overlay.dart';
import 'package:bonfire/router/controller.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/shared/utils/desktop_window.dart';
import 'package:bonfire/theme/app_theme.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Register media_kit as package:video_player's backend everywhere except iOS.
  // iOS has no media_kit_libs_ios_video (see pubspec.yaml — libmpv's
  // fork/execve and OpenGL ES references got 0.2.6 rejected under App Store
  // guideline 2.5.1), so there is no libmpv to initialise there; video_player
  // falls through to its stock AVFoundation implementation instead.
  VideoPlayerMediaKit.ensureInitialized(
    android: true,
    iOS: false,
    macOS: true,
    windows: true,
    linux: true,
    web: true,
  );

  WidgetsFlutterBinding.ensureInitialized();

  // Load the build's version into kAppVersion before anything reads it (update
  // checker, error reporting, MCP serverInfo). Single bundled-metadata read, no
  // network; self-guarded so it can't block startup.
  await initAppInfo();

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

/// Upper bound on the combined (system × in-app) text scale. The OS can ask
/// for far more than this at the top accessibility sizes; past roughly 2× the
/// app's fixed-height rows (channel tiles, the member list, voice tiles) start
/// clipping instead of growing, so honour the user's preference up to here and
/// no further.
const double _maxEffectiveTextScale = 2.0;

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
    // First-launch walkthrough (#175). It snapshots "is this a fresh install?"
    // before sign-in persists a session, then waits for sign-in before showing
    // anything. A no-op on every later launch, and on installs that predate it.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => maybeShowOnboardingOnStartup(ref),
    );
    // Post-update "What's new" notes (#183): shown once per new version, after
    // sign-in. A no-op on a first install or an unchanged version.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => maybeShowReleaseNotesOnStartup(ref),
    );
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      switch (parsed.route) {
        case 'navigate':
          // Target an already-connected server by space id; for now just open
          // the home surface (deep space/channel selection is a follow-up).
          if (loggedIn) routerController.go('/spaces');
          break;
        case 'federate':
          // Join a space homed on a remote server through the active
          // connection. Requires being signed in (federation is server-to
          // -server); otherwise route to login.
          if (!loggedIn) {
            routerController.go('/login');
            break;
          }
          final domain = parsed.domain;
          final spaceId = parsed.spaceId;
          final client = ref.read(accordAuthProvider.notifier).client;
          if (domain == null || spaceId == null || client == null) break;
          final outcome = await joinFederatedSpace(
            ref,
            client,
            domain,
            spaceId,
          );
          if (outcome.error == null) {
            routerController.go('/spaces');
          } else {
            final ctx = rootNavigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              ScaffoldMessenger.maybeOf(
                ctx,
              )?.showSnackBar(SnackBar(content: Text(outcome.error!)));
            }
          }
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
    // Keep the Android background-connection service controller alive so the
    // foreground service starts/stops with the "Background connection" setting
    // and login state (a no-op on every other platform and on Play builds).
    ref.watch(backgroundConnectionControllerProvider);
    // Keep the desktop taskbar/dock unread badge alive so it tracks unread
    // state live, including while the window is minimised (no-op on web/mobile).
    ref.watch(taskbarBadgeControllerProvider);
    soundManager.enabled = settings.soundsEnabled;
    soundManager.volume = settings.sfxVolume;
    final theme = buildAppTheme(
      settings.themePreset,
      accent: settings.accentColor == null
          ? null
          : Color(settings.accentColor!),
    );

    return MaterialApp.router(
      title: 'Daccord',
      theme: theme,
      darkTheme: theme,
      routerConfig: routerController,
      // Apply accessibility prefs app-wide: scale all text by the UI scale and
      // honour reduced-motion. Done in the router app's builder so the
      // override sits above every route.
      // The incoming-call banner is hosted here too, above every route, so a
      // ring stays answerable from inside a dialog or the full-screen call
      // view (#139).
      builder: (context, child) {
        // Compose the in-app UI scale with the platform's own text scale (iOS
        // Dynamic Type, Android font size) instead of replacing it. Passing
        // `TextScaler.linear(uiScale)` straight through discarded whatever the
        // user had set at the OS level, so iOS "Larger Text" did nothing here —
        // the app always rendered at its own scale. Capped at
        // [_maxEffectiveTextScale] so the largest accessibility sizes can't
        // burst fixed-height rows.
        final systemScale = MediaQuery.textScalerOf(context).scale(1);
        final combined = (systemScale * settings.uiScale).clamp(
          AccordSettings.minUiScale,
          _maxEffectiveTextScale,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(combined),
            disableAnimations: settings.reducedMotion,
          ),
          child: withIncomingCallOverlay(child),
        );
      },
    );
  }
}
