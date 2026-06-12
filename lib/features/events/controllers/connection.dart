import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection.g.dart';

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
  /// The server is responding, making its first connection attempt, or in the
  /// initial disconnected state before any attempt has been made — UI waiting
  /// on data should keep showing a loading spinner.
  bool get isReachable =>
      this == ConnectionStatus.disconnected ||
      this == ConnectionStatus.connecting ||
      this == ConnectionStatus.connected ||
      this == ConnectionStatus.ready;

  /// The gateway has dropped and is cycling reconnect attempts, or has exhausted
  /// them — the server is effectively unreachable. UI that is still waiting on
  /// data should show an "unreachable" message instead of an endless spinner.
  bool get isUnreachable => !isReachable;
}

/// Exposes the current [ConnectionStatus] to the UI (e.g. a connecting banner).
@Riverpod(keepAlive: true)
class ConnectionController extends _$ConnectionController {
  @override
  ConnectionStatus build() => ConnectionStatus.disconnected;

  void set(ConnectionStatus status) => state = status;
}
