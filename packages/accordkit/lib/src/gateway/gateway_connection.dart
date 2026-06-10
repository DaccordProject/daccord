import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Transport abstraction the gateway uses to talk to a WebSocket. Abstracted
/// so the reconnect/heartbeat/dispatch logic can be unit-tested against a fake
/// connection without real networking.
abstract class GatewayConnection {
  /// Resolves once the connection is open (or rejects on failure).
  Future<void> get ready;

  /// Inbound text frames.
  Stream<String> get messages;

  /// Sends a text frame.
  void sendText(String text);

  /// Closes the connection with an optional close [code] and [reason].
  Future<void> close([int? code, String? reason]);

  /// The close code observed after the connection ended, if any.
  int? get closeCode;

  /// The close reason observed after the connection ended, if any.
  String? get closeReason;
}

/// Factory signature used by the gateway to create a connection for a URL.
typedef GatewayConnectionFactory = GatewayConnection Function(String url);

/// Default [GatewayConnection] backed by `package:web_socket_channel`.
class WebSocketGatewayConnection implements GatewayConnection {
  final WebSocketChannel _channel;

  WebSocketGatewayConnection(this._channel);

  /// Connects to [url] using [WebSocketChannel.connect].
  factory WebSocketGatewayConnection.connect(String url) {
    return WebSocketGatewayConnection(WebSocketChannel.connect(Uri.parse(url)));
  }

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<String> get messages => _channel.stream.map((event) {
        if (event is String) return event;
        if (event is List<int>) return utf8.decode(event);
        return event.toString();
      });

  @override
  void sendText(String text) => _channel.sink.add(text);

  @override
  Future<void> close([int? code, String? reason]) =>
      _channel.sink.close(code, reason);

  @override
  int? get closeCode => _channel.closeCode;

  @override
  String? get closeReason => _channel.closeReason;
}
