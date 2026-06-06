/// Conditional-export facade for the local MCP server.
///
/// On platforms with `dart:io` (desktop) this resolves to the real
/// [McpServer] in `mcp_server_io.dart`; on web it resolves to the no-op in
/// `mcp_server_stub.dart`. Callers import this file only.
library;

export 'mcp_server_stub.dart' if (dart.library.io) 'mcp_server_io.dart';
