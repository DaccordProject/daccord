import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/controllers/ready.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/events/utils/accord_event_handler.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_auth.g.dart';

/// Authentication + connection lifecycle against an Accord server. The Accord
/// replacement for the Discord-specific `Auth` provider: it owns the live
/// [AccordClient], drives login (credentials → optional MFA → token), persists
/// the session for restore-on-launch, and tears everything down on logout.
@Riverpod(keepAlive: true)
class AccordAuth extends _$AccordAuth {
  static const _sessionBoxName = 'accord-session';
  static const _sessionKey = 'session';
  static const _accountsKey = 'accounts';

  AccordClient? _client;
  VoidCallback? _disposeEvents;

  /// The live client, or null when signed out. Repositories should obtain this
  /// via the logged-in [AccordAuthLoggedIn] state rather than reaching in here.
  AccordClient? get client => _client;

  @override
  AccordAuthState build() {
    ref.onDispose(() {
      _disposeEvents?.call();
      _client?.dispose();
    });
    return const AccordAuthLoggedOut();
  }

  /// Logs in to [server] with [username]/[password]. Returns an
  /// [AccordAuthMfaRequired] state when the server demands a second factor;
  /// follow up with [submitMfa].
  Future<AccordAuthState> loginWithCredentials({
    required AccordServer server,
    required String username,
    required String password,
  }) async {
    state = const AccordAuthInProgress();

    // A throwaway client used only to reach the unauthenticated REST routes.
    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.login({
        'username': username,
        'password': password,
      });

      if (!result.ok) {
        return _fail(result.error?.message ?? 'Login failed');
      }

      final data = result.data;
      if (data is Map && data['mfa_required'] == true) {
        final next = AccordAuthMfaRequired(
          ticket: data['ticket']?.toString() ?? '',
          server: server,
        );
        state = next;
        return next;
      }

      return await _completeLogin(server, data);
    } catch (e) {
      return _fail(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  /// Registers a new account on [server] and logs straight in. [displayName]
  /// defaults to [username] when blank.
  Future<AccordAuthState> registerWithCredentials({
    required AccordServer server,
    required String username,
    required String password,
    String? displayName,
  }) async {
    state = const AccordAuthInProgress();

    final authClient = _restClientFor(server);
    try {
      final dn = displayName?.trim();
      final result = await authClient.auth.register({
        'username': username,
        'password': password,
        'display_name': (dn == null || dn.isEmpty) ? username : dn,
      });

      if (!result.ok) {
        return _fail(result.error?.message ?? 'Registration failed');
      }

      return await _completeLogin(server, result.data);
    } catch (e) {
      return _fail(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  /// Connects to [server] as an anonymous guest (read-only). The guest token is
  /// transient, so the session is **not** persisted or added to the saved
  /// account list. (Guest-token refresh and guest-mode restrictions live in the
  /// connection layer and are not wired yet.)
  Future<AccordAuthState> loginAsGuest(AccordServer server) async {
    state = const AccordAuthInProgress();
    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.guest();
      if (!result.ok) {
        return _fail(result.error?.message ?? 'Guest access not available');
      }
      final data = result.data;
      if (data is! Map) {
        return _fail('Unexpected guest response');
      }
      final token = data['token']?.toString();
      if (token == null || token.isEmpty) {
        return _fail('No guest token received');
      }

      final probe = _restClientFor(server, token: token);
      try {
        final me = await probe.users.getMe();
        if (!me.ok || me.data is! AccordUser) {
          return _fail(me.error?.message ?? 'Guest connection failed');
        }
        final user = me.data as AccordUser;
        final session = AccordSession(
          server: server,
          token: token,
          tokenType: 'Bearer',
          userId: user.id,
          username: user.displayName ?? user.username,
          avatar: user.avatar,
          isAdmin: user.isAdmin,
        );
        // Intentionally not persisted: guest sessions are transient.
        return await _connect(session);
      } finally {
        await probe.dispose();
      }
    } catch (e) {
      return _fail(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  /// Fetches a server's public settings (e.g. Terms-of-Service config) before
  /// login. Returns the settings map, unwrapping a `{ data: {...} }` envelope,
  /// or null on failure.
  Future<Map<String, dynamic>?> fetchServerSettings(AccordServer server) async {
    final client = _restClientFor(server);
    try {
      final result = await client.rest.makeRequest('GET', '/settings');
      if (!result.ok || result.data is! Map) return null;
      final map = Map<String, dynamic>.from(result.data as Map);
      final inner = map['data'];
      return inner is Map ? Map<String, dynamic>.from(inner) : map;
    } catch (_) {
      return null;
    } finally {
      await client.dispose();
    }
  }

  /// Completes an MFA challenge from [loginWithCredentials] with a TOTP or
  /// backup [code].
  Future<AccordAuthState> submitMfa(String code) async {
    final current = state;
    if (current is! AccordAuthMfaRequired) {
      return _fail('No MFA challenge in progress');
    }
    final server = current.server;
    state = const AccordAuthInProgress();

    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.loginMfa({
        'ticket': current.ticket,
        'code': code,
      });
      if (!result.ok) {
        return _fail(result.error?.message ?? 'Invalid two-factor code');
      }
      return await _completeLogin(server, result.data);
    } catch (e) {
      return _fail(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  /// Resolves an [AccordAuthPasswordResetRequired] challenge: changes the
  /// password using the temporary token, then connects the now-usable session.
  Future<AccordAuthState> submitPasswordChange({
    required String oldPassword,
    required String newPassword,
  }) async {
    final current = state;
    if (current is! AccordAuthPasswordResetRequired) {
      return _fail('No password change in progress');
    }
    final pending = current.pending;
    state = const AccordAuthInProgress();

    final authed = _restClientFor(
      pending.server,
      token: pending.token,
      tokenType: pending.tokenType,
    );
    try {
      final result = await authed.auth.changePassword({
        'old_password': oldPassword,
        'new_password': newPassword,
      });
      if (!result.ok) {
        return _resetRequired(
          pending,
          error: result.error?.message ?? 'Password change failed',
        );
      }
      await _persist(pending);
      return await _connect(pending);
    } catch (e) {
      return _resetRequired(pending, error: e.toString());
    } finally {
      await authed.dispose();
    }
  }

  /// Logs in directly with an existing [token] (e.g. a bot token or one pasted
  /// by the user). Fetches the account, persists the session, and connects.
  Future<AccordAuthState> loginWithToken({
    required AccordServer server,
    required String token,
    String tokenType = 'Bearer',
  }) async {
    state = const AccordAuthInProgress();
    final probe = _restClientFor(server, token: token, tokenType: tokenType);
    try {
      final me = await probe.users.getMe();
      if (!me.ok || me.data is! AccordUser) {
        return _fail(me.error?.message ?? 'Token rejected');
      }
      final user = me.data as AccordUser;
      final session = AccordSession(
        server: server,
        token: token,
        tokenType: tokenType,
        userId: user.id,
        username: user.displayName ?? user.username,
        avatar: user.avatar,
        isAdmin: user.isAdmin,
      );
      await _persist(session);
      return await _connect(session);
    } catch (e) {
      return _fail(e.toString());
    } finally {
      await probe.dispose();
    }
  }

  /// Restores a persisted session and reconnects the gateway. Returns
  /// [AccordAuthLoggedOut] when nothing is stored.
  Future<AccordAuthState> restoreSession() async {
    final box = await Hive.openBox(_sessionBoxName);
    final raw = box.get(_sessionKey);
    if (raw == null) {
      return const AccordAuthLoggedOut();
    }
    try {
      final session =
          AccordSession.fromJson(Map<String, dynamic>.from(raw as Map));
      return await _connect(session);
    } catch (e) {
      debugPrint('Failed to restore Accord session: $e');
      await box.delete(_sessionKey);
      return _fail(e.toString());
    }
  }

  /// Tears down the live client and clears the stored session.
  Future<void> logout() async {
    _disposeEvents?.call();
    _disposeEvents = null;
    await _client?.dispose();
    _client = null;

    final box = await Hive.openBox(_sessionBoxName);
    await box.delete(_sessionKey);

    ref
        .read(connectionControllerProvider.notifier)
        .set(ConnectionStatus.disconnected);
    ref.read(readyControllerProvider.notifier).setReady(false);
    state = const AccordAuthLoggedOut();
  }

  // ── internals ─────────────────────────────────────────────────────────────

  AccordClient _restClientFor(
    AccordServer server, {
    String token = '',
    String tokenType = 'Bearer',
  }) =>
      AccordClient(
        token: token,
        tokenType: tokenType,
        baseUrl: server.baseUrl,
        gatewayUrl: server.gatewayUrl,
        cdnUrl: server.cdnUrl,
      );

  /// Parses an `{ user, token }` auth response and connects.
  Future<AccordAuthState> _completeLogin(
      AccordServer server, Object? data) async {
    if (data is! Map) {
      return _fail('Malformed auth response');
    }
    final token = data['token']?.toString();
    final user = data['user'];
    if (token == null || user is! AccordUser) {
      return _fail('Auth response missing token or user');
    }
    final session = AccordSession(
      server: server,
      token: token,
      tokenType: 'Bearer',
      userId: user.id,
      username: user.displayName ?? user.username,
      avatar: user.avatar,
      isAdmin: user.isAdmin,
    );
    if (data['force_password_reset'] == true) {
      return _resetRequired(session);
    }
    await _persist(session);
    return await _connect(session);
  }

  AccordAuthState _resetRequired(AccordSession pending, {String? error}) {
    final next = AccordAuthPasswordResetRequired(pending, error: error);
    state = next;
    return next;
  }

  /// Persists [session] as the active session and upserts it into the saved
  /// account list (keyed by user + server) for the account switcher.
  Future<void> _persist(AccordSession session) async {
    final box = await Hive.openBox(_sessionBoxName);
    await box.put(_sessionKey, session.toJson());
    final accounts = _readAccounts(box);
    accounts[_accountKey(session)] = session.toJson();
    await box.put(_accountsKey, accounts);
  }

  String _accountKey(AccordSession session) =>
      '${session.userId}@${session.server.baseUrl}';

  Map<String, dynamic> _readAccounts(Box box) {
    final raw = box.get(_accountsKey);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  /// All saved accounts, for the switcher UI.
  Future<List<AccordSession>> listAccounts() async {
    final box = await Hive.openBox(_sessionBoxName);
    final accounts = _readAccounts(box);
    final result = <AccordSession>[];
    for (final raw in accounts.values) {
      if (raw is! Map) continue;
      try {
        result.add(AccordSession.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {
        // Skip malformed saved accounts.
      }
    }
    return result;
  }

  /// Switches the active session to a previously saved [session] and connects.
  Future<AccordAuthState> switchTo(AccordSession session) async {
    state = const AccordAuthInProgress();
    try {
      await _persist(session);
      return await _connect(session);
    } catch (e) {
      return _fail(e.toString());
    }
  }

  /// Removes [session] from the saved account list. If it is the active
  /// session, also signs out.
  Future<void> removeAccount(AccordSession session) async {
    final box = await Hive.openBox(_sessionBoxName);
    final accounts = _readAccounts(box);
    accounts.remove(_accountKey(session));
    await box.put(_accountsKey, accounts);

    final active = state;
    if (active is AccordAuthLoggedIn &&
        _accountKey(active.session) == _accountKey(session)) {
      await logout();
      return;
    }
    // Clear a stale active pointer left behind by a logged-out removal.
    final rawActive = box.get(_sessionKey);
    if (rawActive is Map) {
      try {
        final stored =
            AccordSession.fromJson(Map<String, dynamic>.from(rawActive));
        if (_accountKey(stored) == _accountKey(session)) {
          await box.delete(_sessionKey);
        }
      } catch (_) {
        // Ignore an unreadable active pointer.
      }
    }
  }

  /// Builds the live [AccordClient], wires gateway events, and connects.
  Future<AccordAuthState> _connect(AccordSession session) async {
    _disposeEvents?.call();
    await _client?.dispose();

    ref
        .read(connectionControllerProvider.notifier)
        .set(ConnectionStatus.connecting);

    final client = AccordClient(
      token: session.token,
      tokenType: session.tokenType,
      baseUrl: session.server.baseUrl,
      gatewayUrl: session.server.gatewayUrl,
      cdnUrl: session.server.cdnUrl,
      intents: [
        GatewayIntents.spaces,
        GatewayIntents.messages,
        GatewayIntents.messageContent,
        GatewayIntents.messageReactions,
        GatewayIntents.messageTyping,
        GatewayIntents.members,
        GatewayIntents.presences,
        GatewayIntents.voiceStates,
      ],
    );
    _client = client;
    _disposeEvents = handleAccordEvents(ref, client);
    client.login();

    ref.read(readyControllerProvider.notifier).setReady(true);

    final next = AccordAuthLoggedIn(client: client, session: session);
    state = next;
    return next;
  }

  AccordAuthState _fail(String message) {
    final next = AccordAuthFailed(message);
    state = next;
    return next;
  }
}
