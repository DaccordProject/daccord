import 'dart:convert';
import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('shared API scopes paths and every action carries an exact revision',
      () async {
    final requests = <http.Request>[];
    final rest = AccordRest('https://community.test/api/v1',
        token: 'account-secret',
        tokenType: 'User', client: MockClient((request) async {
      requests.add(request);
      return http.Response(
          jsonEncode({
            'data': {'id': 'session', 'space_id': 'space'}
          }),
          200);
    }));
    final api = ExperiencesApi(rest);
    await api.action('space', 'session', 42, 'move',
        a: 12, b: 28, promotion: 'q');
    expect(requests.single.url.path,
        '/api/v1/spaces/space/arcade/sessions/session/actions');
    expect(jsonDecode(requests.single.body),
        {'revision': 42, 'kind': 'move', 'a': 12, 'b': 28, 'promotion': 'q'});
    await api.membership('other/space', 'other/session', 'join', 0,
        spectator: true);
    expect(requests.last.url.toString(),
        contains('other%2Fspace/arcade/sessions/other%2Fsession/members'));
    expect(jsonDecode(requests.last.body)['spectator'], isTrue);
    await api.enable('space', 'chess', '1.0.0');
    expect(requests.last.method, 'PUT');
    expect(jsonDecode(requests.last.body), {'version': '1.0.0'});
  });
  test('session mutations are not replayed after rate limits', () async {
    var attempts = 0;
    final rest = AccordRest('https://community.test/api/v1',
        client: MockClient((request) async {
      attempts++;
      return http.Response(
          jsonEncode({
            'error': {
              'code': 'rate_limited',
              'message': 'Slow down',
              'retry_after': 1
            }
          }),
          429,
          headers: {'retry-after': '1'});
    }));
    final result = await ExperiencesApi(rest)
        .action('space', 'session', 1, 'move', a: 12, b: 28);
    expect(result.ok, isFalse);
    expect(result.statusCode, 429);
    expect(attempts, 1);
  });
  test('space sessions deserialize both modes through the same API', () async {
    final rest = AccordRest('https://community.test/api/v1',
        client: MockClient((request) async => http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'one',
                  'space_id': 'space',
                  'game_id': 'chess',
                  'version': '1.0.0',
                  'digest': 'digest',
                  'mode': 'turn_based',
                  'state': 'running',
                  'host_user_id': 'one',
                  'revision': 7,
                  'turn_user_id': 'two',
                  'participants': [],
                  'game': {}
                },
                {
                  'id': 'two',
                  'space_id': 'space',
                  'game_id': 'pong',
                  'version': '1.0.0',
                  'digest': 'digest',
                  'mode': 'real_time',
                  'state': 'lobby',
                  'host_user_id': 'one',
                  'revision': 0,
                  'participants': [],
                  'game': {}
                }
              ]
            }),
            200)));
    final result = await ExperiencesApi(rest).sessions('space');
    final sessions = (result.data as List).cast<AccordExperienceSession>();
    expect(sessions.map((s) => s.mode), ['turn_based', 'real_time']);
    expect(sessions.first.turnUserId, 'two');
    expect(sessions.first.revision, 7);
  });
}
