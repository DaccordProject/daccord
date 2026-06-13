import 'dart:async';
import 'dart:ui';

import 'package:bonfire/features/error_reporting/repositories/glitchtip_client.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'error_reporting.g.dart';

/// GlitchTip DSN baked into the build. Overridable at build time with
/// `--dart-define=SENTRY_DSN=...` (release.yml injects the `SENTRY_DSN`
/// secret); the dev DSN stays in the repo for local testing, mirroring the
/// reference client's `project.godot` setup.
const String kDefaultGlitchTipDsn =
    'https://f7c1b4791bdc42daac0b6411d41c8c4f@crash.daccord.gg/2';

const String _envSentryDsn = String.fromEnvironment('SENTRY_DSN');

String resolveGlitchTipDsn() =>
    _envSentryDsn.isEmpty ? kDefaultGlitchTipDsn : _envSentryDsn;

/// Redacts tokens and server URLs from [msg] before anything leaves the
/// device — the same patterns as the reference client's
/// `ErrorReporting.scrub_pii_text`: Bearer tokens, `token=` query params,
/// `dk_…` hex tokens, bare 64-char hex strings, and URLs with explicit ports.
String scrubPiiText(String msg) {
  var out = msg;
  out = out.replaceAll(
    RegExp(r'Bearer\s+[A-Za-z0-9._\-]+'),
    'Bearer [REDACTED]',
  );
  out = out.replaceAll(RegExp('token=[^&\\s"\']+'), 'token=[REDACTED]');
  out = out.replaceAll(RegExp(r'dk_[0-9a-fA-F]{8,}'), '[TOKEN REDACTED]');
  out = out.replaceAll(RegExp(r'\b[0-9a-fA-F]{64}\b'), '[TOKEN REDACTED]');
  out = out.replaceAll(
    RegExp('https?://[^\\s"\']+:\\d{2,5}[^\\s"\']*'),
    '[URL REDACTED]',
  );
  return out;
}

/// Opt-in error reporting to a self-hosted GlitchTip (Sentry-compatible)
/// instance. Port of the reference client's `error_reporting.gd` autoload:
/// nothing is initialized — and no network request ever happens — until the
/// user enables [AccordSettings.errorReportingEnabled] (first-launch consent
/// dialog or the settings toggle). State is whether reporting is active.
///
/// Once active it also captures unhandled [FlutterError]s and uncaught async
/// errors, scrubbed through [scrubPiiText]. Breadcrumbs (navigation, message
/// sent, voice errors) carry structural IDs only — never content.
@Riverpod(keepAlive: true)
class ErrorReportingController extends _$ErrorReportingController {
  /// Client the process-wide error hooks report through; null while reporting
  /// is disabled. Static because [FlutterError.onError] is process-wide and
  /// installed once.
  static GlitchTipClient? _active;
  static bool _hooksInstalled = false;

  GlitchTipClient? _client;

  @override
  bool build() {
    final enabled = ref.watch(
      settingsControllerProvider.select((s) => s.errorReportingEnabled),
    );
    if (!enabled) {
      _client = null;
      _active = null;
      return false;
    }
    final created = GlitchTipClient();
    if (!created.init(resolveGlitchTipDsn())) {
      _client = null;
      _active = null;
      return false;
    }
    _client = created;
    _active = created;
    _installGlobalHooks();
    // Navigation breadcrumbs: react to the persisted selection changing rather
    // than having SettingsController push to us (that would form a dependency
    // cycle, since we watch settings above). IDs are truncated before they
    // leave the device.
    ref.listen(settingsControllerProvider.select((s) => s.lastSpaceId), (
      prev,
      next,
    ) {
      if (next.isNotEmpty && next != prev) spaceSelected(next);
    });
    ref.listen(settingsControllerProvider.select((s) => s.lastChannelId), (
      prev,
      next,
    ) {
      if (next.isNotEmpty && next != prev) channelSelected(next);
    });
    // If this provider is torn down (e.g. container disposal) the global
    // hooks must stop reporting through the dead client and its HTTP pool
    // must be released.
    ref.onDispose(() {
      if (identical(_active, created)) _active = null;
      created.close();
    });
    return true;
  }

  /// The `event_id` of the last sent event ('' when none / disabled).
  String get lastEventId => _client?.lastEventId ?? '';

  /// Records a PII-scrubbed breadcrumb; no-op while reporting is disabled.
  void addBreadcrumb(String message, String category) {
    _client?.addBreadcrumb(scrubPiiText(message), category);
  }

  void spaceSelected(String spaceId) =>
      addBreadcrumb('Switched space: ${_truncateId(spaceId)}', 'navigation');

  void channelSelected(String channelId) =>
      addBreadcrumb('Opened channel: ${_truncateId(channelId)}', 'navigation');

  /// Breadcrumbs the fact a message was sent — never its content.
  void messageSent() => addBreadcrumb('Sent message', 'action');

  void voiceError(String error) =>
      addBreadcrumb('Voice error: $error', 'voice');

  /// Refreshes the context tags (server count, truncated space/channel IDs)
  /// attached to subsequent events.
  void updateContext() {
    final client = _client;
    if (client == null) return;
    final connections = ref.read(connectionsControllerProvider);
    client.setTag('server_count', '${connections.connections.length}');
    final settings = ref.read(settingsControllerProvider);
    if (settings.lastSpaceId.isNotEmpty) {
      client.setTag('space_id', _truncateId(settings.lastSpaceId));
    }
    if (settings.lastChannelId.isNotEmpty) {
      client.setTag('channel_id', _truncateId(settings.lastChannelId));
    }
  }

  /// Sends a user-initiated problem report as a `type=user-feedback` tagged
  /// INFO event (GlitchTip has no Sentry feedback envelope API). No-op while
  /// reporting is disabled.
  Future<void> reportProblem(String description) async {
    final client = _client;
    if (client == null) return;
    updateContext();
    client.setTag('type', 'user-feedback');
    try {
      await client.captureMessage(scrubPiiText(description));
    } finally {
      // Remove the temporary tag so it doesn't bleed into subsequent
      // auto-captured error events.
      client.removeTag('type');
    }
  }

  /// IDs are truncated to their last 4 chars so events can be correlated
  /// without identifying the space/channel.
  static String _truncateId(String id) =>
      id.length <= 4 ? id : '…${id.substring(id.length - 4)}';

  /// Wraps the process-wide error handlers exactly once, chaining to whatever
  /// was installed before (main.dart's LiveKit/WebRTC noise filters keep
  /// working). Capture itself is a no-op while [_active] is null, so consent
  /// can be toggled without re-wrapping.
  static void _installGlobalHooks() {
    if (_hooksInstalled) return;
    _hooksInstalled = true;
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _captureGlobal(details.exception, details.stack);
      previousOnError?.call(details);
    };
    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _captureGlobal(error, stack);
      return previousPlatformOnError?.call(error, stack) ?? false;
    };
  }

  static void _captureGlobal(Object error, StackTrace? stack) {
    final client = _active;
    if (client == null) return;
    try {
      unawaited(
        client.captureError(
          scrubPiiText(error.toString()),
          stack: stack == null ? '' : scrubPiiText(stack.toString()),
        ),
      );
    } catch (_) {
      // Never let reporting an error raise another one.
    }
  }
}
