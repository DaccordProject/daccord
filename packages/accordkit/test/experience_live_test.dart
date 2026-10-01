@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:accordkit/accordkit.dart';
import 'package:test/test.dart';

void main() {
  test(
      'live host scopes URL, authenticates outside guest state and sequences bounded input',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final frames = <Map<String, dynamic>>[];
    final accepted = Completer<WebSocket>();
    server.listen((request) async {
      expect(request.uri.path,
          '/api/v1/spaces/space/arcade/sessions/session/live');
      expect(request.uri.query, isEmpty);
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        final frame = jsonDecode(message as String) as Map<String, dynamic>;
        frames.add(frame);
        if (frames.length == 1) {
          socket.add(jsonEncode({
            'data': {
              'id': 'session',
              'space_id': 'space',
              'game_id': 'pong',
              'version': '1.0.0',
              'digest': 'digest',
              'mode': 'real_time',
              'state': 'running',
              'revision': 7,
              'host_user_id': 'user',
              'participants': [],
              'game': {}
            }
          }));
        }
      });
      accepted.complete(socket);
    });
    final client = AccordClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        tokenType: 'Bearer',
        token: 'trusted-host-token');
    addTearDown(client.dispose);
    final live =
        await ExperienceLiveSession.connect(client, 'space', 'session');
    addTearDown(live.close);
    final snapshot =
        await live.snapshots.first.timeout(const Duration(seconds: 3));
    expect(snapshot.revision, 7);
    expect(frames.first, {'token': 'Bearer trusted-host-token'});
    live.input(-1);
    live.input(865);
    live.input(300);
    live.input(400);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(frames.skip(1).toList(), [
      {'sequence': 1, 'kind': 'input', 'a': 300},
      {'sequence': 2, 'kind': 'input', 'a': 400},
    ]);
    await live.close();
    live.input(500);
    expect(frames, hasLength(3));
    await (await accepted.future).close();
  });
}
