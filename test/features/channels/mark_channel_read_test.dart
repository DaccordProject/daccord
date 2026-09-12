import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps a bare [ProviderScope] and captures its [WidgetRef] via [Consumer],
/// mirroring how [markChannelRead] is actually called (from callbacks, with a
/// live [WidgetRef]) rather than a bare [ProviderContainer].
Future<WidgetRef> _pumpRef(WidgetTester tester) async {
  late WidgetRef ref;
  await tester.pumpWidget(
    ProviderScope(
      child: Consumer(
        builder: (context, r, _) {
          ref = r;
          return const SizedBox();
        },
      ),
    ),
  );
  return ref;
}

bool _isUnread(WidgetRef ref, String serverKey, String channelId) =>
    ref.read(readStateControllerProvider(serverKey)).isUnread(channelId);

void _seedUnread(WidgetRef ref, String serverKey, String channelId) =>
    ref
        .read(readStateControllerProvider(serverKey).notifier)
        .markUnread(channelId, spaceId: 's1');

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// A minimal logged-in [AccordAuth] override whose [clientForKey] resolves
/// only [key] to [client] — enough to exercise the REST ack without a real
/// connection/session.
class _Auth extends AccordAuth {
  _Auth(this.key, this.client);
  final String key;
  final AccordClient client;

  @override
  AccordAuthState build() => const AccordAuthLoggedOut();

  @override
  AccordClient? clientForKey(String k) => k == key ? client : null;
}

/// Like [_pumpRef], but with a live [AccordClient] wired to [key] so
/// acknowledgements actually reach the (mocked) REST layer.
Future<WidgetRef> _pumpRefWithClient(
  WidgetTester tester, {
  required String key,
  required AccordClient client,
}) async {
  late WidgetRef ref;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [accordAuthProvider.overrideWith(() => _Auth(key, client))],
      child: Consumer(
        builder: (context, r, _) {
          ref = r;
          return const SizedBox();
        },
      ),
    ),
  );
  return ref;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('markChannelRead', () {
    testWidgets(
      'clears local unread state via an explicit serverKey with no cached '
      'messages and no live client (the voice-channel case)',
      (tester) async {
        final ref = await _pumpRef(tester);
        const key = 'u1@server.test';
        _seedUnread(ref, key, 'c1');
        expect(_isUnread(ref, key, 'c1'), isTrue);

        // No client is connected in this container, so the `channels.ack`
        // REST call resolves to a no-op — the local clear must not depend on
        // it succeeding (or even being attempted).
        markChannelRead(ref, 'c1', serverKey: key, fallbackMessageId: 'm-fallback');

        expect(_isUnread(ref, key, 'c1'), isFalse);
      },
    );

    testWidgets(
      'falls back to the active connection when no serverKey is given',
      (tester) async {
        final ref = await _pumpRef(tester);
        const key = 'active-key';
        ref.read(connectionsControllerProvider.notifier).setActive(key);
        _seedUnread(ref, key, 'c1');

        markChannelRead(ref, 'c1');

        expect(_isUnread(ref, key, 'c1'), isFalse);
      },
    );

    testWidgets(
      'is a no-op when there is no explicit serverKey and no active '
      'connection',
      (tester) async {
        final ref = await _pumpRef(tester);
        const key = 'u1@server.test';
        _seedUnread(ref, key, 'c1');

        markChannelRead(ref, 'c1');

        expect(_isUnread(ref, key, 'c1'), isTrue);
      },
    );

    testWidgets(
      'an explicit serverKey wins over an unrelated active connection',
      (tester) async {
        final ref = await _pumpRef(tester);
        const activeKey = 'active-key';
        const pinnedKey = 'pinned-key';
        ref.read(connectionsControllerProvider.notifier).setActive(activeKey);
        _seedUnread(ref, activeKey, 'c1');
        _seedUnread(ref, pinnedKey, 'c1');

        markChannelRead(ref, 'c1', serverKey: pinnedKey);

        expect(_isUnread(ref, pinnedKey, 'c1'), isFalse);
        expect(_isUnread(ref, activeKey, 'c1'), isTrue);
      },
    );

    testWidgets(
      'acknowledges the newest of tracker position and fallback, not a '
      'stale fallback',
      (tester) async {
        final acked = <String>[];
        final client = AccordClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/ack')) {
              acked.add(jsonDecode(request.body)['message_id'] as String);
            }
            return http.Response('{"data":null}', 200);
          }),
        );
        addTearDown(client.dispose);
        const key = 'u1@server.test';
        final ref = await _pumpRefWithClient(tester, key: key, client: client);

        // The gateway already advanced the tracker past the stale
        // `last_message_id` fallback the caller happens to pass in.
        ref
            .read(readStateControllerProvider(key).notifier)
            .markUnread('c1', spaceId: 's1', messageId: '20');

        markChannelRead(ref, 'c1', serverKey: key, fallbackMessageId: '5');
        await _settle();

        expect(acked, ['20']);
        expect(_isUnread(ref, key, 'c1'), isFalse);
      },
    );
  });
}
