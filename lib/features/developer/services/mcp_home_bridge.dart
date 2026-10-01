/// Web-safe bridge between the MCP tools layer and the live [AccordHomeScreen].
///
/// While mounted, the home screen registers the navigation handlers the
/// `navigate` tools invoke and a reader for its rendered state (the `read`
/// group's `get_current_state`). No `dart:io` or widget dependency, so it is
/// safe to import on web.
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

  /// Registers (or replaces) all navigation handlers.
  void registerAll(Map<String, McpNavHandler> handlers) {
    _handlers
      ..clear()
      ..addAll(handlers);
  }

  /// Reads the home screen's latest rendered state rather than keeping a copy.
  void setStateReader(McpHomeStateReader reader) {
    _stateReader = reader;
  }

  /// Clears every handler and the state reader.
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
