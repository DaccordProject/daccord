import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/views/accord_member_list.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'accord_members_load_test.dart' as fixture;

const key = 'u-self@https://accord.example.test';
const space = 'space1';
final roster = accordMembersControllerProvider(key, space);

Map<String, dynamic> row(String id) => {
  'user_id': id,
  'user': {'id': id, 'username': id},
};

Future<void> waitFor(bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Probe timed out');
}

Future<void> mount(
  WidgetTester tester,
  ProviderContainer c, {
  int? total,
  int? online,
}) async {
  c.read(connectionsControllerProvider.notifier).setActive(key);
  c.read(spacesControllerProvider.notifier).setSpaces([
    AccordSpace(id: space, memberCount: total, presenceCount: online),
  ]);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: const Scaffold(body: AccordMemberList(spaceId: space)),
      ),
    ),
  );
  await tester.pump();
}

// Regressions for complete roster loading and presence lifecycle recovery.
void main() {
  test('loads online users beyond page one', () async {
    var calls = 0;
    final c = fixture.makeContainer((request) async {
      calls++;
      expect(request.url.queryParameters['limit'], '100');
      if (request.url.queryParameters['after'] != null) {
        return http.Response(
          jsonEncode({
            'data': [row('online-newcomer')],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'data': [for (var i = 0; i < 100; i++) row('older-$i')],
          'cursor': {'after': 'older-99', 'has_more': true},
        }),
        200,
      );
    });
    c.read(presenceControllerProvider(key).notifier).seed([
      AccordPresence(userId: 'online-newcomer', status: 'online'),
    ]);
    await waitFor(() => c.read(roster) != null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 2);
    expect(c.read(roster)!.length, 101);
    expect(
      accordPresenceStatus(
        c.read(presenceControllerProvider(key)),
        'online-newcomer',
      ),
      'online',
    );
    expect(c.read(roster), contains('online-newcomer'));
  });

  test('initial REST snapshot preserves concurrent joins and leaves', () async {
    final response = Completer<http.Response>();
    final c = fixture.makeContainer((_) => response.future);
    c.read(roster.notifier)
      ..upsertMember(
        AccordMember(
          userId: 'live-join',
          user: AccordUser(id: 'live-join'),
        ),
      )
      ..removeMember('already-left');
    expect(c.read(roster), isNull);
    response.complete(
      http.Response(jsonEncode([row('old-member'), row('already-left')]), 200),
    );
    await waitFor(() => c.read(roster)?.containsKey('old-member') == true);
    expect(c.read(roster), contains('live-join'));
    expect(c.read(roster), isNot(contains('already-left')));
  });

  test(
    'user enrichment preserves joins and departed members stay removed',
    () async {
      final response = Completer<http.Response>();
      var resolving = false;
      final c = fixture.makeContainer((request) async {
        if (request.url.path.contains('/users/')) {
          resolving = true;
          return response.future;
        }
        return http.Response(
          jsonEncode([
            {'user_id': 'old-member'},
          ]),
          200,
        );
      });
      await waitFor(() => resolving);
      c.read(roster.notifier)
        ..removeMember('old-member')
        ..upsertMember(
          AccordMember(
            userId: 'live-join',
            user: AccordUser(id: 'live-join'),
          ),
        );
      expect(c.read(roster), isNot(contains('old-member')));
      response.complete(
        http.Response(jsonEncode({'id': 'old-member', 'username': 'Old'}), 200),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.read(roster), isNot(contains('old-member')));
      expect(c.read(roster), contains('live-join'));
    },
  );

  testWidgets('invisible user is grouped under Offline', (tester) async {
    final c = fixture.makeContainer(
      (_) async => http.Response(jsonEncode([row('invisible-user')]), 200),
    );
    await tester.runAsync(() => waitFor(() => c.read(roster) != null));
    c.read(presenceControllerProvider(key).notifier).seed([
      AccordPresence(userId: 'invisible-user', status: 'invisible'),
    ]);
    await mount(tester, c);
    expect(find.text('MEMBERS — 1'), findsNothing);
    expect(find.text('OFFLINE — 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump();
  });

  testWidgets(
    'offline count follows live presence instead of stale summaries',
    (tester) async {
      final c = fixture.makeContainer(
        (_) async =>
            http.Response(jsonEncode([row('a'), row('b'), row('c')]), 200),
      );
      await tester.runAsync(() => waitFor(() => c.read(roster) != null));
      final ctl = c.read(presenceControllerProvider(key).notifier);
      ctl.seed([
        AccordPresence(userId: 'a', status: 'online'),
        AccordPresence(userId: 'b', status: 'online'),
      ]);
      await mount(tester, c, total: 100, online: 2);
      expect(find.text('OFFLINE — 1'), findsOneWidget);
      ctl.upsert(AccordPresence(userId: 'c', status: 'online'));
      await tester.pump();
      expect(find.text('MEMBERS — 3'), findsOneWidget);
      expect(find.textContaining('OFFLINE —'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.pump();
    },
  );

  test('a fresh READY refreshes an already open roster', () async {
    var calls = 0;
    final client = _ReadyClient((request) async {
      if (request.url.path.endsWith('/members')) {
        calls++;
        return http.Response(
          jsonEncode([row(calls == 1 ? 'old-member' : 'new-member')]),
          200,
        );
      }
      return http.Response('{"data":[]}', 200);
    });
    final c = fixture.makeContainer(
      (_) async => http.Response('', 404),
      clientOverride: client,
    );
    await waitFor(() => c.read(roster) != null);
    final handler = Provider<void>((ref) {
      final dispose = handleAccordEvents(
        ref,
        client,
        serverKey: key,
        currentUserId: 'u-self',
        selfDomain: 'accord.example.test',
        isActive: () => true,
      );
      ref.onDispose(dispose);
    });
    c.read(handler);
    client.readyEvents.add({'presences': []});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    client.readyEvents.add({'presences': []});
    await waitFor(() => c.read(roster)!.containsKey('new-member'));
    expect(calls, 2);
    expect(c.read(roster), isNot(contains('old-member')));
    await client.readyEvents.close();
  });

  test('a superseded reload cannot publish its older snapshot', () async {
    final older = Completer<http.Response>();
    var calls = 0;
    final c = fixture.makeContainer((_) async {
      calls++;
      if (calls == 1) return older.future;
      return http.Response(jsonEncode([row('new-member')]), 200);
    });
    final client = (c.read(accordAuthProvider) as AccordAuthLoggedIn).client;
    await c.read(roster.notifier).reload(client);
    older.complete(http.Response(jsonEncode([row('old-member')]), 200));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(roster)!.keys, ['new-member']);
  });

  test('legacy pages without cursor still load the final members', () async {
    var calls = 0;
    final c = fixture.makeContainer((request) async {
      calls++;
      return http.Response(
        jsonEncode(
          request.url.queryParameters['after'] == null
              ? [for (var i = 0; i < 100; i++) row('member-$i')]
              : [row('final-member')],
        ),
        200,
      );
    });
    await waitFor(() => c.read(roster) != null);
    expect(calls, 2);
    expect(c.read(roster)!.length, 101);
  });

  test(
    'a repeated cursor fails instead of publishing an incomplete roster',
    () async {
      final c = fixture.makeContainer(
        (_) async => http.Response(
          jsonEncode({
            'data': [row('old-member')],
            'cursor': {'after': 'old-member', 'has_more': true},
          }),
          200,
        ),
      );
      await waitFor(() => c.read(membersLoadFailedProvider(key, space)));
      expect(c.read(roster), isNull);
    },
  );
  test('opening a space merges its current presence snapshot', () async {
    final client = _ReadyClient(
      (request) async => http.Response(
        jsonEncode({
          'data': request.url.path.endsWith('/presences')
              ? [
                  {'user_id': 'new-space-member', 'status': 'online'},
                ]
              : [row('new-space-member')],
        }),
        200,
      ),
    );
    final c = fixture.makeContainer(
      (_) async => http.Response('', 404),
      clientOverride: client,
    );
    c
        .read(presenceControllerProvider(key).notifier)
        .upsert(AccordPresence(userId: 'other-space', status: 'idle'));
    await waitFor(
      () =>
          accordPresenceStatus(
            c.read(presenceControllerProvider(key)),
            'new-space-member',
          ) ==
          'online',
    );
    expect(
      accordPresenceStatus(
        c.read(presenceControllerProvider(key)),
        'other-space',
      ),
      'idle',
    );
    await client.readyEvents.close();
  });
}

class _ReadyClient extends AccordClient {
  _ReadyClient(Future<http.Response> Function(http.Request) responder)
    : super(
        baseUrl: 'https://accord.example.test',
        httpClient: MockClient(responder),
      );
  final readyEvents = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get onReady => readyEvents.stream;
}
