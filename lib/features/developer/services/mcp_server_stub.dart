/// Web (no `dart:io`) no-op stand-in for the local MCP server.
///
/// The MCP server is desktop-only (it binds a loopback TCP socket); on web this
/// class satisfies the same surface as the real [McpServer] but does nothing.
library;

import 'package:bonfire/features/developer/services/mcp_tools.dart';

class McpServer {
  McpServer({
    required McpTools tools,
    required String Function() tokenGetter,
    required List<String> Function() allowedGroupsGetter,
    required void Function(McpActivity) onActivity,
    String appVersion = '0.0.0',
  });

  bool get isListening => false;

  Future<bool> start(int port) async => false;

  Future<void> stop() async {}
}
