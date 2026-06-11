import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:universal_platform/universal_platform.dart';

part 'background_connection.g.dart';

/// Starts/stops the Android foreground service (`BackgroundConnectionService`)
/// that exempts the app process from Android's cached-app freezer while
/// backgrounded, so the gateway sockets stay alive and mention notifications
/// keep firing. The service holds no logic of its own — keeping the process
/// unfrozen is the whole job.
///
/// Mirrors the MCP server controller pattern: kept alive by a `ref.watch` in
/// `MainWindow`, reacting to the persisted "Background connection" setting and
/// the login state. A no-op on every platform but Android.
@Riverpod(keepAlive: true)
class BackgroundConnectionController extends _$BackgroundConnectionController {
  static const _channel = MethodChannel(
    'com.daccord.app/background_connection',
  );

  bool _running = false;

  @override
  void build() {
    if (!UniversalPlatform.isAndroid) return;
    final enabled = ref.watch(
      settingsControllerProvider.select((s) => s.backgroundConnection),
    );
    final loggedIn = ref.watch(
      accordAuthProvider.select((s) => s is AccordAuthLoggedIn),
    );
    _apply(enabled && loggedIn);
  }

  Future<void> _apply(bool shouldRun) async {
    if (shouldRun == _running) return;
    _running = shouldRun;
    try {
      await _channel.invokeMethod<void>(shouldRun ? 'start' : 'stop');
    } catch (e) {
      // Roll back so the next build retries instead of believing the lie.
      _running = !shouldRun;
      debugPrint(
        'BackgroundConnectionService ${shouldRun ? 'start' : 'stop'} failed: $e',
      );
    }
  }
}
