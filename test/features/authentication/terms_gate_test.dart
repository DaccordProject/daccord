import 'dart:io';

import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/models/app_terms.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/terms_acceptance.dart';
import 'package:bonfire/features/authentication/views/accord_login.dart';
import 'package:bonfire/features/authentication/views/terms_gate.dart';
import 'package:bonfire/features/authentication/views/welcome_view.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// The app's own terms gate (#289).
///
/// A server's Terms of Service can't satisfy App Review 1.2: it is optional per
/// instance and `GET /settings` is authenticated-only, so a signed-out user
/// never sees one. These tests pin the replacement — terms shown before *any*
/// signed-out surface, acceptance remembered, and a version bump re-prompting.

class _LoggedOutAuth extends AccordAuth {
  @override
  AccordAuthState build() => AccordAuthLoggedOut();

  @override
  Future<List<AccordSession>> listAccounts() async => const [];

  @override
  Future<AccordAuthState> restoreSession() async => state;
}

Widget _loginApp() => ProviderScope(
  overrides: [accordAuthProvider.overrideWith(_LoggedOutAuth.new)],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: const Scaffold(body: AccordLoginScreen()),
  ),
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('terms-gate-test');
    Hive.init(tempDir.path);
    await Hive.openBox('auth');
    await Hive.openBox('accord-session');
    await Hive.openBox('accord-settings');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('auth');
    await Hive.deleteBoxFromDisk('accord-session');
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('acceptance is remembered, and a new version asks again', () async {
    expect(hasAcceptedAppTerms(), isFalse);

    await recordAppTermsAcceptance();
    expect(hasAcceptedAppTerms(), isTrue);

    // A terms revision bumps the version; the stored older acceptance no
    // longer covers it.
    await Hive.box(
      'auth',
    ).put('accepted-app-terms-version', appTermsVersion - 1);
    expect(hasAcceptedAppTerms(), isFalse);

    await clearAppTermsAcceptance();
    expect(hasAcceptedAppTerms(), isFalse);
  });

  testWidgets('the gate replaces every signed-out surface until accepted', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_loginApp());
    await tester.pump();
    await tester.pump();

    expect(find.byType(TermsGateView), findsOneWidget);
    expect(find.text(appTermsTitle), findsOneWidget);
    expect(find.textContaining('Zero tolerance'), findsOneWidget);
    // The welcome screen — and with it the server browser and the credentials
    // form behind it — stays out of reach.
    expect(find.byType(WelcomeView), findsNothing);
  });

  testWidgets('agreeing is what lifts the gate', (tester) async {
    // The gate on its own: the login screen's handler records acceptance
    // through Hive, whose real IO never lands on a widget test's fake clock.
    var accepted = false;
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TermsGateView(onAccept: () => accepted = true),
          ),
        ),
      ),
    );

    final agree = find.widgetWithText(ElevatedButton, 'Agree and continue');
    await tester.ensureVisible(agree);
    await tester.tap(agree);
    await tester.pump();

    expect(accepted, isTrue);
  });

  testWidgets('an accepted device goes straight to the signed-out flow', (
    tester,
  ) async {
    // Hive writes are real IO: inside a widget test they only run under
    // runAsync, not on the fake clock pumps drive.
    await tester.runAsync(recordAppTermsAcceptance);
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_loginApp());
    await tester.pump();
    await tester.pump();

    expect(find.byType(TermsGateView), findsNothing);
    expect(find.byType(WelcomeView), findsOneWidget);
  });

  testWidgets('the terms stay reachable from the credentials form', (
    tester,
  ) async {
    await tester.runAsync(recordAppTermsAcceptance);
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [accordAuthProvider.overrideWith(_LoggedOutAuth.new)],
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

    final link = find.widgetWithText(TextButton, appTermsTitle);
    expect(link, findsOneWidget);
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.byType(AppTermsBody), findsOneWidget);
  });
}
