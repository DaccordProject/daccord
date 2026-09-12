import 'dart:convert';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/automod/utils/automod_policy.dart';
import 'package:bonfire/features/automod/views/automod_panel.dart';
import 'package:bonfire/features/automod/views/block_attachment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AccordClient clientWith(Future<http.Response> Function(http.Request) respond) {
  final client = AccordClient(
    baseUrl: 'https://example.test',
    gatewayUrl: 'wss://example.test/ws',
    cdnUrl: 'https://example.test/cdn',
    token: 'private-token',
    httpClient: MockClient(respond),
  );
  addTearDown(client.dispose);
  return client;
}

http.Response data(Object? value) =>
    http.Response(jsonEncode({'data': value}), 200);
Future<String?> block(
  AccordClient client, {
  List<String> ids = const ['a', 'b'],
  bool Function()? active,
}) => blockAttachmentsAndDelete(
  client: client,
  scope: 's',
  channelId: 'c',
  messageId: 'm',
  attachmentIds: ids,
  reason: 'Repeated prohibited upload',
  stillActive: active,
);
Map<String, dynamic> policy() => {
  'enabled': false,
  'retention_days': 7,
  'exempt_roles': [],
  'exempt_permissions': [],
  'rules': [],
};

void main() {
  test('blocks all selected attachments before deleting', () async {
    final calls = <String>[];
    final client = clientWith((r) async {
      calls.add('${r.method} ${r.url.path}');
      return data(null);
    });
    expect(await block(client), isNull);
    expect(calls, [
      'POST /api/v1/automod/s/attachments/a/block',
      'POST /api/v1/automod/s/attachments/b/block',
      'DELETE /api/v1/channels/c/messages/m',
    ]);
  });
  test(
    'a failed second block retains message and reports first block',
    () async {
      final calls = <String>[];
      final client = clientWith((r) async {
        calls.add(r.method);
        return calls.length == 2
            ? http.Response('{"error":{"message":"Forbidden"}}', 403)
            : data(null);
      });
      expect(
        await block(client),
        contains('1 file(s) are blocked. The message was kept.'),
      );
      expect(calls, ['POST', 'POST']);
    },
  );
  test('failed deletion leaves successful blocks intact', () async {
    final calls = <String>[];
    final client = clientWith((r) async {
      calls.add(r.method);
      return r.method == 'DELETE' ? http.Response('{}', 500) : data(null);
    });
    expect(
      await block(client),
      contains('Files are blocked, but the message could not be deleted'),
    );
    expect(calls, ['POST', 'POST', 'DELETE']);
  });
  test('account change and empty selection prevent deletion', () async {
    final calls = <String>[];
    final client = clientWith((r) async {
      calls.add(r.method);
      return data(null);
    });
    expect(await block(client, ids: []), contains('Select'));
    expect(
      await block(client, active: () => calls.isEmpty),
      contains('Account changed'),
    );
    expect(calls, ['POST']);
  });
  test('malformed and unsupported rules are rejected without crashing', () {
    expect(validateAutomodPolicy(policy()), isNull);
    expect(
      validateAutomodPolicy({
        ...policy(),
        'rules': [null],
      }),
      isNotNull,
    );
    expect(
      validateAutomodPolicy({
        ...policy(),
        'rules': [
          {'id': 'x'},
        ],
      }),
      isNotNull,
    );
    expect(
      validateAutomodPolicy({
        ...policy(),
        'rules': [
          {
            'id': 'x',
            'scope': {'type': 'all'},
            'trigger': {
              'type': 'media',
              'threshold': 0.8,
              'categories': ['ANUS_EXPOSED'],
            },
            'action': {'type': 'timeout', 'seconds': 30},
          },
        ],
      }),
      contains('Timeouts require'),
    );
  });
  testWidgets('review-only permission never fetches or shows configuration', (
    tester,
  ) async {
    final paths = <String>[];
    final client = clientWith((r) async {
      paths.add(r.url.path);
      return data([]);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AutomodWorkbench(
            client: client,
            scope: 's',
            canConfigure: false,
            canReview: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Rules'), findsNothing);
    expect(find.text('Blocked files'), findsNothing);
    expect(paths, ['/api/v1/automod/s/uploads', '/api/v1/automod/s/events']);
  });
  testWidgets('configuration-only permission never fetches evidence or queue', (
    tester,
  ) async {
    final paths = <String>[];
    final client = clientWith((r) async {
      paths.add(r.url.path);
      return data(
        r.url.path.endsWith('/policy')
            ? {'policy': policy(), 'inherited': true}
            : [],
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AutomodWorkbench(
            client: client,
            scope: 's',
            canConfigure: true,
            canReview: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rules'), findsOneWidget);
    expect(find.text('Review'), findsNothing);
    expect(find.textContaining('Using the server policy'), findsOneWidget);
    expect(paths, ['/api/v1/automod/s/policy', '/api/v1/automod/s/hashes']);
  });
  testWidgets(
    'older server displays actionable error instead of editable defaults',
    (tester) async {
      final client = clientWith((_) async => http.Response('{}', 404));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AutomodWorkbench(
              client: client,
              scope: 's',
              canConfigure: true,
              canReview: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Update the server.'), findsOneWidget);
      expect(find.text('Enable automatic scanning'), findsNothing);
    },
  );
  testWidgets(
    'private evidence closes when the account workbench is disposed',
    (tester) async {
      final client = clientWith((r) async {
        if (r.url.path.endsWith('/content')) {
          return http.Response.bytes([1, 2, 3], 200);
        }
        return data(
          r.url.path.endsWith('/uploads')
              ? [
                  {
                    'id': 'u',
                    'filename': 'private.mp4',
                    'content_type': 'video/mp4',
                    'status': 'quarantined',
                    'author_id': 'a',
                  },
                ]
              : [],
        );
      });
      var active = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: active
                    ? AutomodWorkbench(
                        client: client,
                        scope: 's',
                        canConfigure: false,
                        canReview: true,
                      )
                    : const Text('New account'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View evidence'));
      await tester.pumpAndSettle();
      expect(find.text('Download original'), findsOneWidget);
      update(() => active = false);
      await tester.pumpAndSettle();
      expect(find.text('Download original'), findsNothing);
      expect(find.text('New account'), findsOneWidget);
    },
  );
}
