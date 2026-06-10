import 'dart:async';

import 'package:accordkit/accordkit.dart';

/// A [GatewayConnection] driven by tests: push inbound frames with [receive],
/// inspect outbound frames via [sent], and simulate closure with [simulateClose].
class FakeGatewayConnection implements GatewayConnection {
  final String url;
  final _messages = StreamController<String>();
  final Completer<void> _ready = Completer<void>();

  /// JSON strings sent by the socket.
  final List<String> sent = [];

  @override
  int? closeCode;
  @override
  String? closeReason;

  bool readyImmediately;

  FakeGatewayConnection(this.url, {this.readyImmediately = true}) {
    if (readyImmediately && !_ready.isCompleted) {
      _ready.complete();
    }
  }

  /// Completes the [ready] future (when [readyImmediately] was false).
  void markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  /// Pushes an inbound frame to the socket.
  void receive(String text) => _messages.add(text);

  /// Simulates the connection closing with the given code/reason.
  void simulateClose(int code, [String reason = '']) {
    closeCode = code;
    closeReason = reason;
    if (!_messages.isClosed) _messages.close();
  }

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  void sendText(String text) => sent.add(text);

  @override
  Future<void> close([int? code, String? reason]) async {
    if (code != null) closeCode = code;
    if (reason != null) closeReason = reason;
    if (!_messages.isClosed) await _messages.close();
  }
}

/// Creates a connection factory that hands out [FakeGatewayConnection]s and
/// records each one created (so tests can drive reconnect scenarios).
class FakeConnectionFactory {
  final List<FakeGatewayConnection> connections = [];
  bool readyImmediately;

  FakeConnectionFactory({this.readyImmediately = true});

  FakeGatewayConnection get last => connections.last;

  GatewayConnection call(String url) {
    final conn = FakeGatewayConnection(url, readyImmediately: readyImmediately);
    connections.add(conn);
    return conn;
  }
}
