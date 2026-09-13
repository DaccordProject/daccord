import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/developer/services/mcp_tools.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _toolsProvider = Provider<McpTools>((ref) => McpTools(ref));

void main() {
  late ProviderContainer container;
  late McpTools tools;
  late AccordClient client;
  late AccordSession session;
  late Map<String, dynamic> space;
  late Map<String, Map<String, dynamic>> channels;
  late List<http.Request> writes;
  late List<String> permissions;
  Future<http.Response?> Function(http.Request)? intercept;

  setUp(() {
    space = {'id': 's', 'name': 'Community', 'owner_id': 'self'};
    channels = {
      'category': {'id': 'category', 'space_id': 's', 'name': 'Games', 'type': 'category'},
      'text': {'id': 'text', 'space_id': 's', 'name': 'general', 'type': 'text'},
      'foreign': {'id': 'foreign', 'space_id': 'other', 'name': 'Elsewhere', 'type': 'text'},
    };
    writes = [];
    permissions = [];
    intercept = null;
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    session = AccordSession(server: server, token: 'token', userId: 'self', username: 'self');
    client = AccordClient(
      token: 'token', baseUrl: server.baseUrl, gatewayUrl: server.gatewayUrl,
      httpClient: MockClient((request) async {
        final response = await intercept?.call(request);
        if (response != null) return response;
        final path = request.url.path.replaceFirst('/api/v1', '');
        if (request.method != 'GET') writes.add(request);
        Object? data;
        if (path == '/spaces' && request.method == 'POST') {
          space = {...space, ...jsonDecode(request.body) as Map<String, dynamic>};
          data = space;
        } else if (path == '/spaces/s') {
          if (request.method == 'PATCH') {
            space = {...space, ...jsonDecode(request.body) as Map<String, dynamic>};
          }
          data = space;
        } else if (path == '/spaces/s/members/self') {
          data = {'user_id': 'self', 'roles': ['role']};
        } else if (path == '/spaces/s/roles') {
          data = [{'id': 'role', 'position': 1, 'permissions': permissions}];
        } else if (path == '/spaces/s/channels') {
          if (request.method == 'POST') {
            final channel = {'id': 'new', 'space_id': 's', ...jsonDecode(request.body) as Map<String, dynamic>};
            channels['new'] = channel;
            data = channel;
          } else {
            if (request.method == 'PATCH') {
              for (final entry in jsonDecode(request.body) as List) {
                final map = entry as Map<String, dynamic>;
                channels[map['id'] as String]!.addAll(map);
              }
            }
            data = channels.values.where((channel) => channel['space_id'] == 's').toList();
          }
        } else if (path.startsWith('/channels/')) {
          final id = path.split('/').last;
          if (request.method == 'PATCH') channels[id]!.addAll(jsonDecode(request.body) as Map<String, dynamic>);
          data = channels[id];
          if (request.method == 'DELETE') channels.remove(id);
        } else {
          return http.Response(jsonEncode({'error': {'code': 'not_found', 'message': path}}), 404);
        }
        return http.Response(jsonEncode({'data': data}), 200);
      }),
    );
    container = ProviderContainer(overrides: [
      accordAuthProvider.overrideWithValue(AccordAuthLoggedIn(client: client, session: session)),
    ]);
    final connections = container.read(connectionsControllerProvider.notifier);
    connections.register(session);
    connections.setActive(session.key);
    tools = container.read(_toolsProvider);
  });

  tearDown(() {
    container.dispose();
    client.dispose();
  });

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) =>
      tools.tools[name]!.handler(args);

  test('space management is a dedicated opt-in group', () {
    expect(AccordSettings.mcpToolGroups, contains('space_management'));
    expect(AccordSettings.defaultMcpAllowedGroups, isNot(contains('space_management')));
    expect(AccordSettings.fromJson({}).mcpAllowedGroups, isNot(contains('space_management')));
    for (final name in ['create_space', 'update_space', 'create_channel', 'update_channel', 'delete_channel', 'reorder_channels']) {
      expect(tools.tools[name]!.group, 'space_management');
    }
  });

  test('space creation and partial update return entities and populate both caches', () async {
    final created = await call('create_space', {'name': 'Gaming', 'description': 'Play together'});
    expect(created['ok'], isTrue);
    expect((created['space'] as Map)['id'], 's');
    final updated = await call('update_space', {
      'space_id': 's', 'description': null, 'public': true,
      'allow_guest_access': false, 'default_notifications': 'mentions',
      'verification_level': 'high', 'explicit_content_filter': 'everyone',
      'nsfw_level': 'moderate', 'rules_channel_id': 'text', 'system_channel_id': null,
    });
    expect(updated['ok'], isTrue);
    final body = jsonDecode(writes.last.body) as Map;
    expect(body.containsKey('name'), isFalse);
    expect(body.containsKey('description'), isTrue);
    expect(body['description'], isNull);
    expect(body['system_channel_id'], isNull);
    expect(body['rules_channel_id'], 'text');
    expect(container.read(spacesControllerProvider)!.single.name, 'Gaming');
    expect(container.read(connectionsControllerProvider).active!.spaces.single.defaultNotifications, 'mentions');
  });

  test('image data and explicit removals reach the SDK unchanged', () async {
    const image = 'data:image/png;base64,iVBORw0KGgo=';
    final bodies = <Map<String, dynamic>>[];
    intercept = (request) async {
      if (request.method != 'PATCH') return null;
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(jsonEncode({'data': space}), 200);
    };
    expect((await call('update_space', {'space_id': 's', 'icon': image, 'banner': image}))['ok'], isTrue);
    expect(bodies.single, {'icon': image, 'banner': image});
    expect((await call('update_space', {'space_id': 's', 'icon': null, 'banner': null}))['ok'], isTrue);
    expect(bodies.last, {'icon': null, 'banner': null});
  });

  for (final type in ['category', 'text', 'announcement', 'forum', 'voice']) {
    test('creates $type with typed fields and caches returned entity', () async {
      final result = await call('create_channel', {
        'space_id': 's', 'name': 'New channel', 'type': type,
        if (type != 'category') 'parent_id': 'category',
        'topic': 'Welcome', 'nsfw': false, 'rate_limit': 5,
      });
      expect(result['ok'], isTrue);
      expect((result['channel'] as Map)['id'], 'new');
      expect(jsonDecode(writes.single.body)['rate_limit'], 5);
      expect(container.read(accordChannelsControllerProvider(session.key, 's'))!.any((channel) => channel.id == 'new'), isTrue);
    });
  }

  test('updates type and clears topic/parent without losing explicit nulls', () async {
    final result = await call('update_channel', {
      'space_id': 's', 'channel_id': 'text', 'type': 'announcement',
      'topic': null, 'parent_id': null, 'rate_limit': 0, 'nsfw': true,
    });
    expect(result['ok'], isTrue);
    expect((result['channel'] as Map)['type'], 'announcement');
    final body = jsonDecode(writes.single.body) as Map;
    expect(body.keys, containsAll(['topic', 'parent_id', 'rate_limit', 'nsfw']));
    expect(body['parent_id'], isNull);
    expect(body.containsKey('name'), isFalse);
  });

  test('reorders channels and refreshes cache including parent changes', () async {
    final result = await call('reorder_channels', {
      'space_id': 's',
      'channels': [{'id': 'text', 'position': 2, 'parent_id': 'category'}],
    });
    expect(result['ok'], isTrue);
    final updated = (result['channels'] as List).cast<Map>().singleWhere((channel) => channel['id'] == 'text');
    expect(updated['position'], 2);
    expect(updated['parent_id'], 'category');
    expect(jsonDecode(writes.single.body), [{'id': 'text', 'position': 2, 'parent_id': 'category'}]);
  });

  test('deletion requires explicit confirmation and removes cached channel', () async {
    final missing = await call('delete_channel', {'space_id': 's', 'channel_id': 'text'});
    expect(missing['code'], 'validation_error');
    expect(writes, isEmpty);
    final result = await call('delete_channel', {'space_id': 's', 'channel_id': 'text', 'confirm': true});
    expect(result['deleted_channel_id'], 'text');
    expect(container.read(accordChannelsControllerProvider(session.key, 's'))!.any((channel) => channel.id == 'text'), isFalse);
  });

  test('checks fresh role permissions and prevents writes for unauthorized members', () async {
    space['owner_id'] = 'another-user';
    final denied = await call('update_space', {'space_id': 's', 'name': 'Denied'});
    expect(denied['code'], 'permission_denied');
    expect(denied['permission'], AccordPermission.manageSpace);
    expect(writes, isEmpty);
    permissions = [AccordPermission.manageSpace];
    expect((await call('update_space', {'space_id': 's', 'name': 'Allowed'}))['ok'], isTrue);
    final deniedChannel = await call('delete_channel', {'space_id': 's', 'channel_id': 'text', 'confirm': true});
    expect(deniedChannel['permission'], AccordPermission.manageChannels);
    expect(writes, hasLength(1));
  });

  test('rejects cross-space targets and destructive channel type changes', () async {
    for (final args in [
      {'space_id': 's', 'channel_id': 'foreign', 'name': 'No'},
      {'space_id': 's', 'channel_id': 'text', 'type': 'voice'},
      {'space_id': 's', 'channel_id': 'text', 'parent_id': 'text'},
    ]) {
      expect((await call('update_channel', args))['code'], 'validation_error');
    }
    expect((await call('update_space', {'space_id': 's', 'rules_channel_id': 'foreign'}))['code'], 'validation_error');
    expect(writes, isEmpty);
  });

  test('schema validation rejects coerced values, unknown fields and duplicate IDs', () async {
    for (final args in [
      {'space_id': 's', 'name': ''},
      {'space_id': 's', 'public': 'true'},
      {'space_id': 's', 'verification_level': 'invalid'},
      {'space_id': 's', 'icon': 'not-an-image'},
      {'space_id': 's', 'icon': 'data:image/png;base64,!!!'},
      {'space_id': 's', 'unknown': true},
      {'space_id': 's'},
    ]) {
      expect((await call('update_space', args))['code'], 'validation_error');
    }
    expect((await call('update_channel', {'space_id': 's', 'channel_id': 'text', 'rate_limit': 21601}))['code'], 'validation_error');
    expect((await call('reorder_channels', {'space_id': 's', 'channels': [{'id': 'text', 'position': 0}, {'id': 'text', 'position': 1}]}))['code'], 'validation_error');
    expect(writes, isEmpty);
  });

  test('preserves structured server permission errors', () async {
    intercept = (request) async => request.method == 'POST'
        ? http.Response(jsonEncode({'error': {'code': 'forbidden', 'message': 'Space creation disabled'}}), 403)
        : null;
    final result = await call('create_space', {'name': 'Denied'});
    expect(result['code'], 'forbidden');
    expect(result['_status'], 403);
    expect(result['error'], 'Space creation disabled');
  });

  test('refresh failures warn without reporting an accepted write as failed', () async {
    intercept = (request) async => request.method == 'GET' && request.url.path.endsWith('/channels')
        ? http.Response(jsonEncode({'error': {'code': 'unavailable', 'message': 'Refresh unavailable'}}), 503)
        : null;
    final result = await call('create_channel', {'space_id': 's', 'name': 'Created', 'type': 'text'});
    expect(result['ok'], isTrue);
    expect((result['channel'] as Map)['id'], 'new');
    expect((result['warning'] as Map)['_status'], 503);
    expect(writes, hasLength(1));
  });

  test('account switch during permission fetch prevents the mutation', () async {
    final pending = Completer<http.Response?>();
    final started = Completer<void>();
    intercept = (request) async {
      if (request.url.path.endsWith('/spaces/s')) {
        started.complete();
        return pending.future;
      }
      return null;
    };
    final operation = call('update_space', {'space_id': 's', 'name': 'No'});
    await started.future;
    container.updateOverrides([accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut())]);
    pending.complete(http.Response(jsonEncode({'data': space}), 200));
    expect((await operation)['code'], 'connection_changed');
    expect(writes, isEmpty);
  });
}
