import 'dart:io';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/views/accord_login.dart';
import 'package:bonfire/features/authentication/views/password_reset_form.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _PrimaryResetAuth extends AccordAuth {
  _PrimaryResetAuth(this.pending);

  final AccordSession pending;
  String? submittedOldPassword;
  String? submittedNewPassword;

  @override
  AccordAuthState build() => AccordAuthPasswordResetRequired(pending);

  @override
  Future<List<AccordSession>> listAccounts() async => const [];

  @override
  Future<AccordAuthState> restoreSession() async => state;

  @override
  Future<AccordAuthState> submitPasswordChange({
    required String oldPassword,
    required String newPassword,
  }) async {
    submittedOldPassword = oldPassword;
    submittedNewPassword = newPassword;
    return state;
  }
}

class _AddServerResetAuth extends AccordAuth {
  _AddServerResetAuth(this.initial, this.pending);

  final AccordAuthLoggedIn initial;
  final AccordSession pending;
  String? submittedOldPassword;
  String? submittedNewPassword;

  @override
  AccordAuthState build() => initial;

  @override
  AccordClient? get client => initial.client;

  @override
  String? keyForBaseUrl(String baseUrl) => null;

  @override
  Future<AddServerOutcome> addServerWithCredentials({
    required AccordServer server,
    required String username,
    required String password,
  }) async => AddServerOutcome.passwordReset(pending);

  @override
  Future<AddServerOutcome> addServerSubmitPasswordChange({
    required AccordSession pending,
    required String oldPassword,
    required String newPassword,
  }) async {
    submittedOldPassword = oldPassword;
    submittedNewPassword = newPassword;
    return AddServerOutcome.ok();
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
  description: 'TextField labelled $label',
);

void main() {
  late Directory tempDir;
  late AccordServer server;
  late AccordSession pending;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'password-reset-surfaces-test',
    );
    Hive.init(tempDir.path);
    await Hive.openBox('accord-session');
    await Hive.openBox('accord-settings');
    server = AccordServer.fromBaseUrl('https://reset.example');
    pending = AccordSession(
      server: server,
      token: 'temporary-token',
      userId: 'reset-user',
      username: 'Reset User',
    );
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('accord-session');
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('primary login submits the shared password reset form', (
    tester,
  ) async {
    late _PrimaryResetAuth fake;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accordAuthProvider.overrideWith(() {
            fake = _PrimaryResetAuth(pending);
            return fake;
          }),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: const Scaffold(
            body: AccordLoginScreen(startOnCredentials: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(PasswordResetForm), findsOneWidget);
    await tester.enterText(_field('Current password'), 'temporary-password');
    await tester.enterText(_field('New password'), 'replacement-password');
    await tester.enterText(
      _field('Confirm new password'),
      'replacement-password',
    );
    final changePassword = find.widgetWithText(
      ElevatedButton,
      'Change Password',
    );
    await tester.ensureVisible(changePassword);
    await tester.tap(changePassword);
    await tester.pump();

    expect(fake.submittedOldPassword, 'temporary-password');
    expect(fake.submittedNewPassword, 'replacement-password');
  });

  testWidgets('add-server login completes the same password reset flow', (
    tester,
  ) async {
    final existingServer = AccordServer.fromBaseUrl('https://existing.example');
    final existingSession = AccordSession(
      server: existingServer,
      token: 'existing-token',
      userId: 'existing-user',
      username: 'Existing User',
    );
    final existingClient = AccordClient(
      token: existingSession.token,
      baseUrl: existingServer.baseUrl,
    );
    addTearDown(existingClient.dispose);
    final initial = AccordAuthLoggedIn(
      client: existingClient,
      session: existingSession,
    );
    late _AddServerResetAuth fake;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accordAuthProvider.overrideWith(() {
            fake = _AddServerResetAuth(initial, pending);
            return fake;
          }),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showAddServerDialog(context, initialUrl: server.baseUrl),
                child: const Text('Open add server'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open add server'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();
    await tester.enterText(_field('Username or email'), 'reset-user');
    await tester.enterText(_field('Password'), 'temporary-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.byType(PasswordResetForm), findsOneWidget);
    await tester.enterText(_field('Current password'), 'temporary-password');
    await tester.enterText(_field('New password'), 'replacement-password');
    await tester.enterText(
      _field('Confirm new password'),
      'replacement-password',
    );
    final changePassword = find.widgetWithText(
      ElevatedButton,
      'Change Password',
    );
    await tester.ensureVisible(changePassword);
    await tester.tap(changePassword);
    await tester.pumpAndSettle();

    expect(fake.submittedOldPassword, 'temporary-password');
    expect(fake.submittedNewPassword, 'replacement-password');
    expect(find.text('Add a Server'), findsNothing);
  });
}
