import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A [DmChannelsController] exposing a fixed conversation list, so the DM
/// dialog renders without a server.
class _FakeDmChannels extends DmChannelsController {
  _FakeDmChannels(this._channels);

  final List<AccordChannel> _channels;

  @override
  List<AccordChannel>? build(String serverKey) => _channels;
}

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

AccordMessage _message(String author, String content, DateTime sentAt) =>
    AccordMessage(
      id: 'm-$content',
      channelId: 'dm1',
      authorId: author,
      content: content,
      timestamp: sentAt.toUtc().toIso8601String(),
    );

/// Signed in as [userId], with a client that answers every request with an
/// empty list so nothing reaches the network.
AccordAuthLoggedIn _loggedIn(String userId) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient((_) async => http.Response('[]', 200)),
  );
  addTearDown(client.dispose);
  return AccordAuthLoggedIn(
    client: client,
    session: AccordSession(
      server: server,
      token: 'test-token',
      userId: userId,
      username: 'me',
    ),
  );
}

void main() {
  late ProviderContainer container;

  /// Recreates [container] with bob (`u2`) at the given presence and name,
  /// signed in as [selfId] when given.
  void useConversation({
    String name = 'bob',
    String? status,
    String? selfId,
    String? origin,
  }) {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        if (selfId != null)
          accordAuthProvider.overrideWithValue(_loggedIn(selfId)),
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
        if (status != null)
          activePresencesProvider.overrideWithValue(
            PresenceMap(
              byUser: {'u2': AccordPresence(userId: 'u2', status: status)},
            ),
          ),
        dmChannelsControllerProvider('').overrideWith(
          () => _FakeDmChannels([
            AccordChannel(
              id: 'dm1',
              type: 'dm',
              recipients: [
                AccordUser(id: 'u2', username: name, origin: origin),
              ],
            ),
          ]),
        ),
      ],
    );
  }

  /// Renders the app at a phone-sized logical [width].
  void useWidth(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 740);
    addTearDown(tester.view.reset);
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAccordDirectMessages(context),
                child: const Text('open dms'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open dms'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    container = ProviderContainer();
    useConversation();
  });

  tearDown(() => container.dispose());

  testWidgets('row shows the preview and its last-activity time', (
    tester,
  ) async {
    final sentAt = DateTime.now().subtract(const Duration(days: 1));
    container
        .read(dmChannelsControllerProvider('').notifier)
        .setPreview('dm1', _message('u2', 'Near the beach', sentAt));

    await openDialog(tester);

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Near the beach'), findsOneWidget);
    expect(find.text(conversationTimeString(sentAt)), findsOneWidget);
  });

  testWidgets('zone-less UTC preview time displays in device local time', (
    tester,
  ) async {
    final instant = DateTime.utc(2026, 9, 28, 16, 15);
    final message = _message('u2', 'UTC preview', instant)
      ..timestamp = '2026-09-28 16:15:00';
    container
        .read(dmChannelsControllerProvider('').notifier)
        .setPreview('dm1', message);

    await openDialog(tester);

    final local = instant.toLocal();
    expect(find.text('UTC preview'), findsOneWidget);
    expect(find.text(conversationTimeString(local)), findsOneWidget);
    expect(find.byTooltip(messageTimestampString(local)), findsOneWidget);
  });

  testWidgets('a preview without a time shows no time label', (tester) async {
    await openDialog(tester);

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);
  });

  testWidgets('a wide row shows the origin badge with its domain', (
    tester,
  ) async {
    useConversation(origin: 'remote.example');

    await openDialog(tester);

    expect(find.text('@remote.example'), findsOneWidget);
  });

  testWidgets('header actions are compact icon buttons', (tester) async {
    await openDialog(tester);

    expect(find.byTooltip('New group'), findsOneWidget);
    expect(find.byTooltip('Message remote user'), findsOneWidget);
  });

  group('row semantics', () {
    testWidgets('an unread row with mentions announces them and presence', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      useConversation(status: 'online');
      final sentAt = DateTime.now().subtract(const Duration(days: 1));
      container
          .read(dmChannelsControllerProvider('').notifier)
          .setPreview('dm1', _message('u2', 'Near the beach', sentAt));
      final readState = container.read(
        readStateControllerProvider('').notifier,
      );
      readState.markUnread('dm1', isMention: true);
      readState.markUnread('dm1', isMention: true);

      await openDialog(tester);

      expect(
        find.bySemanticsLabel(
          'bob, online, Unread, 2 mentions, Near the beach, '
          '${messageTimestampString(sentAt)}',
        ),
        findsOneWidget,
      );
      // The badge is folded into the row label, not read as a bare "2".
      expect(find.bySemanticsLabel('2'), findsNothing);
      semantics.dispose();
    });

    testWidgets('a single mention is singular', (tester) async {
      final semantics = tester.ensureSemantics();
      container
          .read(readStateControllerProvider('').notifier)
          .markUnread('dm1', isMention: true);

      await openDialog(tester);

      expect(
        find.bySemanticsLabel(RegExp(r'Unread, 1 mention$')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('an unread row without mentions says Unread only', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      useConversation(status: 'dnd');
      container
          .read(readStateControllerProvider('').notifier)
          .markUnread('dm1');

      await openDialog(tester);

      expect(
        find.bySemanticsLabel('bob, do not disturb, Unread'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a read row is not announced as unread', (tester) async {
      final semantics = tester.ensureSemantics();
      useConversation(status: 'idle');

      await openDialog(tester);

      expect(find.bySemanticsLabel('bob, idle'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Unread')), findsNothing);
      semantics.dispose();
    });

    testWidgets('a user with no presence is announced offline', (tester) async {
      final semantics = tester.ensureSemantics();

      await openDialog(tester);

      expect(find.bySemanticsLabel('bob, offline'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a remote user is announced with their home domain', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      useConversation(origin: 'remote.example', status: 'online');

      await openDialog(tester);

      expect(
        find.bySemanticsLabel('bob, homed on remote.example, online'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('the row stays tappable for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();

      await openDialog(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('bob, offline')),
        matchesSemantics(
          label: 'bob, offline',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('own-message previews', () {
    testWidgets('your own last message is prefixed "You:"', (tester) async {
      final semantics = tester.ensureSemantics();
      useConversation(selfId: 'me');
      container
          .read(dmChannelsControllerProvider('').notifier)
          .setPreview('dm1', _message('me', 'On my way', DateTime.now()));

      await openDialog(tester);

      expect(find.text('You: On my way'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('You: On my way')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets("the other user's message has no prefix", (tester) async {
      useConversation(selfId: 'me');
      container
          .read(dmChannelsControllerProvider('').notifier)
          .setPreview('dm1', _message('u2', 'On my way', DateTime.now()));

      await openDialog(tester);

      expect(find.text('On my way'), findsOneWidget);
      expect(find.textContaining('You:'), findsNothing);
    });
  });

  group('narrow mobile widths', () {
    const longName =
        'a_really_quite_remarkably_long_username_that_cannot_possibly_fit';
    const longPreview =
        'This preview is long enough that it has to be truncated on a phone';

    for (final width in [320.0, 375.0]) {
      testWidgets('a long name uses the full row at ${width.toInt()}px '
          'when there is no time', (tester) async {
        useWidth(tester, width);
        useConversation(name: longName);
        container
            .read(dmChannelsControllerProvider('').notifier)
            .setPreview(
              'dm1',
              AccordMessage(
                id: 'm1',
                channelId: 'dm1',
                authorId: 'u2',
                content: longPreview,
              ),
            );

        await openDialog(tester);

        expect(tester.takeException(), isNull);
        final titleWidth = tester.getSize(find.text(longName)).width;
        final previewWidth = tester.getSize(find.text(longPreview)).width;
        // Both lines are truncated to the same text column: the title is not
        // squeezed into half of it.
        expect(titleWidth, moreOrLessEquals(previewWidth, epsilon: 1));
      });

      testWidgets('a long name leaves room for the time and badge at '
          '${width.toInt()}px', (tester) async {
        useWidth(tester, width);
        useConversation(
          name: longName,
          status: 'online',
          origin: 'remote.example',
        );
        final sentAt = DateTime.now();
        container
            .read(dmChannelsControllerProvider('').notifier)
            .setPreview('dm1', _message('u2', longPreview, sentAt));
        final readState = container.read(
          readStateControllerProvider('').notifier,
        );
        for (var i = 0; i < 12; i++) {
          readState.markUnread('dm1', isMention: true);
        }

        await openDialog(tester);

        expect(tester.takeException(), isNull);
        final time = find.text(conversationTimeString(sentAt));
        expect(time, findsOneWidget);
        expect(find.text('12'), findsOneWidget);
        final titleRect = tester.getRect(find.text(longName));
        // Too narrow for the "@domain" text: the badge keeps its globe.
        expect(find.text('@remote.example'), findsNothing);
        final originRect = tester.getRect(find.byIcon(Icons.public));
        final timeRect = tester.getRect(time);
        // Name, then the origin badge beside it, then the time at the end.
        expect(titleRect.right, lessThanOrEqualTo(originRect.left));
        expect(originRect.right, lessThanOrEqualTo(timeRect.left));
        expect(timeRect.right, lessThanOrEqualTo(width));
      });
    }
  });
}
