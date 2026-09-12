import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/pending_uploads.dart';
import 'package:bonfire/features/messaging/controllers/withdrawn_attachments.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The gateway side of #329, through the real event handler: AutoMod status
/// events advancing the sender's placeholders, and attachment withdrawals
/// reaching the channel cache, the withdrawn set and the image-cache eviction.

class _FakeGatewayConnection implements GatewayConnection {
  final _messages = StreamController<String>();
  void receive(Map<String, dynamic> frame) => _messages.add(jsonEncode(frame));
  @override
  Future<void> get ready => Future.value();
  @override
  Stream<String> get messages => _messages.stream;
  @override
  void sendText(String text) {}
  @override
  Future<void> close([int? code, String? reason]) => _messages.close();
  @override
  int? closeCode;
  @override
  String? closeReason;
}

class _QuietSettings extends SettingsController {
  @override
  AccordSettings build() =>
      const AccordSettings(notificationsEnabled: false, soundsEnabled: false);
}

const _serverKey = 'u-self@https://accord.example.test';
const _baseUrl = 'https://accord.example.test';
final _refProvider = Provider<Ref>((ref) => ref);

class _Harness {
  _Harness({Map<String, Map<String, Object?>> uploads = const {}}) {
    client = AccordClient(
      baseUrl: _baseUrl,
      gatewayUrl: 'wss://accord.example.test/ws',
      cdnUrl: '$_baseUrl/cdn',
      connectionFactory: (_) => connection,
      httpClient: MockClient((request) async {
        final segments = request.url.pathSegments;
        if (segments.contains('uploads')) {
          final id = segments.last;
          lookups.add(id);
          final body = uploads[id];
          if (body == null) return http.Response('{"error":{}}', 404);
          return http.Response(
            jsonEncode({
              'data': {'id': id, 'message_id': 'm1', ...body},
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );
    addTearDown(client.dispose);
    container = ProviderContainer(
      overrides: [settingsControllerProvider.overrideWith(_QuietSettings.new)],
    );
    addTearDown(container.dispose);
    // Listening opens the channel, which is what lets the handler cache into it.
    container.listen(messages, (_, _) {});
    addTearDown(
      handleAccordEvents(
        container.read(_refProvider),
        client,
        serverKey: _serverKey,
        currentUserId: 'u-self',
        selfDomain: 'accord.example.test',
        isActive: () => true,
      ),
    );
    evicted = [];
    evictCachedImage = (url) async => evicted.add(url);
    addTearDown(() => evictCachedImage = (_) async {});
    client.login();
  }

  final connection = _FakeGatewayConnection();
  late final AccordClient client;
  late final ProviderContainer container;
  final lookups = <String>[];
  late List<String> evicted;

  final messages = accordMessagesControllerProvider(_serverKey, 'c1');

  PendingUploadsSnapshot get pending =>
      container.read(pendingUploadsControllerProvider(_serverKey));
  PendingUploadsController get pendingNotifier =>
      container.read(pendingUploadsControllerProvider(_serverKey).notifier);
  Set<String> get withdrawn =>
      container.read(withdrawnAttachmentsControllerProvider(_serverKey));
  AccordMessage? get cachedM1 =>
      container.read(messages)?.where((m) => m.id == 'm1').firstOrNull;

  /// Seeds the open channel cache with m1 carrying [attachmentIds].
  AccordMessage seedMessage(List<String> attachmentIds) {
    final message = AccordMessage(
      id: 'm1',
      channelId: 'c1',
      spaceId: 's1',
      authorId: 'u-self',
      attachments: [
        for (final id in attachmentIds)
          AccordAttachment(id: id, filename: '$id.png', url: '/cdn/$id.png'),
      ],
    );
    container.read(messages.notifier).addMessage(message);
    return message;
  }

  void event(String type, Map<String, dynamic> data) => connection.receive({
    'op': GatewayOpcodes.event,
    'type': type,
    'data': data,
  });

  void uploadStatus(
    String id,
    String status, {
    String type = 'automod.upload_status',
  }) => event(type, {
    'id': id,
    'message_id': 'm1',
    'channel_id': 'c1',
    'space_id': 's1',
    'status': status,
  });

  Future<void> settle([int ticks = 6]) async {
    for (var i = 0; i < ticks; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  test('a message.update that drops an attachment replaces the cached list, '
      'marks it withdrawn and evicts its image', () async {
    final h = _Harness();
    await h.settle();
    h.seedMessage(['a1', 'a2']);

    h.event('message.update', {
      'id': 'm1',
      'channel_id': 'c1',
      'space_id': 's1',
      'author_id': 'u-self',
      'attachments': [
        {'id': 'a2', 'filename': 'a2.png', 'url': '/cdn/a2.png'},
      ],
    });
    await h.settle();

    expect(h.cachedM1!.attachments.map((a) => a.id), ['a2']);
    expect(h.withdrawn, {'a1'});
    expect(h.evicted, contains('$_baseUrl/cdn/a1.png'));
    expect(h.evicted, isNot(contains('$_baseUrl/cdn/a2.png')));
  });

  test('an edit that keeps its attachments withdraws nothing', () async {
    final h = _Harness();
    await h.settle();
    h.seedMessage(['a1']);

    h.event('message.update', {
      'id': 'm1',
      'channel_id': 'c1',
      'space_id': 's1',
      'content': 'edited',
      'attachments': [
        {'id': 'a1', 'filename': 'a1.png', 'url': '/cdn/a1.png'},
      ],
    });
    await h.settle();

    expect(h.cachedM1!.content, 'edited');
    expect(h.withdrawn, isEmpty);
    expect(h.evicted, isEmpty);
  });

  test('automod.upload_status advances the sender placeholders', () async {
    final h = _Harness();
    await h.settle();
    final message = h.seedMessage([]);
    h.pendingNotifier.track(message, ['u1', 'u2', 'u3']);

    h.uploadStatus('u1', 'published');
    h.uploadStatus('u2', 'quarantined');
    h.uploadStatus('u3', 'rejected');
    h.uploadStatus('u3', 'rejected');
    await h.settle();

    final byId = {for (final u in h.pending.forMessage('m1')) u.id: u.status};
    expect(byId, {'u2': 'quarantined', 'u3': 'rejected'});
  });

  test(
    'a status that beats the 202 is honoured once the upload is tracked',
    () async {
      final h = _Harness();
      await h.settle();
      final message = h.seedMessage([]);

      h.uploadStatus('u9', 'quarantined');
      await h.settle();
      expect(h.pending.uploads, isEmpty);

      h.pendingNotifier.track(message, ['u9']);

      expect(h.pending.forMessage('m1').single.status, 'quarantined');
    },
  );

  test(
    'a refusal of an already-published attachment strips it from the cache',
    () async {
      final h = _Harness();
      await h.settle();
      h.seedMessage(['u1', 'a2']);

      h.uploadStatus('u1', 'removed');
      await h.settle();

      expect(h.cachedM1!.attachments.map((a) => a.id), ['a2']);
      expect(h.withdrawn, {'u1'});
      expect(h.evicted, contains('$_baseUrl/cdn/u1.png'));
    },
  );

  test(
    'the moderator stream never creates a placeholder for a stranger',
    () async {
      final h = _Harness();
      await h.settle();
      final message = h.seedMessage([]);

      h.uploadStatus('u1', 'rejected', type: 'automod.upload_update');
      await h.settle();
      h.pendingNotifier.track(message, ['u1']);

      expect(h.pending.forMessage('m1').single.status, 'pending');
    },
  );

  test(
    'message.update carrying a tracked id publishes the placeholder',
    () async {
      final h = _Harness();
      await h.settle();
      final message = h.seedMessage([]);
      h.pendingNotifier.track(message, ['u1']);

      h.event('message.update', {
        'id': 'm1',
        'channel_id': 'c1',
        'space_id': 's1',
        'attachments': [
          {'id': 'u1', 'filename': 'u1.png', 'url': '/cdn/u1.png'},
        ],
      });
      await h.settle();

      expect(h.pending.uploads, isEmpty);
      expect(h.cachedM1!.attachments.single.id, 'u1');
    },
  );

  test('message.delete drops the message placeholders', () async {
    final h = _Harness();
    await h.settle();
    final message = h.seedMessage([]);
    h.pendingNotifier.track(message, ['u1']);

    h.event('message.delete', {'id': 'm1', 'channel_id': 'c1'});
    await h.settle();

    expect(h.pending.uploads, isEmpty);
    expect(h.cachedM1, isNull);
  });

  test('READY asks the server about each outstanding upload once', () async {
    final h = _Harness(
      uploads: {
        'u1': {'status': 'rejected', 'reason': 'blocked hash'},
      },
    );
    await h.settle();
    final message = h.seedMessage([]);
    h.pendingNotifier.track(message, ['u1', 'u2']);
    h.uploadStatus('u2', 'rejected');
    await h.settle();
    h.lookups.clear();

    h.event('ready', {
      'session_id': 'sess',
      'user': {'id': 'u-self', 'username': 'self'},
    });
    await h.settle(12);

    expect(h.lookups, ['u1', 'u2']);
    expect(h.pending.uploads['u1']!.status, 'rejected');
    expect(h.pending.uploads['u1']!.reason, 'blocked hash');
  });
}
