import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _spaceId = 'space';
const _channelId = 'channel';
const _selfId = 'self';
const _permissionHint =
    "You don't have permission to mention @everyone or @here in this channel.";

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();

  @override
  void setDraft(String channelId, String text) {}
}

class _Harness {
  _Harness({
    required List<String> everyonePermissions,
    List<AccordPermissionOverwrite> overwrites = const [],
    String ownerId = 'owner',
    bool isDm = false,
  }) {
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    client = AccordClient(
      token: 'token',
      baseUrl: server.baseUrl,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/messages')) {
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'data': {}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    channel = AccordChannel(
      id: _channelId,
      spaceId: isDm ? null : _spaceId,
      name: 'general',
      permissionOverwrites: overwrites,
    );
    final space = AccordSpace(
      id: _spaceId,
      ownerId: ownerId,
      roles: [
        AccordRole(
          id: 'everyone',
          name: '@everyone',
          position: 0,
          permissions: everyonePermissions,
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(
          AccordAuthLoggedIn(
            client: client,
            session: AccordSession(
              server: server,
              token: 'token',
              userId: _selfId,
              username: 'Self',
            ),
          ),
        ),
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
        spacesControllerProvider.overrideWithValue([space]),
        accordMembersControllerProvider(_spaceId).overrideWithValue({
          _selfId: AccordMember(userId: _selfId, spaceId: _spaceId),
        }),
      ],
    );
  }

  late final AccordClient client;
  late final AccordChannel channel;
  late final ProviderContainer container;

  Widget get app => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(
        body: MessagePane(
          channel: channel,
          channelId: _channelId,
          spaceId: channel.spaceId,
        ),
      ),
    ),
  );

  void dispose() => client.dispose();
}

Future<_Harness> _pump(
  WidgetTester tester, {
  List<String> permissions = const [AccordPermission.sendMessages],
  List<AccordPermissionOverwrite> overwrites = const [],
  String ownerId = 'owner',
  bool isDm = false,
}) async {
  final harness = _Harness(
    everyonePermissions: permissions,
    overwrites: overwrites,
    ownerId: ownerId,
    isDm: isDm,
  );
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.app);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return harness;
}

Finder get _composer => find.byType(TextField).last;

void main() {
  testWidgets('shows a non-blocking hint without mention permission', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(_composer, 'Hello @everyone');
    await tester.pump();

    expect(find.text(_permissionHint), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('channel overwrite grants broadcast mention permission', (
    tester,
  ) async {
    await _pump(
      tester,
      overwrites: [
        AccordPermissionOverwrite(
          id: 'everyone',
          type: 'role',
          allow: [AccordPermission.mentionEveryone],
        ),
      ],
    );

    await tester.enterText(_composer, 'Hello @here');
    await tester.pump();

    expect(find.text(_permissionHint), findsNothing);
  });

  testWidgets('space owner bypass is not gated by channel denies', (
    tester,
  ) async {
    await _pump(
      tester,
      ownerId: _selfId,
      overwrites: [
        AccordPermissionOverwrite(
          id: 'everyone',
          type: 'role',
          deny: [AccordPermission.mentionEveryone],
        ),
      ],
    );

    await tester.enterText(_composer, 'Hello @everyone');
    await tester.pump();

    expect(find.text(_permissionHint), findsNothing);
  });

  testWidgets('broadcast autocomplete is offered first with permission', (
    tester,
  ) async {
    await _pump(
      tester,
      permissions: const [
        AccordPermission.sendMessages,
        AccordPermission.mentionEveryone,
      ],
    );

    await tester.enterText(_composer, '@');
    await tester.pump();

    expect(find.text('@everyone'), findsOneWidget);
    expect(find.text('@here'), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('@everyone')).dy,
      lessThan(tester.getTopLeft(find.text('@here')).dy),
    );

    await tester.enterText(_composer, '@h');
    await tester.pump();
    expect(find.text('@everyone'), findsNothing);
    expect(find.text('@here'), findsOneWidget);
  });

  testWidgets('picking broadcast completion inserts the literal token', (
    tester,
  ) async {
    await _pump(
      tester,
      permissions: const [
        AccordPermission.sendMessages,
        AccordPermission.mentionEveryone,
      ],
    );

    await tester.enterText(_composer, '@ever');
    await tester.pump();
    expect(find.text('@everyone'), findsOneWidget);
    expect(find.text('@here'), findsNothing);
    await tester.tap(find.text('@everyone'));
    await tester.pump();

    expect(tester.widget<TextField>(_composer).controller?.text, '@everyone ');
  });

  testWidgets('broadcast autocomplete is hidden without permission', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(_composer, '@');
    await tester.pump();

    expect(find.text('@everyone'), findsNothing);
    expect(find.text('@here'), findsNothing);
  });

  testWidgets('broadcast autocomplete is absent in DMs', (tester) async {
    await _pump(
      tester,
      isDm: true,
      permissions: const [AccordPermission.mentionEveryone],
    );

    await tester.enterText(_composer, '@');
    await tester.pump();

    expect(find.text('@everyone'), findsNothing);
    expect(find.text('@here'), findsNothing);
  });
}
