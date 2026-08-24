/// Lifecycle of the Accord gateway connection, driven by the gateway streams
/// in `accord_event_handler.dart`.
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  ready,
  reconnecting,
}

extension ConnectionStatusReachability on ConnectionStatus {
  /// The server is responding, or making its first connection attempt — UI that
  /// is waiting on data should keep showing a loading spinner.
  bool get isReachable =>
      this == ConnectionStatus.connecting ||
      this == ConnectionStatus.connected ||
      this == ConnectionStatus.ready;

  /// The gateway has dropped and is cycling reconnect attempts, or has exhausted
  /// them — the server is effectively unreachable. UI that is still waiting on
  /// data should show an "unreachable" message instead of an endless spinner.
  bool get isUnreachable => !isReachable;
}
