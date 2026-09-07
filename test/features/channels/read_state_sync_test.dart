import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late ProviderContainer container;
  late ReadStateController reads;
  const provider = readStateControllerProvider;
  setUp(() {
    container = ProviderContainer();
    reads = container.read(provider('server').notifier);
  });
  tearDown(() => container.dispose());

  ReadStateSnapshot snapshot() => container.read(provider('server'));
  void receive(String id, {bool mention = true}) {
    if (reads.receiveMessage('channel', id)) {
      reads.markUnread('channel', messageId: id, isMention: mention);
    }
  }

  AccordClient client(Future<http.Response> Function(http.Request) handler) {
    final result = AccordClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient(handler),
    );
    addTearDown(result.dispose);
    return result;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('replay cannot double-count mentions or undo a remote read', () {
    receive('10');
    receive('10');
    expect(snapshot().mentionCount('channel'), 1);
    reads.applyRemoteRead('channel', '10');
    expect(snapshot().isUnread('channel'), isFalse);
    expect(reads.receiveMessage('channel', '10'), isFalse);
    receive('11');
    expect(snapshot().mentionCount('channel'), 1);
  });

  test('delayed remote acknowledgement preserves newer mentions', () {
    receive('9');
    receive('10');
    reads.applyRemoteRead('channel', '9');
    expect(snapshot().isUnread('channel'), isTrue);
    expect(snapshot().mentionCount('channel'), 1);
    reads.applyRemoteRead('channel', '8');
    expect(snapshot().mentionCount('channel'), 1);
    reads.applyRemoteRead('channel', '10');
    expect(snapshot().isUnread('channel'), isFalse);
  });

  test('READY positions suppress replay and retain newer unread', () {
    reads.hydrate(const [
      ReadEntry(
        channelId: 'channel',
        lastMessageId: '20',
        lastReadMessageId: '10',
        mentions: 2,
      ),
    ]);
    expect(reads.receiveMessage('channel', '20'), isFalse);
    reads.applyRemoteRead('channel', '15');
    expect(snapshot().isUnread('channel'), isTrue);
    reads.applyRemoteRead('channel', '20');
    expect(snapshot().isUnread('channel'), isFalse);
  });

  test(
    'acknowledgements serialize and coalesce to the newest message',
    () async {
      final requests = <String>[];
      final first = Completer<http.Response>();
      final api = client((request) async {
        requests.add(jsonDecode(request.body)['message_id'] as String);
        if (requests.length == 1) return first.future;
        return http.Response('{"data":null}', 200);
      });
      receive('9');
      reads.acknowledge(api, 'channel', '9');
      reads.acknowledge(api, 'channel', '10');
      reads.acknowledge(api, 'channel', '11');
      await settle();
      expect(requests, ['9']);
      first.complete(http.Response('{"data":null}', 200));
      await settle();
      expect(requests, ['9', '11']);
      reads.acknowledge(api, 'channel', '10');
      reads.acknowledge(api, 'channel', '11');
      await settle();
      expect(requests, ['9', '11']);
    },
  );

  test('failed ack retries on reconnect and stale READY stays read', () async {
    var fail = true;
    final requests = <String>[];
    final api = client((request) async {
      requests.add(jsonDecode(request.body)['message_id'] as String);
      return http.Response('{"data":null}', fail ? 403 : 200);
    });
    receive('20');
    reads.acknowledge(api, 'channel', '20');
    await settle();
    reads.hydrate(const [
      ReadEntry(
        channelId: 'channel',
        lastMessageId: '20',
        lastReadMessageId: '10',
      ),
    ]);
    expect(snapshot().isUnread('channel'), isFalse);
    fail = false;
    reads.retryPending(api);
    await settle();
    expect(requests, ['20', '20']);
    reads.hydrate(const [
      ReadEntry(
        channelId: 'channel',
        lastMessageId: '21',
        lastReadMessageId: '20',
      ),
    ]);
    expect(snapshot().isUnread('channel'), isTrue);
  });

  test('snowflakes compare exactly across digit lengths and web precision', () {
    expect(compareMessageIds('10', '9'), greaterThan(0));
    expect(
      compareMessageIds('9007199254740993', '9007199254740992'),
      greaterThan(0),
    );
  });
}
