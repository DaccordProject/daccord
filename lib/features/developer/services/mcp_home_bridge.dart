/// Web-safe bridge between the MCP tools layer and the live [AccordHomeScreen].
///
/// Navigation tools (the `navigate` group) need to drive UI that only the home
/// screen owns — selecting a space/channel tab, opening dialogs, toggling the
/// member list. The home screen registers a set of handler closures here when it
/// mounts and clears them when it unmounts. A reader callback exposes the home
/// screen's latest rendered state to the `read` group's `get_current_state` tool
/// without duplicating it.
///
/// This file deliberately has no `dart:io`/Flutter-widget dependency beyond the
/// closures it stores, so it is safe to import on web (where the MCP server
/// itself is a no-op).
library;

/// A navigation handler. Receives an argument map (already enriched by the tools
/// layer, e.g. with a resolved `server_key`/`space_id`) and returns the MCP
/// result map (`{ok: true, ...}` or `{error: ...}`).
typedef McpNavHandler =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> args);

typedef McpHomeState = ({
  String? spaceId,
  String? channelId,
  bool memberListVisible,
});

typedef McpHomeStateReader = McpHomeState Function();

/// Singleton wiring point. The home screen registers handlers; the MCP tools
/// layer invokes them.
class McpHomeBridge {
  final Map<String, McpNavHandler> _handlers = {};
  McpHomeStateReader? _stateReader;

  McpHomeState get state =>
      _stateReader?.call() ??
      (spaceId: null, channelId: null, memberListVisible: true);

  /// True once the home screen has registered its handlers.
  bool get isMounted => _handlers.isNotEmpty;

  /// Registers (or replaces) all navigation handlers. Called by the home screen
  /// in `initState`.
  void registerAll(Map<String, McpNavHandler> handlers) {
    _handlers
      ..clear()
      ..addAll(handlers);
  }

  /// Uses the home screen's latest rendered state without keeping a second,
  /// independently-mutated copy in this bridge.
  void setStateReader(McpHomeStateReader reader) {
    _stateReader = reader;
  }

  /// Clears every handler and the state reader. Called by the home screen in
  /// `dispose`.
  void clear() {
    _handlers.clear();
    _stateReader = null;
  }

  /// Invokes the [action] handler, or returns an error result when the home
  /// screen isn't mounted / doesn't support it.
  Future<Map<String, dynamic>> invoke(
    String action,
    Map<String, dynamic> args,
  ) async {
    final handler = _handlers[action];
    if (handler == null) {
      return {'error': 'Navigation unavailable: home screen not mounted'};
    }
    return handler(args);
  }
}

/// Process-wide bridge instance.
final McpHomeBridge mcpHomeBridge = McpHomeBridge();
