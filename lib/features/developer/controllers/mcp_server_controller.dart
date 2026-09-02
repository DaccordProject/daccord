import 'package:bonfire/features/developer/services/mcp_server.dart';
import 'package:bonfire/features/developer/services/mcp_tools.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/app_info.dart';
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

  /// Most-recent tool calls, oldest first (capped to [_McpServerControllerCap]).
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

/// Owns the desktop-only local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags. The server runs only while Developer Mode **and**
/// the MCP toggle are both on (mirroring the reference client's two-step
/// opt-in); it restarts when the port changes. The bearer token and allowed
/// tool groups are read live by the server, so changing those takes effect
/// without a restart.
///
/// The desktop-only part is enforced here rather than assumed: [McpServer]
/// resolves to the real `dart:io` implementation on *any* platform with
/// `dart:library.io` — which includes iOS and Android — so without this gate a
/// persisted `developerMode` flag would start a real HTTP listener on a phone or
/// inside a store build. [isDeveloperModeAvailable] is the single source of
/// truth, shared with the settings UI that offers the toggle.
///
/// On web (no `dart:io`) the [McpServer] facade is a no-op, so this controller
/// is inert there too.
@Riverpod(keepAlive: true)
class McpServerController extends _$McpServerController {
  McpServer? _server;
  McpTools? _tools;
  final List<McpActivity> _activity = [];
  bool _running = false;
  int _runningPort = 0;

  @override
  McpServerState build() {
    final settings = ref.watch(settingsControllerProvider);
    final shouldRun =
        isDeveloperModeAvailable &&
        settings.developerMode &&
        settings.mcpEnabled &&
        settings.mcpToken.trim().isNotEmpty;
    final port = settings.mcpPort;
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
