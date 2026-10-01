import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/experience.dart';
import 'accord_client.dart';

/// Authenticated host transport. Guests only emit proposed input commands;
/// account tokens, sockets and URLs stay inside the SDK/host.
class ExperienceLiveSession {
  final WebSocketChannel _channel;
  int _sequence = 0;
  bool _closed = false;
  ExperienceLiveSession._(this._channel);

  static Future<ExperienceLiveSession> connect(
      AccordClient client, String space, String session) async {
    final base = Uri.parse(client.config.apiUrl());
    final url = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path:
            '${base.path}/spaces/${Uri.encodeComponent(space)}/arcade/sessions/${Uri.encodeComponent(session)}/live');
    final channel = WebSocketChannel.connect(url);
    try {
      await channel.ready.timeout(const Duration(seconds: 5));
      channel.sink.add(jsonEncode({'token': 'Bearer ${client.token}'}));
      return ExperienceLiveSession._(channel);
    } catch (_) {
      await channel.sink.close();
      rethrow;
    }
  }

  Stream<AccordExperienceSession> get snapshots =>
      _channel.stream.map((message) {
        if (message is! String || message.length > 100000) {
          throw const FormatException('Invalid live snapshot');
        }
        final data = jsonDecode(message) as Map;
        return AccordExperienceSession.fromJson(
            Map<String, dynamic>.from(data['data'] as Map));
      });

  /// Hosts throttle to 20 inputs/sec; the server enforces 30/sec across sockets.
  void input(int target) {
    if (_closed || target < 0 || target > 864) return;
    _channel.sink.add(
        jsonEncode({'sequence': ++_sequence, 'kind': 'input', 'a': target}));
  }

  Future<void> close() async {
    _closed = true;
    await _channel.sink.close();
  }
}
