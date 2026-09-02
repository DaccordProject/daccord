import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/hidden_messages.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/messaging/views/thread_view.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The thread root is never in [ThreadRepliesController]'s list, so the
/// visibility filter that hides a reported message or a blocked author's
/// replies everywhere else (#290) never reached it — a reported/blocked root
/// kept rendering at the top of its own thread. These hold the fix: opening
/// (or staying in) a thread whose root the visibility filter would hide now
/// closes the thread instead.

const _channelId = 'c1';
const _rootId = 'root1';
const _selfId = 'u1';
const _themId = 'u2';

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

class _FakeHiddenMessages extends HiddenMessagesController {
  _FakeHiddenMessages(this.initial);

  final Set<String> initial;

  @override
  Set<String> build() => initial;
}

class _FakeBlockedUsers extends BlockedUsersController {
  _FakeBlockedUsers(this.initial);

  final Set<String> initial;

  @override
  Set<String> build(String serverKey) => initial;
}

class _FakeThreadReplies extends ThreadRepliesController {
  @override
  List<AccordMessage>? build(
    String serverKey,
    String channelId,
    String rootId,
  ) => const [];
}

AccordMessage get _root => AccordMessage(
  id: _rootId,
  channelId: _channelId,
  authorId: _themId,
  content: 'root content',
  timestamp: '2026-01-01T10:00:00Z',
);

class _Harness {
  _Harness({Set<String> hidden = const {}, Set<String> blocked = const {}}) {
    final responder = MockClient(
      (request) async => http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    client = AccordClient(
      token: 'test-token',
      tokenType: 'Bearer',
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
      httpClient: responder,
    );
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(
          AccordAuthLoggedIn(
            client: client,
            session: AccordSession(
              server: server,
              token: 'test-token',
              userId: _selfId,
              username: 'self',
            ),
          ),
        ),
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
        hiddenMessagesControllerProvider.overrideWith(
          () => _FakeHiddenMessages(hidden),
        ),
        blockedUsersControllerProvider(
          '',
        ).overrideWith(() => _FakeBlockedUsers(blocked)),
        threadRepliesControllerProvider(
          '',
          _channelId,
          _rootId,
        ).overrideWith(_FakeThreadReplies.new),
      ],
    );
  }

  late final AccordClient client;
  late final ProviderContainer container;
  bool closeCalled = false;
  ThreadResult? closedWith;

  Widget get app => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(
        body: AccordThreadPane(
          channelId: _channelId,
          spaceId: null,
          root: _root,
          canManageMessages: false,
          onClose: (result) {
            closeCalled = true;
            closedWith = result;
          },
        ),
      ),
    ),
  );

  void dispose() => client.dispose();
}

Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'a thread whose root author the user already blocked closes rather '
    'than showing it',
    (tester) async {
      final harness = _Harness(blocked: {_themId});
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app);
      await _tick(tester);

      expect(harness.closeCalled, isTrue);
      // Not a delete: nothing should treat this as the post having been
      // removed (that would drop it from a shared list like the forum board).
      expect(harness.closedWith, isNull);
    },
  );

  testWidgets(
    'a thread whose root the user already reported closes rather than '
    'showing it',
    (tester) async {
      final harness = _Harness(hidden: {_rootId});
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app);
      await _tick(tester);

      expect(harness.closeCalled, isTrue);
      expect(harness.closedWith, isNull);
    },
  );

  testWidgets('a thread whose root is visible stays open and shown', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app);
    await _tick(tester);

    expect(harness.closeCalled, isFalse);
    expect(find.text('root content', findRichText: true), findsOneWidget);
  });
}
