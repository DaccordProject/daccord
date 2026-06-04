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

/// Exposes the current [ConnectionStatus] to the UI (e.g. a connecting banner).
@Riverpod(keepAlive: true)
class ConnectionController extends _$ConnectionController {
  @override
  ConnectionStatus build() => ConnectionStatus.disconnected;

  void set(ConnectionStatus status) => state = status;
}
