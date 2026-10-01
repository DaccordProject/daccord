import 'package:bonfire/features/developer/services/mcp_server.dart';
import 'package:bonfire/features/developer/services/mcp_tools.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mcp_server_controller.g.dart';

/// Observable status of the local MCP server.
class McpServerState {
  const McpServerState({
    this.listening = false,
    this.port = 0,
    this.activity = const [],
  });

  final bool listening;
  final int port;

  /// Most-recent tool calls, oldest first (capped to [_activityLogCap]).
  final List<McpActivity> activity;

  McpServerState copyWith({
    bool? listening,
    int? port,
    List<McpActivity>? activity,
  }) =>
      McpServerState(
        listening: listening ?? this.listening,
        port: port ?? this.port,
        activity: activity ?? this.activity,
      );
}

const int _activityLogCap = 100;

/// Owns the local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags: it runs only while Developer Mode **and** the
/// MCP toggle are on, and restarts when the port changes. The bearer token and
/// allowed tool groups are read live, so changing them needs no restart.
///
/// [isDeveloperModeAvailable] gates it explicitly because [McpServer] resolves
/// to the real `dart:io` listener on iOS and Android too, where a persisted
/// `developerMode` flag must not start one.
@Riverpod(keepAlive: true)
class McpServerController extends _$McpServerController {
  McpServer? _server;
  McpTools? _tools;
  final List<McpActivity> _activity = [];
  bool _running = false;
  int _runningPort = 0;

  @override
  McpServerState build() {
    // Select only the fields that drive the lifecycle so unrelated settings
    // writes don't re-run the reconcile.
    final settings = ref.watch(
      settingsControllerProvider.select(
        (s) => (
          developerMode: s.developerMode,
          mcpEnabled: s.mcpEnabled,
          hasToken: s.mcpToken.trim().isNotEmpty,
          port: s.mcpPort,
        ),
      ),
    );
    final shouldRun =
        isDeveloperModeAvailable &&
        settings.developerMode &&
        settings.mcpEnabled &&
        settings.hasToken;
    final port = settings.port;
    ref.onDispose(() {
      _server?.stop();
      _server = null;
      _running = false;
    });
    // Reconcile asynchronously so we never mutate `state` during build.
    Future.microtask(() => _reconcile(shouldRun, port));
    return McpServerState(
      listening: _running,
      port: port,
      activity: List.unmodifiable(_activity),
    );
  }

  Future<void> _reconcile(bool shouldRun, int port) async {
    if (shouldRun && (!_running || _runningPort != port)) {
      await _server?.stop();
      _tools ??= McpTools(ref);
      _server = McpServer(
        tools: _tools!,
        tokenGetter: () => ref.read(settingsControllerProvider).mcpToken,
        allowedGroupsGetter: () =>
            ref.read(settingsControllerProvider).mcpAllowedGroups,
        onActivity: _onActivity,
      );
      final ok = await _server!.start(port);
      _running = ok && _server!.isListening;
      _runningPort = port;
      state = state.copyWith(listening: _running, port: port);
    } else if (!shouldRun && _running) {
      await _server?.stop();
      _server = null;
      _running = false;
      state = state.copyWith(listening: false);
    }
  }

  void _onActivity(McpActivity activity) {
    _activity.add(activity);
    if (_activity.length > _activityLogCap) _activity.removeAt(0);
    state = state.copyWith(activity: List.unmodifiable(_activity));
  }

  /// Clears the in-memory activity log.
  void clearActivity() {
    _activity.clear();
    state = state.copyWith(activity: const []);
  }
}
