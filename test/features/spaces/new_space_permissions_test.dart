import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/permission_catalog.dart';
import 'package:bonfire/features/spaces/utils/new_space_permissions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AccordSpace _spaceWithEveryonePermissions(List<dynamic> permissions) =>
    AccordSpace(
      id: 'space',
      roles: [
        AccordRole(
          id: 'everyone',
          name: '@everyone',
          position: 0,
          permissions: permissions,
        ),
      ],
    );

void main() {
  test('current server default needs no client-side update', () async {
    var calls = 0;
    final client = AccordClient(
      baseUrl: 'https://accord.example',
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);

    final result = await normalizeNewSpaceEveryoneRole(
      client,
      _spaceWithEveryonePermissions([AccordPermission.sendMessages]),
    );

    expect(result, isNull);
    expect(calls, 0);
  });

  test(
    'legacy server default is removed only from the new everyone role',
    () async {
      late http.Request request;
      final client = AccordClient(
        baseUrl: 'https://accord.example',
        httpClient: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode({
              'id': 'everyone',
              'name': '@everyone',
              'position': 0,
              'permissions': [AccordPermission.sendMessages],
            }),
            200,
          );
        }),
      );
      addTearDown(client.dispose);

      final result = await normalizeNewSpaceEveryoneRole(
        client,
        _spaceWithEveryonePermissions([
          AccordPermission.sendMessages,
          AccordPermission.mentionEveryone,
        ]),
      );

      expect(result?.ok, isTrue);
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/spaces/space/roles/everyone');
      expect(jsonDecode(request.body), {
        'permissions': [AccordPermission.sendMessages],
      });
    },
  );

  test('broadcast permission is discoverable in the Text group', () {
    final text = accordPermissionGroups.singleWhere(
      (group) => group.label == 'Text',
    );

    expect(text.permissions, contains(AccordPermission.mentionEveryone));
    expect(
      accordPermissionLabel(AccordPermission.mentionEveryone),
      'Mention @everyone, @here, and all roles',
    );
  });
}
