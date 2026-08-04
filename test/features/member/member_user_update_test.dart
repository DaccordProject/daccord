import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The client half of #193: a `user.update` gateway event has to reach both
// caches that hold an `AccordUser` — the global one and each open space's
// member records — without disturbing the per-space nickname/avatar overrides
// that must keep winning. The gateway handler wires
// `AccordUsersController.upsert` + `AccordMembersController.applyUserUpdate`;
// these tests cover that pair of mutations.

const _spaceId = 'space1';
const _cdn = 'https://accord.example.test/cdn';

String _membersJson(List<Map<String, dynamic>> members) =>
    jsonEncode(members);

ProviderContainer makeContainer(String body) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient((_) async => http.Response(body, 200)),
  );
  final session = AccordSession(
    server: server,
    token: 'test-token',
    userId: 'u-self',
    username: 'self',
  );
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(client: client, session: session),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  return container;
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Replays what the gateway handler does for one `user.update`.
void applyUserUpdate(ProviderContainer c, AccordUser user) {
  c.read(accordUsersControllerProvider.notifier).upsert(user);
  for (final spaceId in [...activeMemberSpaces]) {
    c
        .read(accordMembersControllerProvider(spaceId).notifier)
        .applyUserUpdate(user);
  }
}

void main() {
  test('refreshes the global user cache and every open space member', () async {
    final c = makeContainer(_membersJson([
      {
        'user_id': 'u1',
        'user': {'id': 'u1', 'username': 'u1', 'avatar': 'oldhash'},
      },
    ]));
    c.read(accordMembersControllerProvider(_spaceId));
    await _waitUntil(
      () => c.read(accordMembersControllerProvider(_spaceId)) != null,
    );

    applyUserUpdate(
      c,
      AccordUser(
        id: 'u1',
        username: 'u1',
        displayName: 'Renamed',
        avatar: 'newhash',
      ),
    );

    final cachedUser = c.read(accordUsersControllerProvider)['u1'];
    expect(cachedUser?.displayName, 'Renamed');
    expect(accordAvatarUrl(cachedUser, _cdn), contains('newhash'));

    final member = c.read(accordMembersControllerProvider(_spaceId))!['u1']!;
    expect(accordMemberName(member), 'Renamed');
    expect(accordMemberAvatarUrl(member, _cdn), contains('newhash'));
  });

  test('per-space nickname and avatar overrides still win', () async {
    final c = makeContainer(_membersJson([
      {
        'user_id': 'u1',
        'nick': 'Spacey',
        'avatar': 'memberhash',
        'user': {'id': 'u1', 'username': 'u1', 'avatar': 'oldhash'},
      },
    ]));
    c.read(accordMembersControllerProvider(_spaceId));
    await _waitUntil(
      () => c.read(accordMembersControllerProvider(_spaceId)) != null,
    );

    applyUserUpdate(
      c,
      AccordUser(
        id: 'u1',
        username: 'u1',
        displayName: 'Renamed',
        avatar: 'newhash',
      ),
    );

    final member = c.read(accordMembersControllerProvider(_spaceId))!['u1']!;
    // The member record itself is untouched: overrides survive the update.
    expect(member.nickname, 'Spacey');
    expect(member.avatar, 'memberhash');
    expect(accordMemberName(member), 'Spacey');
    expect(accordMemberAvatarUrl(member, _cdn), contains('memberhash'));
    // …while the embedded user underneath it did pick up the change.
    expect(member.user?.displayName, 'Renamed');
  });

  test('an update for a non-member only touches the global cache', () async {
    final c = makeContainer(_membersJson([
      {
        'user_id': 'u1',
        'user': {'id': 'u1', 'username': 'u1'},
      },
    ]));
    c.read(accordMembersControllerProvider(_spaceId));
    await _waitUntil(
      () => c.read(accordMembersControllerProvider(_spaceId)) != null,
    );

    applyUserUpdate(
      c,
      AccordUser(id: 'stranger', username: 'stranger', displayName: 'Str'),
    );

    expect(c.read(accordUsersControllerProvider)['stranger']?.displayName, 'Str');
    final members = c.read(accordMembersControllerProvider(_spaceId))!;
    expect(members.keys, ['u1']);
  });
}
