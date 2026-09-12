import 'dart:convert';
import 'dart:io';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/pending_uploads.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A logged-out container so `build()` skips its auto `_load` REST call —
/// these tests drive `send`/`sendWithAttachments` directly with a client of
/// their own, the same way the composer and other callers do.
ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AccordClient _clientWith(
  Future<http.Response> Function(http.Request request) responder,
) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient(responder),
  );
  addTearDown(client.dispose);
  return client;
}

http.Response _errorResponse(int status, String code, String message) =>
    http.Response(
      jsonEncode({
        'error': {'code': code, 'message': message},
      }),
      status,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('accord-messages-send-test');
    Hive.init(tempDir.path);
    await Hive.openBox('accord-settings');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('send', () {
    test('returns true on success', () async {
      final n = _makeContainer().read(
        accordMessagesControllerProvider('', 'ch1').notifier,
      );
      final client = _clientWith(
        (_) async => http.Response(
          jsonEncode({'id': 'm1', 'channel_id': 'ch1', 'content': 'hi'}),
          200,
        ),
      );

      expect(await n.send(client, 'hi'), isTrue);
    });

    test('returns false on a server failure', () async {
      final n = _makeContainer().read(
        accordMessagesControllerProvider('', 'ch1').notifier,
      );
      final client = _clientWith(
        (_) async => _errorResponse(403, 'FORBIDDEN', 'Missing permission'),
      );

      expect(await n.send(client, 'hi'), isFalse);
    });
  });

  group('sendWithAttachments — no files', () {
    // sendWithAttachments falls back to the same messages.create call `send`
    // makes, but needs the server's own failure reason rather than `send`'s
    // bare bool — that's what the composer shows above the message box.
    test(
      'surfaces the server error message on failure, not a generic one',
      () async {
        final n = _makeContainer().read(
          accordMessagesControllerProvider('', 'ch1').notifier,
        );
        final client = _clientWith(
          (_) async => _errorResponse(
            403,
            'FORBIDDEN',
            'Missing Attach Files permission',
          ),
        );

        final error = await n.sendWithAttachments(client, 'hi', const []);

        expect(error?.message, 'Missing Attach Files permission');
      },
    );

    test('returns null on success', () async {
      final n = _makeContainer().read(
        accordMessagesControllerProvider('', 'ch1').notifier,
      );
      final client = _clientWith(
        (_) async => http.Response(
          jsonEncode({'id': 'm1', 'channel_id': 'ch1', 'content': 'hi'}),
          200,
        ),
      );

      expect(await n.sendWithAttachments(client, 'hi', const []), isNull);
    });
  });

  group('sendWithAttachments — with files', () {
    final file = <String, dynamic>{
      'filename': 'pic.png',
      'content': <int>[1, 2, 3],
    };

    test(
      'a 202 with pending attachments is one message and one POST',
      () async {
        final container = _makeContainer();
        final n = container.read(
          accordMessagesControllerProvider('', 'ch1').notifier,
        );
        var posts = 0;
        final client = _clientWith((request) async {
          posts += 1;
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'm1',
                'channel_id': 'ch1',
                'content': 'hi',
                'attachments': <Object>[],
              },
              'pending_attachments': ['u1', 'u2'],
            }),
            202,
          );
        });

        final error = await n.sendWithAttachments(client, 'hi', [file]);

        expect(error?.message, isNull);
        expect(posts, 1);
        final messages = container.read(
          accordMessagesControllerProvider('', 'ch1'),
        );
        expect(messages?.map((m) => m.id), ['m1']);
        expect(messages!.single.attachments, isEmpty);
        // The held uploads are tracked against the message for the placeholder.
        final pending = container.read(pendingUploadsControllerProvider(''));
        expect(pending.forMessage('m1').map((u) => u.id), ['u1', 'u2']);
        expect(pending.forMessage('m1').every((u) => u.isOutstanding), isTrue);
      },
    );

    test('a 200 with the attachments delivered tracks nothing', () async {
      final container = _makeContainer();
      final n = container.read(
        accordMessagesControllerProvider('', 'ch1').notifier,
      );
      final client = _clientWith(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'id': 'm1',
              'channel_id': 'ch1',
              'attachments': [
                {'id': 'a1', 'filename': 'pic.png', 'url': '/cdn/a1.png'},
              ],
            },
          }),
          200,
        ),
      );

      expect(await n.sendWithAttachments(client, 'hi', [file]), isNull);

      final messages = container.read(
        accordMessagesControllerProvider('', 'ch1'),
      );
      expect(messages!.single.attachments.single.id, 'a1');
      expect(
        container.read(pendingUploadsControllerProvider('')).uploads,
        isEmpty,
      );
    });

    test(
      'a deterministic AutoMod rejection (400) shows the server reason',
      () async {
        final container = _makeContainer();
        final n = container.read(
          accordMessagesControllerProvider('', 'ch1').notifier,
        );
        final client = _clientWith(
          (_) async => _errorResponse(
            400,
            'BAD_REQUEST',
            'attachment blocked by rule blocked-file',
          ),
        );

        final error = await n.sendWithAttachments(client, 'hi', [file]);

        expect(error?.message, 'attachment blocked by rule blocked-file');
        expect(
          container.read(accordMessagesControllerProvider('', 'ch1')),
          isNull,
        );
      },
    );

    test('surfaces the server error message on failure', () async {
      final n = _makeContainer().read(
        accordMessagesControllerProvider('', 'ch1').notifier,
      );
      final client = _clientWith(
        (_) async => _errorResponse(413, 'FILE_TOO_LARGE', 'File too large'),
      );

      final error = await n.sendWithAttachments(client, 'hi', [
        {
          'filename': 'song.mp3',
          'content': <int>[1, 2, 3],
        },
      ]);

      expect(error?.message, 'File too large');
    });

    test(
      'falls back to a generic message when the server sends none',
      () async {
        final n = _makeContainer().read(
          accordMessagesControllerProvider('', 'ch1').notifier,
        );
        final client = _clientWith(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 'INTERNAL'},
            }),
            500,
          ),
        );

        final error = await n.sendWithAttachments(client, 'hi', [
          {
            'filename': 'song.mp3',
            'content': <int>[1, 2, 3],
          },
        ]);

        expect(error?.message, 'Failed to send attachments.');
      },
    );
  });
  group('rate limits (#330)', () {
    // The server's exact 429 shape for slowmode and the upload budgets:
    // `Retry-After` header plus `error.retry_after`, both in seconds.
    http.Response rateLimited(int seconds) => http.Response(
      jsonEncode({
        'error': {
          'code': 'rate_limited',
          'message': 'rate limited, retry after ${seconds}s',
          'retry_after': seconds,
        },
      }),
      429,
      headers: {'retry-after': '$seconds'},
    );

    test(
      'a slowmode 429 on a text send comes back once with its retry_after',
      () async {
        var requests = 0;
        final n = _makeContainer().read(
          accordMessagesControllerProvider('', 'ch1').notifier,
        );
        final client = _clientWith((_) async {
          requests++;
          return rateLimited(12);
        });

        final failure = await n.sendWithAttachments(client, 'hi', const []);

        // Exactly one POST: the SDK must not retry a user send, or Send stays
        // busy for the whole cooldown and the server sees duplicate attempts.
        expect(requests, 1);
        expect(failure, isNotNull);
        expect(failure!.rateLimited, isTrue);
        expect(failure.retryAfter, const Duration(seconds: 12));
        expect(failure.message, 'rate limited, retry after 12s');
      },
    );

    test('an upload-budget 429 is sent exactly once, files and all', () async {
      var uploads = 0;
      final n = _makeContainer().read(
        accordMessagesControllerProvider('', 'ch1').notifier,
      );
      final client = _clientWith((request) async {
        if (request.url.path.endsWith('/messages/upload')) uploads++;
        return rateLimited(45);
      });

      final failure = await n.sendWithAttachments(client, 'pic', [
        {
          'filename': 'a.png',
          'content': <int>[1, 2, 3],
        },
      ]);

      expect(uploads, 1);
      expect(failure!.rateLimited, isTrue);
      expect(failure.retryAfter, const Duration(seconds: 45));
    });

    test('send() still reports a rate limit as a plain failure', () async {
      final n = _makeContainer().read(
        accordMessagesControllerProvider('', 'ch1').notifier,
      );
      final client = _clientWith((_) async => rateLimited(5));
      expect(await n.send(client, 'hi'), isFalse);
    });
  });
}
