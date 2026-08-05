import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/utils/attachment_limits.dart';
import 'package:bonfire/features/messaging/utils/attachment_types.dart';
import 'package:bonfire/features/server/controllers/server_limits.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/models/accord_server_limits.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

PendingAttachment _file(String name, int bytes) => PendingAttachment(
      PlatformFile(name: name, size: bytes, bytes: Uint8List(bytes)),
    );

/// A logged-in container whose client answers `GET /settings` with [responder].
ProviderContainer _container(
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

/// Polls until [condition] holds, so the test doesn't depend on how many
/// microtasks the fire-and-forget refresh takes.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('AccordServerLimits.fromSettings', () {
    test('reads both limits from a public settings payload', () {
      final limits = AccordServerLimits.fromSettings(const {
        'max_attachment_size': 8 * 1024 * 1024,
        'max_attachments_per_message': 4,
        'server_name': 'Example',
      });
      expect(limits.maxAttachmentBytes, 8 * 1024 * 1024);
      expect(limits.maxAttachmentsPerMessage, 4);
      expect(limits.fromServer, isTrue);
    });

    test('falls back entirely when the fetch failed (null payload)', () {
      final limits = AccordServerLimits.fromSettings(null);
      expect(limits, AccordServerLimits.fallback);
      expect(limits.maxAttachmentBytes, kMaxAttachmentBytes);
      expect(limits.maxAttachmentsPerMessage, kMaxAttachmentsPerMessage);
      expect(limits.fromServer, isFalse);
    });

    test('falls back when the server exposes neither key', () {
      final limits = AccordServerLimits.fromSettings(const {
        'server_name': 'Old server',
        'motd': 'hi',
      });
      expect(limits, AccordServerLimits.fallback);
    });

    test('falls back per-field when only one key is present', () {
      final sizeOnly = AccordServerLimits.fromSettings(const {
        'max_attachment_size': 1024,
      });
      expect(sizeOnly.maxAttachmentBytes, 1024);
      expect(sizeOnly.maxAttachmentsPerMessage, kMaxAttachmentsPerMessage);

      final countOnly = AccordServerLimits.fromSettings(const {
        'max_attachments_per_message': 3,
      });
      expect(countOnly.maxAttachmentBytes, kMaxAttachmentBytes);
      expect(countOnly.maxAttachmentsPerMessage, 3);
    });

    test('accepts string- and double-encoded numbers', () {
      final limits = AccordServerLimits.fromSettings(const {
        'max_attachment_size': '26214400',
        'max_attachments_per_message': 10.0,
      });
      expect(limits.maxAttachmentBytes, 26214400);
      expect(limits.maxAttachmentsPerMessage, 10);
    });

    test('ignores zero, negative and unparseable values', () {
      expect(
        AccordServerLimits.fromSettings(const {
          'max_attachment_size': 0,
          'max_attachments_per_message': -1,
        }),
        AccordServerLimits.fallback,
      );
      expect(
        AccordServerLimits.fromSettings(const {
          'max_attachment_size': 'unlimited',
          'max_attachments_per_message': null,
        }),
        AccordServerLimits.fallback,
      );
    });

    test('the fallback matches the accordserver defaults', () {
      // migrations/011_server_settings.sql: 26214400 bytes, 10 attachments.
      expect(AccordServerLimits.fallback.maxAttachmentBytes, 26214400);
      expect(AccordServerLimits.fallback.maxAttachmentsPerMessage, 10);
    });
  });

  group('ServerLimitsController', () {
    test('starts on the fallback limits when logged out', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(serverLimitsControllerProvider),
        AccordServerLimits.fallback,
      );
    });

    test('fetches GET /settings on connect and adopts the server limits',
        () async {
      var settingsRequests = 0;
      final container = _container((request) async {
        if (request.url.path.endsWith('/settings')) {
          settingsRequests += 1;
          return http.Response(
            jsonEncode({
              'data': {
                'max_attachment_size': 1048576,
                'max_attachments_per_message': 3,
                'server_name': 'Example',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });

      // Reading the provider starts the fire-and-forget refresh, and the
      // fallback is what's visible until it lands.
      expect(container.read(serverLimitsControllerProvider),
          AccordServerLimits.fallback);
      await _until(
        () => container.read(serverLimitsControllerProvider).fromServer,
      );

      final limits = container.read(serverLimitsControllerProvider);
      expect(limits.maxAttachmentBytes, 1048576);
      expect(limits.maxAttachmentsPerMessage, 3);
      expect(settingsRequests, 1);
      // It must not hit the admin-only endpoint, which a non-admin can't read.
      expect(container.read(serverLimitsControllerProvider).fromServer, isTrue);
    });

    test('accepts an unenveloped settings body', () async {
      final container = _container((request) async => http.Response(
            jsonEncode({'max_attachment_size': 2048}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      await _until(
        () => container.read(serverLimitsControllerProvider).fromServer,
      );
      expect(
        container.read(serverLimitsControllerProvider).maxAttachmentBytes,
        2048,
      );
    });

    test('keeps the fallback when GET /settings fails', () async {
      final container = _container(
        (request) async => http.Response('{"message":"nope"}', 403),
      );
      container.read(serverLimitsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        container.read(serverLimitsControllerProvider),
        AccordServerLimits.fallback,
      );
    });

    test('keeps the fallback when the request throws', () async {
      final container = _container(
        (request) async => throw http.ClientException('offline'),
      );
      container.read(serverLimitsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        container.read(serverLimitsControllerProvider),
        AccordServerLimits.fallback,
      );
    });

    test('keeps the fallback when the body is not JSON', () async {
      final container = _container(
        (request) async => http.Response('<html>413 Request Entity Too Large',
            413,
            headers: {'content-type': 'text/html'}),
      );
      container.read(serverLimitsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        container.read(serverLimitsControllerProvider),
        AccordServerLimits.fallback,
      );
    });

    test('applies and reverts settings applied directly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller =
          container.read(serverLimitsControllerProvider.notifier);

      controller.applySettings(const {
        'max_attachment_size': 1048576,
        'max_attachments_per_message': 2,
      });
      final tightened = container.read(serverLimitsControllerProvider);
      expect(tightened.maxAttachmentBytes, 1048576);
      expect(tightened.maxAttachmentsPerMessage, 2);

      // A later failure must not leave stale limits in place.
      controller.applySettings(null);
      expect(
        container.read(serverLimitsControllerProvider),
        AccordServerLimits.fallback,
      );
    });
  });

  group('server-driven limits reach the screening', () {
    test('a lowered server size limit rejects a file the fallback allowed', () {
      final limits = AccordServerLimits.fromSettings(const {
        'max_attachment_size': 1024 * 1024,
      });
      final result = screenAttachments(
        [_file('song.mp3', 5 * 1024 * 1024)],
        maxBytes: limits.maxAttachmentBytes,
        maxCount: limits.maxAttachmentsPerMessage,
      );
      expect(result.accepted, isEmpty);
      expect(result.error, contains('song.mp3'));
      expect(result.error, contains('1.0 MB'));
    });

    test('a lowered server count limit is enforced', () {
      final limits = AccordServerLimits.fromSettings(const {
        'max_attachments_per_message': 1,
      });
      final result = screenAttachments(
        [_file('a.png', 8), _file('b.png', 8)],
        maxBytes: limits.maxAttachmentBytes,
        maxCount: limits.maxAttachmentsPerMessage,
      );
      expect(result.accepted.map((f) => f.name), ['a.png']);
      expect(result.error, contains('b.png'));
    });
  });
}
