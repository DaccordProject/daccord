import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/views/channel_permissions.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Responsive layout of the channel permission editor (#328).
///
/// On desktop the dialog keeps its two panes (200px selector list beside the
/// editor). On a phone that left the editor a few dozen pixels wide, so labels
/// wrapped letter-by-letter and the footer could end up off-screen. Below the
/// breakpoint the selector becomes a horizontal chip strip and the editor gets
/// the full width.

const _spaceId = 'space1';
const _channelId = 'c1';
const _selfId = 'u1';
const _memberId = 'u2';

const _phone = Size(390, 844);
const _desktop = Size(1024, 768);

class _Harness {
  _Harness() {
    final responder = MockClient((request) async {
      final path = request.url.path;
      requests.add('${request.method} $path');
      // One existing member overwrite, so the selector also lists a member
      // (chips only exist for members that carry an overwrite).
      final data = path.endsWith('/channels/$_channelId/permissions')
          ? [
              {
                'id': _memberId,
                'type': 'member',
                'allow': ['view_channel'],
                'deny': <String>[],
              },
            ]
          : <Object>[];
      return http.Response(
        jsonEncode({'data': data}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    client = AccordClient(
      token: 'test-token',
      tokenType: 'Bearer',
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
      httpClient: responder,
    );
    final space = AccordSpace(
      id: _spaceId,
      ownerId: _selfId,
      roles: [
        AccordRole(id: 'everyone', name: '@everyone', position: 0),
        AccordRole(id: 'mod', name: 'Moderator', position: 1),
      ],
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
        spacesControllerProvider.overrideWithValue([space]),
        accordMembersControllerProvider('', _spaceId).overrideWithValue({
          _memberId: AccordMember(
            userId: _memberId,
            spaceId: _spaceId,
            user: AccordUser(id: _memberId, username: 'alice'),
          ),
        }),
      ],
    );
  }

  final List<String> requests = [];
  late final AccordClient client;
  late final ProviderContainer container;

  Widget app({double textScale = 1}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showChannelPermissionsDialog(
              context,
              spaceId: _spaceId,
              channel: AccordChannel(
                id: _channelId,
                spaceId: _spaceId,
                name: 'general',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  void dispose() => container.dispose();
}

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<_Harness> _open(
  WidgetTester tester,
  Size surface, {
  double textScale = 1,
}) async {
  _useSurface(tester, surface);
  final h = _Harness();
  addTearDown(h.dispose);
  await tester.pumpWidget(h.app(textScale: textScale));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(h.requests, contains('GET /api/v1/channels/$_channelId/permissions'));
  return h;
}

/// The nearest [Row] holding a permission label and its three buttons.
Finder _permissionRow(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(Row)).first;

/// The tri-state button box (the square [Container]) around [icon] in the
/// permission row labelled [label].
Finder _triButton(String label, IconData icon) => find
    .ancestor(
      of: find.descendant(
        of: _permissionRow(label),
        matching: find.byIcon(icon),
      ),
      matching: find.byType(Container),
    )
    .first;

/// Asserts the permission label [label] has real room: a column of at least
/// 180px and no more than [maxLines] rendered lines. Note the test font draws
/// every glyph as a 14px square, so at 180-200px only ~13 glyphs fit per
/// line — "View Channel" (12) is the single-line probe; longer labels are
/// allowed a second line here even though a real font keeps them on one.
void _expectLabelRoom(WidgetTester tester, String label, {int maxLines = 1}) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
  expect(paragraph.didExceedMaxLines, isFalse, reason: '"$label" was clipped');
  expect(
    paragraph.constraints.maxWidth,
    greaterThanOrEqualTo(180),
    reason: '"$label" column is squeezed (${paragraph.constraints})',
  );
  final oneLine = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
  ).preferredLineHeight;
  expect(
    paragraph.size.height,
    lessThan(oneLine * (maxLines + 0.5)),
    reason:
        '"$label" should fit on $maxLines line(s) '
        '(size ${paragraph.size}, constraints ${paragraph.constraints})',
  );
}

void main() {
  // A tap that lands off-screen must fail, not silently no-op: every tap
  // below is meant to prove the target is reachable on a phone.
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets('desktop keeps the two-pane layout', (tester) async {
    await _open(tester, _desktop);

    expect(tester.takeException(), isNull);
    // Selector list beside the editor, separated by the vertical rule.
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.text('MEMBERS'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    _expectLabelRoom(tester, 'View Channel');
    expect(find.text('Save').hitTestable(), findsOneWidget);
    // Desktop buttons keep their compact 30x28 size.
    expect(tester.getSize(_triButton('View Channel', Icons.check)).width, 30);
  });

  testWidgets('phone stacks a chip strip above a full-width editor', (
    tester,
  ) async {
    await _open(tester, _phone);

    expect(tester.takeException(), isNull);
    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.text('MEMBERS'), findsNothing);
    // Every selector entry is still reachable as a chip in the strip.
    for (final label in ['@everyone', 'Moderator', 'alice', '+ Add Member']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Labels get real room now instead of a letter-per-line column.
    _expectLabelRoom(tester, 'View Channel');
    _expectLabelRoom(tester, 'Manage Channels', maxLines: 2);
    // Footer stays on screen.
    expect(find.text('Save').hitTestable(), findsOneWidget);
    expect(find.text('Reset').hitTestable(), findsOneWidget);
    // Finger-sized tri-state controls.
    final allow = tester.getSize(_triButton('View Channel', Icons.check));
    expect(allow.width, greaterThanOrEqualTo(40));
    expect(allow.height, greaterThanOrEqualTo(40));
    // The dialog uses the phone's width (default 40px insets would leave
    // the 390px surface with a 310px dialog).
    expect(tester.getSize(find.byType(Dialog)).width, greaterThan(340));
  });

  testWidgets('phone: selecting a chip and editing a permission works', (
    tester,
  ) async {
    await _open(tester, _phone);

    // Member chip (existing overwrite) and role chip are both selectable. The
    // strip scrolls: the member chip starts off-screen at its end, and once
    // selected it is scrolled into view, which pushes the roles off the left.
    await tester.ensureVisible(find.text('alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('alice').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('Moderator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moderator'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(_triButton('View Channel', Icons.check));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The edit registered as a pending change: closing asks to discard.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved Changes'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('phone at large text scale neither overflows nor hides Save', (
    tester,
  ) async {
    await _open(tester, _phone, textScale: 1.6);

    expect(tester.takeException(), isNull);
    expect(find.text('Save').hitTestable(), findsOneWidget);
    expect(find.text('Reset').hitTestable(), findsOneWidget);
    // The longest label wraps onto extra lines instead of being clipped.
    final long = tester.renderObject<RenderParagraph>(
      find.text('Mention @everyone, @here, and all roles'),
    );
    expect(long.didExceedMaxLines, isFalse);
    expect(
      tester.getSize(_triButton('View Channel', Icons.check)).width,
      greaterThanOrEqualTo(40),
    );
  });
}
