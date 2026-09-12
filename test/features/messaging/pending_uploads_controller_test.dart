import 'dart:convert';
import 'dart:io';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/pending_uploads.dart';
import 'package:bonfire/features/messaging/utils/pending_upload_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The pure reconcile logic behind the sender's "attachment processing"
/// placeholder (#329): a 202's upload ids, the uploader status events that
/// advance them (in any order, any number of times), and the post-READY
/// status lookups.

const _serverKey = 'u-self@https://accord.example.test';

final _message = AccordMessage(id: 'm1', channelId: 'c1', spaceId: 's1');

AccordAutomodUploadStatus _event(
  String id,
  String status, {
  String messageId = 'm1',
}) => AccordAutomodUploadStatus(
  id: id,
  messageId: messageId,
  channelId: 'c1',
  spaceId: 's1',
  status: status,
);

ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

PendingUploadsController _notifier(ProviderContainer c) =>
    c.read(pendingUploadsControllerProvider(_serverKey).notifier);

PendingUploadsSnapshot _state(ProviderContainer c) =>
    c.read(pendingUploadsControllerProvider(_serverKey));

/// A client whose `GET /automod/uploads/{id}` answers from [uploads] (a 404
/// for ids it doesn't list), recording every id asked about in [asked].
AccordClient _clientAnswering(
  Map<String, Map<String, Object?>> uploads, {
  required List<String> asked,
}) {
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: 'https://accord.example.test',
    gatewayUrl: 'wss://accord.example.test/ws',
    httpClient: MockClient((request) async {
      final segments = request.url.pathSegments;
      expect(
        segments.contains('uploads'),
        isTrue,
        reason: 'only the status lookup may be called: ${request.url}',
      );
      final id = segments.last;
      asked.add(id);
      final body = uploads[id];
      if (body == null) {
        return http.Response(
          jsonEncode({
            'error': {'code': 'NOT_FOUND', 'message': 'unknown upload'},
          }),
          404,
        );
      }
      return http.Response(
        jsonEncode({
          'data': {'id': id, 'message_id': 'm1', ...body},
        }),
        200,
      );
    }),
  );
  addTearDown(client.dispose);
  return client;
}

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('tracking', () {
    test('a 202 records one pending entry per upload id', () {
      final c = _container();
      _notifier(c).track(_message, ['u1', 'u2']);

      final mine = _state(c).forMessage('m1');
      expect(mine.map((u) => u.id), ['u1', 'u2']);
      expect(mine.every((u) => u.isOutstanding), isTrue);
      expect(mine.first.channelId, 'c1');
      expect(mine.first.spaceId, 's1');
      expect(_state(c).forMessage('other'), isEmpty);
    });

    test('tracking the same ids twice does not duplicate them', () {
      final c = _container();
      _notifier(c).track(_message, ['u1']);
      _notifier(c).track(_message, ['u1']);

      expect(_state(c).uploads.length, 1);
    });
  });

  group('status events', () {
    test('published drops the placeholder', () {
      final c = _container();
      _notifier(c).track(_message, ['u1', 'u2']);

      _notifier(c).applyStatus(_event('u1', AutomodUploadStatus.published));

      expect(_state(c).forMessage('m1').map((u) => u.id), ['u2']);
    });

    test('quarantined then rejected keeps a placeholder with that status', () {
      final c = _container();
      _notifier(c).track(_message, ['u1']);

      _notifier(c).applyStatus(_event('u1', AutomodUploadStatus.quarantined));
      expect(_state(c).forMessage('m1').single.status, 'quarantined');
      expect(_state(c).forMessage('m1').single.isOutstanding, isTrue);

      _notifier(c).applyStatus(_event('u1', AutomodUploadStatus.rejected));
      final refused = _state(c).forMessage('m1').single;
      expect(refused.status, 'rejected');
      expect(refused.isRefused, isTrue);
      expect(refused.isOutstanding, isFalse);
      expect(_state(c).hasOutstanding, isFalse);
    });

    test('removed is a refusal too', () {
      final c = _container();
      _notifier(c).track(_message, ['u1']);

      _notifier(c).applyStatus(_event('u1', AutomodUploadStatus.removed));

      expect(_state(c).forMessage('m1').single.isRefused, isTrue);
    });

    test('a repeated event is a no-op', () {
      final c = _container();
      _notifier(c).track(_message, ['u1']);
      _notifier(c).applyStatus(_event('u1', AutomodUploadStatus.quarantined));
      final before = _state(c);

      _notifier(c).applyStatus(_event('u1', AutomodUploadStatus.quarantined));

      expect(identical(_state(c), before), isTrue);
      expect(_state(c).forMessage('m1'), hasLength(1));
    });

    test('an event that beats the 202 is applied once the id is tracked', () {
      final c = _container();
      _notifier(c).applyStatus(_event('u1', AutomodUploadStatus.quarantined));
      expect(_state(c).uploads, isEmpty);

      _notifier(c).track(_message, ['u1', 'u2']);

      final byId = _state(c).uploads;
      expect(byId['u1']!.status, 'quarantined');
      expect(byId['u2']!.status, 'pending');
    });

    test('a published event that beats the 202 means nothing to track', () {
      final c = _container();
      _notifier(c).applyStatus(_event('u1', AutomodUploadStatus.published));

      _notifier(c).track(_message, ['u1']);

      expect(_state(c).uploads, isEmpty);
    });

    test('unknown ids from the moderator stream are not buffered', () {
      final c = _container();
      _notifier(c).applyStatus(
        _event('u1', AutomodUploadStatus.rejected),
        bufferUnknown: false,
      );

      _notifier(c).track(_message, ['u1']);

      expect(_state(c).uploads['u1']!.status, 'pending');
    });

    test(
      'a refusal fetches the reason for our own upload exactly once',
      () async {
        final c = _container();
        final asked = <String>[];
        final client = _clientAnswering({
          'u1': {'status': 'rejected', 'reason': 'explicit content'},
        }, asked: asked);
        _notifier(c).track(_message, ['u1']);

        _notifier(c).applyStatus(
          _event('u1', AutomodUploadStatus.rejected),
          client: client,
        );
        _notifier(c).applyStatus(
          _event('u1', AutomodUploadStatus.rejected),
          client: client,
        );
        await _settle();

        expect(asked, ['u1']);
        expect(_state(c).uploads['u1']!.reason, 'explicit content');
      },
    );

    test(
      'a reason lookup that 404s leaves the reported status alone',
      () async {
        final c = _container();
        final client = _clientAnswering({}, asked: []);
        _notifier(c).track(_message, ['u1']);

        _notifier(c).applyStatus(
          _event('u1', AutomodUploadStatus.quarantined),
          client: client,
        );
        await _settle();

        expect(_state(c).uploads['u1']!.status, 'quarantined');
        expect(_state(c).uploads['u1']!.reason, isNull);
      },
    );

    test('a pending event fetches nothing', () async {
      final c = _container();
      final asked = <String>[];
      final client = _clientAnswering({}, asked: asked);
      _notifier(c).track(_message, ['u1'], client: client);

      _notifier(
        c,
      ).applyStatus(_event('u1', AutomodUploadStatus.pending), client: client);
      await _settle();

      expect(asked, isEmpty);
    });
  });

  group('message lifecycle', () {
    test(
      'an update carrying a tracked id as a real attachment publishes it',
      () {
        final c = _container();
        _notifier(c).track(_message, ['u1', 'u2']);

        _notifier(c).applyPublishedAttachments(
          AccordMessage(
            id: 'm1',
            channelId: 'c1',
            attachments: [AccordAttachment(id: 'u1', url: '/cdn/u1.png')],
          ),
        );

        expect(_state(c).forMessage('m1').map((u) => u.id), ['u2']);
      },
    );

    test('deleting the message drops its placeholders', () {
      final c = _container();
      _notifier(c).track(_message, ['u1']);
      _notifier(c).track(AccordMessage(id: 'm2', channelId: 'c1'), ['u2']);

      _notifier(c).clearForMessage('m1');

      expect(_state(c).forMessage('m1'), isEmpty);
      expect(_state(c).forMessage('m2'), hasLength(1));
    });
  });

  group('reconcile', () {
    tearDown(() {
      PendingUploadsController.fallbackPollInterval = const Duration(
        seconds: 45,
      );
      PendingUploadsController.maxFallbackPolls = 4;
    });

    test(
      'asks about each outstanding upload once and applies the answers',
      () async {
        final c = _container();
        final asked = <String>[];
        final client = _clientAnswering({
          'u1': {'status': 'published'},
          'u2': {'status': 'rejected', 'reason': 'blocked hash'},
          'u3': {'status': 'quarantined'},
        }, asked: asked);
        _notifier(c).track(_message, ['u1', 'u2', 'u3', 'u4']);
        // Already refused: nothing left to ask.
        _notifier(c).applyStatus(_event('u4', AutomodUploadStatus.rejected));

        await _notifier(c).reconcile(client);

        expect(asked, ['u1', 'u2', 'u3']);
        final byId = _state(c).uploads;
        expect(byId.containsKey('u1'), isFalse);
        expect(byId['u2']!.status, 'rejected');
        expect(byId['u2']!.reason, 'blocked hash');
        expect(byId['u3']!.status, 'quarantined');
        expect(byId['u4']!.status, 'rejected');
      },
    );

    test('a 404 means the server no longer holds it: removed', () async {
      final c = _container();
      final client = _clientAnswering({}, asked: []);
      _notifier(c).track(_message, ['u1']);

      await _notifier(c).reconcile(client);

      expect(_state(c).uploads['u1']!.status, 'removed');
    });

    test(
      'polls a bounded number of times while something stays pending',
      () async {
        PendingUploadsController.fallbackPollInterval = const Duration(
          milliseconds: 5,
        );
        PendingUploadsController.maxFallbackPolls = 2;
        final c = _container();
        final asked = <String>[];
        final client = _clientAnswering({
          'u1': {'status': 'pending'},
        }, asked: asked);
        _notifier(c).track(_message, ['u1']);

        await _notifier(c).reconcile(client);
        await Future<void>.delayed(const Duration(milliseconds: 80));

        // The reconcile lookup plus exactly maxFallbackPolls polls, then quiet.
        expect(asked, ['u1', 'u1', 'u1']);
        expect(_state(c).uploads['u1']!.status, 'pending');
      },
    );

    test('polling stops as soon as nothing is outstanding', () async {
      PendingUploadsController.fallbackPollInterval = const Duration(
        milliseconds: 5,
      );
      PendingUploadsController.maxFallbackPolls = 3;
      final c = _container();
      final asked = <String>[];
      final client = _clientAnswering({
        'u1': {'status': 'pending'},
      }, asked: asked);
      _notifier(c).track(_message, ['u1']);

      await _notifier(c).reconcile(client);
      _notifier(c).applyStatus(_event('u1', AutomodUploadStatus.published));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(asked, ['u1']);
    });
  });

  group('persistence', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('pending-uploads-test');
      Hive.init(tempDir.path);
      await Hive.openBox(PendingUploadStore.boxName);
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk(PendingUploadStore.boxName);
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'tracked uploads survive a restart, scoped to their connection',
      () async {
        final first = _container();
        _notifier(first).track(_message, ['u1']);
        _notifier(
          first,
        ).applyStatus(_event('u1', AutomodUploadStatus.quarantined));
        await _settle();

        final second = _container();
        final restored = _state(second).uploads['u1'];
        expect(restored, isNotNull);
        expect(restored!.messageId, 'm1');
        expect(restored.status, 'quarantined');
        expect(
          second.read(pendingUploadsControllerProvider('someone-else')).uploads,
          isEmpty,
        );
      },
    );

    test('a published upload is gone after a restart too', () async {
      final first = _container();
      _notifier(first).track(_message, ['u1']);
      _notifier(first).applyStatus(_event('u1', AutomodUploadStatus.published));
      await _settle();

      expect(_state(_container()).uploads, isEmpty);
    });
  });
}
