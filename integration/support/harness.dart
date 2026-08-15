/// Test-side glue on top of [AccordTestServer]: creates real accounts, opens
/// real gateway connections, and (optionally) wires a client into a Riverpod
/// [ProviderContainer] so the app's own controllers and gateway event handler
/// can be exercised against live server traffic.
///
/// Typical use — one server per test file, users created once:
///
/// ```dart
/// Future<void> main() async {
///   final harness = await IntegrationHarness.resolve();
///
///   group('messaging', () {
///     late TestAccount alice;
///     setUpAll(() async => alice = await harness.newAccount('alice'));
///     tearDownAll(harness.dispose);
///
///     test('…', () async { … });
///   }, skip: harness.skipReason);
/// }
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/shared/app_info.dart' show kAppVersion;
import 'package:flutter/widgets.dart' show VoidCallback, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'accord_test_server.dart';

/// Default intents for test clients: everything the client app subscribes to
/// that we can assert on without a real SFU.
const List<String> kTestIntents = [
  GatewayIntents.spaces,
  GatewayIntents.members,
  GatewayIntents.messages,
  GatewayIntents.messageContent,
  GatewayIntents.messageReactions,
  GatewayIntents.messageTyping,
  GatewayIntents.directMessages,
  GatewayIntents.presences,
  GatewayIntents.voiceStates,
];

/// A registered user plus its connected [AccordClient].
class TestAccount {
  TestAccount({
    required this.client,
    required this.userId,
    required this.username,
    required this.password,
    required this.token,
    required this.server,
  });

  final AccordClient client;
  final String userId;
  final String username;
  final String password;
  final String token;
  final AccordServer server;

  AccordSession get session => AccordSession(
        server: server,
        token: token,
        tokenType: 'Bearer',
        userId: userId,
        username: username,
      );
}

class IntegrationHarness {
  IntegrationHarness._(this._server, this.skipReason);

  final AccordTestServer? _server;

  /// Non-null when no server could be started — pass it as a group's `skip:`
  /// so the suite explains itself instead of failing opaquely.
  final String? skipReason;

  final List<AccordClient> _clients = [];
  final List<ProviderContainer> _containers = [];
  final List<VoidCallback> _disposers = [];
  int _accountSeq = 0;
  Directory? _hiveDir;

  AccordTestServer get server => _server!;

  String get baseUrl => server.baseUrl;

  AccordServer get accordServer => AccordServer.fromBaseUrl(server.baseUrl);

  /// Starts a server, or captures why one couldn't be started. Never throws —
  /// the caller decides between skipping and failing.
  static Future<IntegrationHarness> resolve() async {
    try {
      return IntegrationHarness._(await AccordTestServer.start(), null);
    } on ServerUnavailable catch (e) {
      return IntegrationHarness._(null, e.message);
    }
  }

  /// Registers a fresh account, optionally connecting its gateway.
  ///
  /// [name] only seeds the username; a per-harness counter keeps it unique, so
  /// calling `newAccount('alice')` twice yields two distinct users.
  ///
  /// Pass `connect: false` when the account still needs to join spaces: the
  /// server snapshots a session's space memberships at IDENTIFY and never
  /// refreshes them (see [connectGateway]), so a gateway opened before the
  /// joins receives nothing for those spaces.
  ///
  /// The server rate-limits registration per IP (see
  /// [AccordTestServer.registrationBudget]), so keep this to a handful per test
  /// file and create accounts in `setUpAll` rather than `setUp`.
  Future<TestAccount> newAccount(
    String name, {
    List<String>? intents,
    bool connect = true,
  }) async {
    final s = server;
    if (s.registrationsUsed >= AccordTestServer.registrationBudget) {
      throw StateError(
        'This server instance has used its ${AccordTestServer.registrationBudget} '
        'registrations (the server allows 5 per IP per 15 minutes and '
        'ACCORD_TEST_MODE does not bypass it). Reuse accounts within the file, '
        'or split these tests across files so each gets its own server.',
      );
    }
    s.registrationsUsed++;

    // The counter alone only guarantees uniqueness within one harness. Test
    // files each get their own process but can share a server — that's exactly
    // what ACCORD_TEST_SERVER_URL does — and two files both asking for
    // "alice0" would collide on the second registration. The pid disambiguates
    // them. Kept to lowercase alphanumerics, which is all `validate_username`
    // accepts, and well inside the server's 32-character limit.
    final username = '$name${_accountSeq++}p$pid';
    const password = 'integration-test-pw';

    final restOnly = _newClient(intents: const []);
    final result = await restOnly.auth.register({
      'username': username,
      'password': password,
      'display_name': username,
    });
    await restOnly.dispose();
    _clients.remove(restOnly);

    if (!result.ok) {
      throw StateError(
        'register($username) failed: ${result.statusCode} ${result.error}',
      );
    }

    final data = result.data as Map<String, dynamic>;
    final user = data['user'] as AccordUser;
    final token = data['token'] as String;

    final client = _newClient(token: token, intents: intents ?? kTestIntents);
    final account = TestAccount(
      client: client,
      userId: user.id,
      username: username,
      password: password,
      token: token,
      server: accordServer,
    );

    if (connect) await connectGateway(account);
    return account;
  }

  /// Opens [account]'s gateway and waits for READY.
  ///
  /// Call this *after* the account's space memberships are in place. The server
  /// loads a session's `space_ids` once, at IDENTIFY, into a non-mutable local
  /// (`src/gateway/mod.rs`), and only reloads it on RESUME — so a space joined
  /// or created after the connection opens fans out nothing to that session.
  Future<void> connectGateway(TestAccount account) async {
    account.client.login();
    await account.client.onReady.first.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw StateError(
        'gateway READY never arrived for ${account.username}',
      ),
    );
  }

  /// Opens the app's Hive boxes against a throwaway directory.
  ///
  /// Required before [containerFor]: several controllers the event handler
  /// writes through (read state, notification settings, space cache) read
  /// Hive synchronously, and an unopened box throws. The app's own
  /// `setupHive()` can't be reused here — it resolves its directory through
  /// `path_provider`, which needs platform channels.
  Future<void> setupHive() async {
    if (_hiveDir != null) return;
    final dir = Directory.systemTemp.createTempSync('accord-integration-hive-');
    _hiveDir = dir;
    Hive.init(dir.path);
    for (final box in const [
      'auth',
      'last-location',
      'added-accounts',
      'space-cache',
      'window-state',
    ]) {
      await Hive.openBox(box);
    }
    await ProfileStore.bootstrap(dir.path);

    // Notifications reach a plugin with no implementation in a headless test
    // VM, and the event handler only touches it when they're enabled. Seed the
    // settings box before any container reads it. Sounds need no equivalent:
    // `SoundManager.silent` defaults to true under `flutter test` (#220).
    final settings = Hive.box('accord-settings');
    final raw = settings.get('settings');
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    map['notificationsEnabled'] = false;
    // The self-updater otherwise reaches the real release endpoint and starts
    // staging a download mid-test, which lands as an unhandled async error
    // after the test body has finished.
    map['autoUpdateCheck'] = false;
    // A fresh Hive dir looks like a first install, so the app would open its
    // onboarding tour, error-reporting consent dialog, and release notes over
    // whatever a UI test is trying to drive. Answer them up front.
    map['errorReportingConsentShown'] = true;
    await settings.put('settings', map);
    await settings.put('onboarding-seen-version', kAppVersion);
    await settings.put('release-notes-seen-version', kAppVersion);
  }

  /// A [ProviderScope] around [child] that reports [account] as the logged-in
  /// session — the widget-tree counterpart of [containerFor], for driving real
  /// screens in `integration_test/`.
  ///
  /// Subclassing [AccordAuth] rather than faking the notifier keeps every
  /// `ref.watchAccordClient()` / `watchUserId()` call site working unchanged,
  /// and its `build()` touches no Hive box.
  ///
  /// (Returns the scope rather than a `List<Override>` because
  /// `flutter_riverpod` doesn't export the `Override` type.)
  Widget scopeFor(TestAccount account, {required Widget child}) => ProviderScope(
        overrides: [
          accordAuthProvider.overrideWith(
            () => _StubAccordAuth(account.client, account.session),
          ),
        ],
        child: child,
      );

  /// Attaches the app's real gateway event handler to [container], so live
  /// server events land in the real caches. Returns a disposer, and also
  /// registers one with the harness so [dispose] cleans up either way.
  VoidCallback wireEvents(ProviderContainer container, TestAccount account) {
    final dispose = handleAccordEvents(
      container.read(_refProvider),
      account.client,
      serverKey: account.session.key,
      currentUserId: account.userId,
      selfDomain: account.server.homeDomain,
      isActive: () => true,
    );
    _disposers.add(dispose);
    return dispose;
  }

  /// A [ProviderContainer] whose `accordAuthProvider` reports [account] as the
  /// logged-in session, with the app's real gateway event handler attached.
  ///
  /// This is what makes controller-level assertions possible: reads go through
  /// the real controllers, and live gateway events land in the real caches —
  /// no widgets. Call [setupHive] first.
  ProviderContainer containerFor(TestAccount account, {bool wireEvents = true}) {
    final container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWith(
          () => _StubAccordAuth(account.client, account.session),
        ),
      ],
    );
    _containers.add(container);

    if (wireEvents) this.wireEvents(container, account);

    return container;
  }

  AccordClient _newClient({String token = '', List<String> intents = const []}) {
    final client = AccordClient(
      token: token,
      tokenType: 'Bearer',
      intents: intents,
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: '${server.baseUrl}/cdn',
    );
    _clients.add(client);
    return client;
  }

  /// Disconnects every client, disposes every container, and stops the server.
  Future<void> dispose() async {
    for (final dispose in _disposers) {
      dispose();
    }
    _disposers.clear();

    for (final container in _containers) {
      container.dispose();
    }
    _containers.clear();

    for (final client in _clients) {
      await client.logout().catchError((_) {});
      await client.dispose();
    }
    _clients.clear();

    if (_hiveDir != null) {
      await Hive.close();
      if (_hiveDir!.existsSync()) _hiveDir!.deleteSync(recursive: true);
      _hiveDir = null;
    }

    await _server?.stop();
  }
}

/// Exposes a container's [Ref] so [handleAccordEvents] can be attached without
/// a widget tree.
final _refProvider = Provider<Ref>((ref) => ref);

/// Reports a fixed logged-in session. Subclassing [AccordAuth] rather than
/// faking the whole notifier keeps every `ref.watchAccordClient()`/`watchUserId()`
/// call site working unchanged, and `build()` touches no Hive box.
class _StubAccordAuth extends AccordAuth {
  _StubAccordAuth(this._client, this._session);

  final AccordClient _client;
  final AccordSession _session;

  @override
  AccordAuthState build() =>
      AccordAuthLoggedIn(client: _client, session: _session);
}

/// Waits for the first event on [stream] satisfying [matches].
///
/// Gateway assertions need this rather than `stream.first`: the server may emit
/// unrelated events first, and a bare `await` with no timeout turns a missing
/// event into a hung suite instead of a failure.
Future<T> waitForEvent<T>(
  Stream<T> stream,
  bool Function(T event) matches, {
  Duration timeout = const Duration(seconds: 10),
  String? description,
}) {
  return stream.firstWhere(matches).timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'No matching ${description ?? '$T'} event within $timeout',
        ),
      );
}

/// Polls [read] until [matches] holds, for assertions on state that a gateway
/// event updates asynchronously (controller caches, in particular).
Future<T> waitForState<T>(
  T Function() read,
  bool Function(T value) matches, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 50),
  String? description,
}) async {
  final deadline = DateTime.now().add(timeout);
  T value = read();
  while (DateTime.now().isBefore(deadline)) {
    value = read();
    if (matches(value)) return value;
    await Future<void>.delayed(interval);
  }
  throw TimeoutException(
    '${description ?? 'State'} never matched within $timeout (last: $value)',
  );
}
