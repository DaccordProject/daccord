import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/credential_validation.dart';
import 'package:bonfire/features/authentication/utils/tos_gate.dart';
import 'package:bonfire/features/authentication/views/auth_form.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The *server's* Terms of Service, the supplementary gate that sits on top of
/// the app's own bundled terms (#289).
///
/// `GET /settings` is authenticated-only, so a signed-out read fails and used
/// to be indistinguishable from a server that advertises no terms — the gate
/// then silently vanished. These tests pin the four-way distinction, and in
/// particular that the expected `401` stays invisible to the user (a standing
/// warning on the register screen would read as a half-configured feature to
/// App Review) while a genuinely unexpected failure does not.

typedef _SettingsResult = ({
  Map<String, dynamic>? settings,
  String? error,
  int statusCode,
});

class _SettingsAuth extends AccordAuth {
  _SettingsAuth(this.result);

  final _SettingsResult result;

  @override
  Future<_SettingsResult> fetchServerSettings(AccordServer server) async =>
      result;
}

final _server = AccordServer.fromBaseUrl('https://example.test');

Future<TosConfig> _config(_SettingsResult result) =>
    fetchTosConfig(_SettingsAuth(result), _server);

Widget _form(TosAvailability availability, {AuthMode mode = AuthMode.register}) =>
    MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AuthCredentialsFields(
            mode: mode,
            onModeChanged: (_) {},
            usernameController: TextEditingController(),
            passwordController: TextEditingController(),
            displayNameController: TextEditingController(),
            tosAvailability: availability,
            tosAccepted: false,
            onTosChanged: (_) {},
            onTosLinkTap: () {},
            onGeneratePassword: () {},
            onSubmit: () {},
          ),
        ),
      ),
    );

/// Whether registration would go through with nothing ticked, which every
/// non-[TosAvailability.advertised] state must allow.
bool _canRegisterWithoutTicking(TosAvailability availability) =>
    validateRegistrationCredentials(
      username: 'someone',
      password: 'hunter2hunter2',
      tosRequired: availability == TosAvailability.advertised,
      tosAccepted: false,
    ) ==
    null;

void main() {
  group('fetchTosConfig', () {
    test('a server that advertises terms reports them', () async {
      final config = await _config((
        settings: {
          'tos_enabled': true,
          'tos_url': 'https://example.test/tos',
          'tos_text': 'Be nice.',
        },
        error: null,
        statusCode: 200,
      ));

      expect(config.availability, TosAvailability.advertised);
      expect(config.url, 'https://example.test/tos');
      expect(config.text, 'Be nice.');
    });

    test('a server that answers without terms is genuinely absent', () async {
      final config = await _config((
        settings: {'tos_enabled': false},
        error: null,
        statusCode: 200,
      ));

      expect(config.availability, TosAvailability.absent);
    });

    test('a refused read is refused, not absent and not unknown', () async {
      // What a signed-out `GET /settings` really does on every instance today.
      for (final status in [401, 403]) {
        final config = await _config((
          settings: null,
          error: 'HTTP $status',
          statusCode: status,
        ));

        expect(config.availability, TosAvailability.refused, reason: '$status');
        expect(config.url, isNull);
        expect(config.text, isNull);
      }
    });

    test('any other failure is unknown', () async {
      for (final status in [0, 404, 500, 502]) {
        final config = await _config((
          settings: null,
          error: 'boom',
          statusCode: status,
        ));

        expect(config.availability, TosAvailability.unknown, reason: '$status');
      }
    });
  });

  group('the register form', () {
    testWidgets('shows the checkbox when the server advertises terms', (
      tester,
    ) async {
      await tester.pumpWidget(_form(TosAvailability.advertised));

      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text(tosUnavailableNotice), findsNothing);

      // And the box still has to be ticked.
      expect(
        validateRegistrationCredentials(
          username: 'someone',
          password: 'hunter2hunter2',
          tosRequired: true,
          tosAccepted: false,
        ),
        'You must accept the Terms of Service.',
      );
    });

    testWidgets('stays quiet when the server advertises none', (tester) async {
      await tester.pumpWidget(_form(TosAvailability.absent));

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text(tosUnavailableNotice), findsNothing);
      expect(_canRegisterWithoutTicking(TosAvailability.absent), isTrue);
    });

    testWidgets('stays quiet when the settings read was refused', (
      tester,
    ) async {
      // The signed-out 401 is expected and structural: logged, never shown.
      // A permanent notice here would read as a half-configured feature to
      // App Review (#292) and appear in the #293 screen recording.
      await tester.pumpWidget(_form(TosAvailability.refused));

      expect(find.text(tosUnavailableNotice), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(_canRegisterWithoutTicking(TosAvailability.refused), isTrue);
    });

    testWidgets('says so when the read failed unexpectedly', (tester) async {
      await tester.pumpWidget(_form(TosAvailability.unknown));

      expect(find.text(tosUnavailableNotice), findsOneWidget);
      // A notice, not a gate: nothing to tick, and registration goes through.
      expect(find.byType(Checkbox), findsNothing);
      expect(_canRegisterWithoutTicking(TosAvailability.unknown), isTrue);
    });

    testWidgets('never shows either in sign-in mode', (tester) async {
      await tester.pumpWidget(
        _form(TosAvailability.unknown, mode: AuthMode.signIn),
      );

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text(tosUnavailableNotice), findsNothing);
    });
  });

  group('end to end, fetch through to what the register form renders', () {
    /// The two failure paths that matter, driven from a settings result rather
    /// than a hand-picked enum value, so a regression in either the mapping or
    /// the rendering is caught.
    Future<void> pumpFor(WidgetTester tester, _SettingsResult result) async {
      late TosConfig config;
      await tester.runAsync(() async => config = await _config(result));
      await tester.pumpWidget(_form(config.availability));
    }

    testWidgets('a signed-out 401 registers with no notice at all', (
      tester,
    ) async {
      await pumpFor(tester, (
        settings: null,
        error: 'invalid or missing authentication',
        statusCode: 401,
      ));

      expect(find.text(tosUnavailableNotice), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('a 500 registers, but says the terms are missing', (
      tester,
    ) async {
      await pumpFor(tester, (
        settings: null,
        error: 'internal server error',
        statusCode: 500,
      ));

      expect(find.text(tosUnavailableNotice), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });
  });
}
