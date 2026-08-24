import 'dart:convert';
import 'dart:io';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
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
    test('surfaces the server error message on failure, not a generic one',
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

      expect(error, 'Missing Attach Files permission');
    });

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
    test('surfaces the server error message on failure', () async {
      final n = _makeContainer().read(
        accordMessagesControllerProvider('', 'ch1').notifier,
      );
      final client = _clientWith(
        (_) async => _errorResponse(413, 'FILE_TOO_LARGE', 'File too large'),
      );

      final error = await n.sendWithAttachments(client, 'hi', [
        {'filename': 'song.mp3', 'content': <int>[1, 2, 3]},
      ]);

      expect(error, 'File too large');
    });

    test('falls back to a generic message when the server sends none',
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
        {'filename': 'song.mp3', 'content': <int>[1, 2, 3]},
      ]);

      expect(error, 'Failed to send attachments.');
    });
  });
}
