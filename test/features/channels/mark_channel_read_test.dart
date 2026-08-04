import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/channels/utils/mark_channel_read.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
