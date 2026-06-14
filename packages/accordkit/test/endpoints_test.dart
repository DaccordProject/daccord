import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/test_helpers.dart';

late List<CapturedRequest> log;
late AccordRest rest;

CapturedRequest get req => log.single;

void main() {
  setUp(() {
    log = <CapturedRequest>[];
  });

  group('UsersApi', () {
    test('getMe deserializes user', () async {
      rest = mockRest(
          log: log, responder: (_) => jsonData({'id': '1', 'username': 'me'}));
      final result = await UsersApi(rest).getMe();
      expect(req.url.path, '/api/v1/users/@me');
      expect((result.data as AccordUser).username, 'me');
    });

    test('searchUsers passes query params', () async {
      rest = mockRest(log: log, responder: (_) => jsonData([]));
      await UsersApi(rest).searchUsers('alice', limit: 5);
      expect(req.url.path, '/api/v1/users/search');
      expect(req.url.queryParameters['query'], 'alice');
      expect(req.url.queryParameters['limit'], '5');
    });

    test('listRelationships deserializes array', () async {
      rest = mockRest(
          log: log,
          responder: (_) => jsonData([
                {
                  'id': '1',
                  'type': 1,
                  'user': {'id': '2', 'username': 'x'}
                },
              ]));
      final result = await UsersApi(rest).listRelationships();
      expect((result.data as List).single, isA<AccordRelationship>());
    });
  });

  group('SpacesApi', () {
    test('create posts body and deserializes', () async {
      rest = mockRest(
          log: log, responder: (_) => jsonData({'id': '9', 'name': 'New'}));
      final result = await SpacesApi(rest).create({'name': 'New'});
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v1/spaces');
      expect(req.jsonBody, {'name': 'New'});
      expect((result.data as AccordSpace).name, 'New');
    });

    test('listChannels deserializes array', () async {
      rest = mockRest(
          log: log,
          responder: (_) => jsonData([
                {'id': '1', 'type': 'text'},
              ]));
      final result = await SpacesApi(rest).listChannels('7');
      expect(req.url.path, '/api/v1/spaces/7/channels');
      expect((result.data as List).single, isA<AccordChannel>());
    });

    test('anonymousCount path', () async {
      rest = mockRest(log: log, responder: (_) => jsonData({'count': 3}));
      await SpacesApi(rest).anonymousCount('7');
      expect(req.url.path, '/api/v1/spaces/7/anonymous-count');
    });
  });

  group('MessagesApi', () {
    test('create message', () async {
      rest = mockRest(
          log: log,
          responder: (_) =>
              jsonData({'id': '1', 'channel_id': '5', 'content': 'hi'}));
      final result = await MessagesApi(rest).create('5', {'content': 'hi'});
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v1/channels/5/messages');
      expect((result.data as AccordMessage).content, 'hi');
    });

    test('bulkDelete posts messages array', () async {
      rest = mockRest(log: log, responder: (_) => jsonData(null));
      await MessagesApi(rest).bulkDelete('5', ['1', '2']);
      expect(req.url.path, '/api/v1/channels/5/messages/bulk-delete');
      expect(req.jsonBody!['messages'], ['1', '2']);
    });

    test('listPosts injects top_level query', () async {
      rest = mockRest(log: log, responder: (_) => jsonData([]));
      await MessagesApi(rest).listPosts('5');
      expect(req.url.queryParameters['top_level'], 'true');
    });

    test('listThread injects thread_id', () async {
      rest = mockRest(log: log, responder: (_) => jsonData([]));
      await MessagesApi(rest).listThread('5', '99');
      expect(req.url.queryParameters['thread_id'], '99');
    });

    test('createWithAttachments uses multipart upload path', () async {
      rest = mockRest(
          log: log, responder: (_) => jsonData({'id': '1', 'channel_id': '5'}));
      await MessagesApi(rest).createWithAttachments(
        '5',
        {'content': 'hi'},
        [
          {
            'filename': 'a.bin',
            'content': Uint8List.fromList([1, 2]),
            'content_type': 'application/octet-stream',
          }
        ],
      );
      expect(req.url.path, '/api/v1/channels/5/messages/upload');
      final body = utf8.decode(req.bodyBytes);
      expect(body, contains('filename="a.bin"'));
      expect(body, contains('name="payload_json"'));
    });
  });

  group('ReactionsApi', () {
    test('add encodes emoji into path', () async {
      rest = mockRest(log: log, responder: (_) => jsonData(null));
      await ReactionsApi(rest).add('5', '10', '👍');
      expect(req.method, 'PUT');
      expect(req.url.path,
          '/api/v1/channels/5/messages/10/reactions/${Uri.encodeComponent('👍')}/@me');
    });
  });

  group('MembersApi', () {
    test('list with withUser sets with_user query', () async {
      rest = mockRest(log: log, responder: (_) => jsonData([]));
      await MembersApi(rest).list('7', query: {'limit': 100}, withUser: true);
      expect(req.url.path, '/api/v1/spaces/7/members');
      expect(req.url.queryParameters['limit'], '100');
      expect(req.url.queryParameters['with_user'], 'true');
    });

    test('list omits with_user by default', () async {
      rest = mockRest(log: log, responder: (_) => jsonData([]));
      await MembersApi(rest).list('7');
      expect(req.url.queryParameters.containsKey('with_user'), isFalse);
    });

    test('leaveMe with deleteData sets query', () async {
      rest = mockRest(log: log, responder: (_) => jsonData(null));
      await MembersApi(rest).leaveMe('7', deleteData: true);
      expect(req.method, 'DELETE');
      expect(req.url.path, '/api/v1/spaces/7/members/@me');
      expect(req.url.queryParameters['delete_data'], 'true');
    });

    test('addRole path', () async {
      rest = mockRest(log: log, responder: (_) => jsonData(null));
      await MembersApi(rest).addRole('7', '2', '3');
      expect(req.url.path, '/api/v1/spaces/7/members/2/roles/3');
      expect(req.method, 'PUT');
    });
  });

  group('AuthApi', () {
    test('register parses auth response into user + token', () async {
      rest = mockRest(
          log: log,
          responder: (_) => jsonData({
                'user': {'id': '1', 'username': 'a'},
                'token': 'abc',
              }));
      final result = await AuthApi(rest).register({'username': 'a'});
      final data = result.data as Map<String, dynamic>;
      expect((data['user'] as AccordUser).username, 'a');
      expect(data['token'], 'abc');
    });

    test('login keeps mfa_required envelope unparsed', () async {
      rest = mockRest(
          log: log,
          responder: (_) => jsonData({'mfa_required': true, 'ticket': 'tkt'}));
      final result = await AuthApi(rest).login({'username': 'a'});
      final data = result.data as Map<String, dynamic>;
      expect(data['mfa_required'], isTrue);
      expect(data['ticket'], 'tkt');
    });
  });

  group('VoiceApi', () {
    test('join deserializes server update', () async {
      rest = mockRest(
          log: log,
          responder: (_) => jsonData({
                'space_id': '7',
                'channel_id': '5',
                'backend': 'livekit',
                'url': 'wss://lk',
                'token': 't',
              }));
      final result = await VoiceApi(rest).join('5', selfMute: true);
      expect(req.url.path, '/api/v1/channels/5/voice/join');
      expect(req.jsonBody, {'self_mute': true, 'self_deaf': false});
      expect((result.data as AccordVoiceServerUpdate).livekitUrl, 'wss://lk');
    });

    test('getStatus deserializes voice state list', () async {
      rest = mockRest(
          log: log,
          responder: (_) => jsonData([
                {'user_id': '1', 'channel_id': '5'},
              ]));
      final result = await VoiceApi(rest).getStatus('5');
      expect((result.data as List).single, isA<AccordVoiceState>());
    });

    test('ring posts to the call/ring path with optional metadata', () async {
      rest = mockRest(log: log, responder: (_) => jsonData({'ok': true}));
      await VoiceApi(rest).ring('5', metadata: {'video': true});
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v1/channels/5/call/ring');
      expect(req.jsonBody, {
        'metadata': {'video': true}
      });
    });

    test('declineCall posts to the call/decline path', () async {
      rest = mockRest(log: log, responder: (_) => jsonData({'ok': true}));
      await VoiceApi(rest).declineCall('5');
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v1/channels/5/call/decline');
    });

    test('cancelCall posts to the call/cancel path', () async {
      rest = mockRest(log: log, responder: (_) => jsonData({'ok': true}));
      await VoiceApi(rest).cancelCall('5');
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v1/channels/5/call/cancel');
    });
  });

  group('PluginsApi', () {
    test('listPlugins filters by type', () async {
      rest = mockRest(log: log, responder: (_) => jsonData([]));
      await PluginsApi(rest).listPlugins('7', type: 'activity');
      expect(req.url.queryParameters['type'], 'activity');
    });

    test('getSource uses raw request', () async {
      rest = mockRest(
          log: log,
          responder: (_) => http.Response.bytes(utf8.encode('-- lua'), 200));
      final result = await PluginsApi(rest).getSource('1');
      expect(req.url.path, '/api/v1/plugins/1/source');
      expect(utf8.decode(result.data as Uint8List), '-- lua');
    });

    test('leaderboardSubmit posts score', () async {
      rest = mockRest(log: log, responder: (_) => jsonData(null));
      await PluginsApi(rest)
          .leaderboardSubmit('1', 'board', 42.0, metadata: {'k': 'v'});
      expect(req.url.path, '/api/v1/plugins/1/leaderboards/board/submit');
      expect(req.jsonBody!['score'], 42.0);
      expect(req.jsonBody!['metadata'], {'k': 'v'});
    });
  });

  group('DirectoryApi', () {
    test('browse builds master-server path with params', () async {
      // DirectoryApi targets the master server, so its rest base URL is the
      // master root (without the /api/v1 instance prefix).
      rest = mockRest(
          log: log,
          baseUrl: 'https://master.test',
          responder: (_) => jsonData({'spaces': []}));
      await DirectoryApi(rest).browse(query: 'fun', tag: 'games', page: 2);
      expect(req.url.path, '/api/v1/directory');
      expect(req.url.queryParameters['q'], 'fun');
      expect(req.url.queryParameters['tag'], 'games');
      expect(req.url.queryParameters['page'], '2');
    });
  });

  group('AdminApi', () {
    test('listUsers deserializes array', () async {
      rest = mockRest(
          log: log,
          responder: (_) => jsonData([
                {'id': '1', 'username': 'a'},
              ]));
      final result = await AdminApi(rest).listUsers();
      expect(req.url.path, '/api/v1/admin/users');
      expect((result.data as List).single, isA<AccordUser>());
    });
  });

  group('RolesApi', () {
    test('reorder sends array body', () async {
      rest = mockRest(log: log, responder: (_) => jsonData([]));
      await RolesApi(rest).reorder('7', [
        {'id': '1', 'position': 0},
      ]);
      expect(req.method, 'PATCH');
      expect(req.url.path, '/api/v1/spaces/7/roles');
      expect(req.jsonArrayBody!.single['id'], '1');
    });
  });
}
