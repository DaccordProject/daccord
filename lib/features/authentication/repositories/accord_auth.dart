import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/controllers/ready.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_session_store.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/voice/controllers/missed_calls.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/utils/space_cache.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_auth.g.dart';

/// One live server connection: its [AccordClient], the gateway-event disposer,
/// and the [AccordSession] that opened it.
class _Conn {
  final AccordClient client;
  final VoidCallback disposeEvents;
  final AccordSession session;

  _Conn({
    required this.client,
    required this.disposeEvents,
    required this.session,
  });
}

/// Neutral result of an auth REST call, before any state publication: exactly
/// one of [data] (success payload), [mfaTicket], or [error] is meaningful.
class _AuthAttempt {
  final Object? data;
  final String? mfaTicket;
  final String? error;

  const _AuthAttempt._({this.data, this.mfaTicket, this.error});

  factory _AuthAttempt.success(Object? data) => _AuthAttempt._(data: data);
  factory _AuthAttempt.mfa(String ticket) => _AuthAttempt._(mfaTicket: ticket);
  factory _AuthAttempt.error(String message) => _AuthAttempt._(error: message);
}

/// Authentication + connection lifecycle against Accord servers. The Accord
/// replacement for the Discord-specific `Auth` provider.
///
/// In the multi-server model this holds N live [AccordClient]s at once (one per
/// connected server, keyed by `userId@baseUrl`) and tracks which one is
/// *active*. `state` (an [AccordAuthLoggedIn]) and [client] always refer to the
/// active connection, so every existing pane/controller keeps reading the active
/// server unchanged. Background connections stay logged in (gateways open,
/// spaces cached in `ConnectionsController`) so the rail can show every server's
/// spaces at once; selecting a space on another server flips the active
/// connection without re-authenticating.
@Riverpod(keepAlive: true)
class AccordAuth extends _$AccordAuth {
  final _store = AccordSessionStore();
  final Map<String, _Conn> _connections = {};
  String? _activeKey;

  /// Connection keys currently being torn down after a 401, so the burst of
  /// simultaneous unauthorized responses (spaces, members, emojis, …) triggers
  /// exactly one sign-out per connection.
  final Set<String> _signingOut = {};

  /// The active connection's client, or null when signed out. Repositories
  /// should obtain this via the logged-in [AccordAuthLoggedIn] state rather than
  /// reaching in here.
  AccordClient? get client =>
      _activeKey == null ? null : _connections[_activeKey]?.client;

  /// The active connection's client for [key], if connected.
  AccordClient? clientForKey(String key) => _connections[key]?.client;

  /// The connection key (`userId@baseUrl`) currently connected to [baseUrl], if
  /// any — used by the deep-link/add-server flow to detect "already connected".
  String? keyForBaseUrl(String baseUrl) {
    for (final conn in _connections.values) {
      if (conn.session.server.baseUrl == baseUrl) return conn.session.key;
    }
    return null;
  }

  @override
  AccordAuthState build() {
    ref.onDispose(() {
      for (final conn in _connections.values) {
        conn.disposeEvents();
        conn.client.dispose();
      }
      _connections.clear();
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
    final attempt = await _attemptLogin(
      server,
      username: username,
      password: password,
    );
    if (attempt.error != null) return _fail(attempt.error!);
    if (attempt.mfaTicket != null) {
      final next = AccordAuthMfaRequired(
        ticket: attempt.mfaTicket!,
        server: server,
      );
      state = next;
      return next;
    }
    return await _completeLogin(server, attempt.data);
  }

  /// Registers a new account on [server] and logs straight in. [displayName]
  /// defaults to [username] when blank.
  Future<AccordAuthState> registerWithCredentials({
    required AccordServer server,
    required String username,
    required String password,
    String? displayName,
  }) async {
    // Usernames are the public login identifier (login is by username, not
    // email); reject email-like values before hitting the server. The server
    // enforces this authoritatively as well.
    if (username.contains('@')) {
      return _fail("Username can't be an email address.");
    }
    state = const AccordAuthInProgress();
    final attempt = await _attemptRegister(
      server,
      username: username,
      password: password,
      displayName: displayName,
    );
    if (attempt.error != null) return _fail(attempt.error!);
    return await _completeLogin(server, attempt.data);
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
        final session = _sessionFrom(server, token, me.data as AccordUser);
        // Intentionally not persisted: guest sessions are transient.
        return await _addConnection(session, makeActive: true);
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
    final attempt = await _attemptMfa(server, ticket: current.ticket, code: code);
    if (attempt.error != null) return _fail(attempt.error!);
    return await _completeLogin(server, attempt.data);
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
      await _store.persist(pending);
      return await _addConnection(pending, makeActive: true);
    } catch (e) {
      return _resetRequired(pending, error: e.toString());
    } finally {
      await authed.dispose();
    }
  }

  /// Restores the persisted active session (and any other saved accounts) and
  /// reconnects their gateways. The active account is connected first and its
  /// logged-in state returned for navigation; the rest connect in the
  /// background so the rail can show every server's spaces. Returns
  /// [AccordAuthLoggedOut] when nothing is stored.
  Future<AccordAuthState> restoreSession() async {
    final raw = await _store.readActiveRaw();
    if (raw == null) {
      return const AccordAuthLoggedOut();
    }

    AccordSession? active;
    try {
      active = AccordSession.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      debugPrint('Failed to restore Accord session: $e');
      await _store.deleteActive();
      return _fail(e.toString());
    }

    final result = await _addConnection(active, makeActive: true);

    // Reconnect every other saved account in the background.
    final activeKey = active.key;
    final accounts = await listAccounts();
    for (final session in accounts) {
      if (session.key == activeKey) continue;
      unawaited(_addConnection(session, makeActive: false));
    }

    // Prune tabs owned by accounts that no longer exist (e.g. logged out before
    // this restore), so the strip doesn't show stale/duplicate tabs.
    final knownServers = {activeKey, for (final s in accounts) s.key};
    ref.read(openTabsControllerProvider.notifier).retainServers(knownServers);
    return result;
  }

  /// Tears down every live connection and clears the active session pointer.
  Future<void> logout() async {
    for (final conn in _connections.values) {
      conn.disposeEvents();
      await conn.client.dispose();
    }
    _connections.clear();
    _activeKey = null;

    await _store.deleteActive();

    ref.read(connectionsControllerProvider.notifier).clear();
    ref.invalidate(readStateControllerProvider);
    ref.invalidate(presenceControllerProvider);
    // Missed calls are session-only and in-memory, so without this they would
    // survive a sign-out that doesn't restart the app.
    ref.read(missedCallsControllerProvider.notifier).clearAll();
    ref.read(openTabsControllerProvider.notifier).clear();
    unawaited(SpaceCache.clear());
    ref.read(spacesControllerProvider.notifier).setSpaces(const []);
    ref
        .read(connectionControllerProvider.notifier)
        .set(ConnectionStatus.disconnected);
    ref.read(readyControllerProvider.notifier).setReady(false);
    state = const AccordAuthLoggedOut();
  }

  /// Reacts to a `401 Unauthorized` from connection [key]: its token is invalid
  /// or expired and accordkit exposes no refresh path, so the session can't be
  /// recovered silently. Sign the affected account out via [removeAccount],
  /// which switches to another live server if one exists or otherwise
  /// [logout]s to the login screen — matching "log me back in" rather than
  /// leaving cached spaces/channels rendered behind a dead token.
  ///
  /// Guarded by [_signingOut] so the burst of simultaneous 401s (spaces,
  /// members, emojis, …) tears the connection down exactly once; a no-op once
  /// the connection is already gone.
  Future<void> _handleUnauthorized(String key) async {
    if (_signingOut.contains(key)) return;
    final conn = _connections[key];
    if (conn == null) return;
    _signingOut.add(key);
    debugPrint('Session $key is unauthorized (token invalid/expired); '
        'signing it out.');
    try {
      await removeAccount(conn.session);
    } finally {
      _signingOut.remove(key);
    }
  }

  // ── Add-a-server (multi-connection) ────────────────────────────────────────
  // These connect an *additional* server while staying logged in. Unlike the
  // primary login flow they must NOT publish a global [AccordAuthInProgress]
  // state (that would bounce the home screen to /login); they keep the current
  // active connection until the new one succeeds.

  /// Connects an additional [server] with an existing [token], persists it, and
  /// makes it active. Returns null on success or an error message on failure.
  Future<String?> addServerWithToken({
    required AccordServer server,
    required String token,
    String tokenType = 'Bearer',
  }) async {
    try {
      final session = await _sessionFromToken(server, token, tokenType);
      if (session == null) return 'Token rejected';
      await _store.persist(session);
      await _addConnection(session, makeActive: true);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Connects an additional [server] with [username]/[password], persists it,
  /// and makes it active. Reports MFA challenges via [AddServerOutcome.mfa].
  Future<AddServerOutcome> addServerWithCredentials({
    required AccordServer server,
    required String username,
    required String password,
  }) async {
    final attempt = await _attemptLogin(
      server,
      username: username,
      password: password,
    );
    if (attempt.error != null) return AddServerOutcome.error(attempt.error!);
    if (attempt.mfaTicket != null) {
      return AddServerOutcome.mfa(attempt.mfaTicket!);
    }
    return await _completeAddServer(server, attempt.data);
  }

  /// Registers a new account on [server] and connects it as an additional
  /// server, persisting it and making it active. The add-a-server counterpart
  /// to [registerWithCredentials] (which is for the primary login flow): it
  /// returns an [AddServerOutcome] instead of publishing a global
  /// [AccordAuthInProgress] state, so the home screen isn't bounced to login.
  Future<AddServerOutcome> addServerWithRegister({
    required AccordServer server,
    required String username,
    required String password,
    String? displayName,
  }) async {
    if (username.contains('@')) {
      return AddServerOutcome.error("Username can't be an email address.");
    }
    final attempt = await _attemptRegister(
      server,
      username: username,
      password: password,
      displayName: displayName,
    );
    if (attempt.error != null) return AddServerOutcome.error(attempt.error!);
    return await _completeAddServer(server, attempt.data);
  }

  /// Completes an MFA challenge raised by [addServerWithCredentials].
  Future<AddServerOutcome> addServerSubmitMfa(
    AccordServer server,
    String ticket,
    String code,
  ) async {
    final attempt = await _attemptMfa(server, ticket: ticket, code: code);
    if (attempt.error != null) return AddServerOutcome.error(attempt.error!);
    return await _completeAddServer(server, attempt.data);
  }

  /// The add-a-server counterpart to [_completeLogin]: same `{ user, token }`
  /// parsing and connect, but reports through [AddServerOutcome] and (by
  /// design) ignores `force_password_reset` — the add-server dialog has no
  /// reset flow.
  Future<AddServerOutcome> _completeAddServer(
    AccordServer server,
    Object? data,
  ) async {
    final parsed = _sessionFromAuthData(server, data);
    if (parsed.error != null) return AddServerOutcome.error(parsed.error!);
    await _store.persist(parsed.session!);
    await _addConnection(parsed.session!, makeActive: true);
    return AddServerOutcome.ok();
  }

  /// Pokes every live connection's gateway to verify it's still alive,
  /// reconnecting any that died (see [AccordClient.ensureConnected]). Called
  /// when the app returns to the foreground: mobile OSes freeze the process
  /// while backgrounded, which stops heartbeats, silently kills sockets, and
  /// can exhaust the automatic reconnect budget before the user comes back.
  void ensureConnectedAll() {
    for (final conn in _connections.values) {
      conn.client.ensureConnected();
    }
  }

  /// Flips the active connection to [key] (a server already connected). No-op if
  /// [key] is not connected.
  void setActiveServer(String key) {
    if (!_connections.containsKey(key)) return;
    _makeActive(key);
  }

  // ── internals ─────────────────────────────────────────────────────────────

  AccordClient _restClientFor(
    AccordServer server, {
    String token = '',
    String tokenType = 'Bearer',
  }) => AccordClient(
    token: token,
    tokenType: tokenType,
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
  );

  // The shared REST cores behind both the primary-login and add-a-server
  // flows, which were previously near-verbatim clones of each other. Each
  // opens a throwaway unauthenticated client, maps failures/exceptions to an
  // [_AuthAttempt], and leaves state publication to the caller (primary login
  // publishes global [AccordAuthState]s; add-a-server returns
  // [AddServerOutcome]s so the home screen isn't bounced to login).

  Future<_AuthAttempt> _attemptLogin(
    AccordServer server, {
    required String username,
    required String password,
  }) async {
    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.login({
        'username': username,
        'password': password,
      });
      if (!result.ok) {
        return _AuthAttempt.error(result.error?.message ?? 'Login failed');
      }
      final data = result.data;
      if (data is Map && data['mfa_required'] == true) {
        return _AuthAttempt.mfa(data['ticket']?.toString() ?? '');
      }
      return _AuthAttempt.success(data);
    } catch (e) {
      return _AuthAttempt.error(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  Future<_AuthAttempt> _attemptRegister(
    AccordServer server, {
    required String username,
    required String password,
    String? displayName,
  }) async {
    final authClient = _restClientFor(server);
    try {
      final dn = displayName?.trim();
      final result = await authClient.auth.register({
        'username': username,
        'password': password,
        'display_name': (dn == null || dn.isEmpty) ? username : dn,
      });
      if (!result.ok) {
        return _AuthAttempt.error(
          result.error?.message ?? 'Registration failed',
        );
      }
      return _AuthAttempt.success(result.data);
    } catch (e) {
      return _AuthAttempt.error(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  Future<_AuthAttempt> _attemptMfa(
    AccordServer server, {
    required String ticket,
    required String code,
  }) async {
    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.loginMfa({
        'ticket': ticket,
        'code': code,
      });
      if (!result.ok) {
        return _AuthAttempt.error(
          result.error?.message ?? 'Invalid two-factor code',
        );
      }
      return _AuthAttempt.success(result.data);
    } catch (e) {
      return _AuthAttempt.error(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  /// Builds the client-local session record for [user] authenticated against
  /// [server] with [token] — the one place the user→session field mapping
  /// lives.
  AccordSession _sessionFrom(
    AccordServer server,
    String token,
    AccordUser user, {
    String tokenType = 'Bearer',
  }) => AccordSession(
    server: server,
    token: token,
    tokenType: tokenType,
    userId: user.id,
    username: user.displayName ?? user.username,
    avatar: user.avatar,
    isAdmin: user.isAdmin,
  );

  /// Parses an `{ user, token }` auth payload into a session, or an error
  /// message when malformed. Shared by the login and add-a-server completions.
  ({AccordSession? session, String? error}) _sessionFromAuthData(
    AccordServer server,
    Object? data,
  ) {
    if (data is! Map) return (session: null, error: 'Malformed auth response');
    final token = data['token']?.toString();
    final user = data['user'];
    if (token == null || user is! AccordUser) {
      return (session: null, error: 'Auth response missing token or user');
    }
    return (session: _sessionFrom(server, token, user), error: null);
  }

  /// Verifies [token] against [server] and mints a session, or null if the
  /// token is rejected.
  Future<AccordSession?> _sessionFromToken(
    AccordServer server,
    String token,
    String tokenType,
  ) async {
    final probe = _restClientFor(server, token: token, tokenType: tokenType);
    try {
      final me = await probe.users.getMe();
      if (!me.ok || me.data is! AccordUser) return null;
      return _sessionFrom(
        server,
        token,
        me.data as AccordUser,
        tokenType: tokenType,
      );
    } finally {
      await probe.dispose();
    }
  }

  /// Parses an `{ user, token }` auth response and connects.
  Future<AccordAuthState> _completeLogin(
    AccordServer server,
    Object? data,
  ) async {
    final parsed = _sessionFromAuthData(server, data);
    if (parsed.error != null) return _fail(parsed.error!);
    final session = parsed.session!;
    if (data is Map && data['force_password_reset'] == true) {
      return _resetRequired(session);
    }
    await _store.persist(session);
    return await _addConnection(session, makeActive: true);
  }

  AccordAuthState _resetRequired(AccordSession pending, {String? error}) {
    final next = AccordAuthPasswordResetRequired(pending, error: error);
    state = next;
    return next;
  }

  String _accountKey(AccordSession session) => session.key;

  /// All saved accounts, for the switcher UI.
  Future<List<AccordSession>> listAccounts() => _store.listAccounts();

  /// Switches the active session to a previously saved [session]. If it is
  /// already connected this just flips active; otherwise it connects it.
  Future<AccordAuthState> switchTo(AccordSession session) async {
    final key = _accountKey(session);
    if (_connections.containsKey(key)) {
      await _store.persistActive(session);
      return _makeActive(key);
    }
    state = const AccordAuthInProgress();
    try {
      await _store.persist(session);
      return await _addConnection(session, makeActive: true);
    } catch (e) {
      return _fail(e.toString());
    }
  }

  /// Removes [session] from the saved account list and disconnects it if live.
  /// If it was the active connection, switches to another connected server or
  /// signs out when none remain.
  Future<void> removeAccount(AccordSession session) async {
    final key = _accountKey(session);
    await _store.removeAccount(key);

    final conn = _connections.remove(key);
    if (conn != null) {
      conn.disposeEvents();
      await conn.client.dispose();
      ref.read(connectionsControllerProvider.notifier).remove(key);
    }
    ref.invalidate(readStateControllerProvider(key));
    ref.invalidate(presenceControllerProvider(key));
    ref.read(openTabsControllerProvider.notifier).removeForServer(key);
    unawaited(SpaceCache.remove(key));

    if (_activeKey == key) {
      _activeKey = null;
      final next = _connections.keys.isNotEmpty
          ? _connections.keys.first
          : null;
      if (next != null) {
        await _store.persistActive(_connections[next]!.session);
        _makeActive(next);
      } else {
        await logout();
      }
      return;
    }

    // Clear a stale active pointer left behind by a logged-out removal.
    final rawActive = await _store.readActiveRaw();
    if (rawActive is Map) {
      try {
        final stored = AccordSession.fromJson(
          Map<String, dynamic>.from(rawActive),
        );
        if (_accountKey(stored) == key) {
          await _store.deleteActive();
        }
      } catch (_) {
        // Ignore an unreadable active pointer.
      }
    }
  }

  /// Tears down the live connection [key] (gateway + event subscriptions) and
  /// drops it from the rail registry. Used to replace an account when a new one
  /// signs in to the same server. Does not touch the saved-account list — the
  /// caller's [_persist] dedupes that.
  Future<void> _evictConnection(String key) async {
    final conn = _connections.remove(key);
    if (conn != null) {
      conn.disposeEvents();
      await conn.client.dispose();
    }
    if (_activeKey == key) _activeKey = null;
    ref.read(connectionsControllerProvider.notifier).remove(key);
    ref.invalidate(readStateControllerProvider(key));
    ref.invalidate(presenceControllerProvider(key));
    ref.read(openTabsControllerProvider.notifier).removeForServer(key);
    unawaited(SpaceCache.remove(key));
  }

  /// Connects [session] as a live server (or, if already connected, optionally
  /// makes it active). Background connections (makeActive: false) keep the
  /// current `state` untouched.
  Future<AccordAuthState> _addConnection(
    AccordSession session, {
    required bool makeActive,
  }) async {
    final key = _accountKey(session);
    if (_connections.containsKey(key)) {
      return makeActive ? _makeActive(key) : state;
    }

    // One account per server: a server is owned by a single account at a time.
    // If a *different* account is already live on this server, an explicit
    // (active) login replaces it; a background restore must not stack a second
    // connection onto the same server (which would duplicate its rail group).
    final existingOnServer = keyForBaseUrl(session.server.baseUrl);
    if (existingOnServer != null && existingOnServer != key) {
      if (!makeActive) return state;
      await _evictConnection(existingOnServer);
    }

    ref
        .read(connectionsControllerProvider.notifier)
        .register(session, status: ConnectionStatus.connecting);

    // Seed the rail from the last-known cache so this server's spaces show
    // immediately (dimmed, while connecting/unreachable) instead of waiting on
    // READY — which never arrives if the server is offline. The gateway READY
    // overwrites this with the authoritative list once connected.
    final cachedSpaces = SpaceCache.load(key);
    if (cachedSpaces.isNotEmpty) {
      ref
          .read(connectionsControllerProvider.notifier)
          .setSpaces(key, cachedSpaces);
    }

    final client = AccordClient(
      token: session.token,
      tokenType: session.tokenType,
      baseUrl: session.server.baseUrl,
      gatewayUrl: session.server.gatewayUrl,
      cdnUrl: session.server.cdnUrl,
      onUnauthorized: () => _handleUnauthorized(key),
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
    final disposeEvents = handleAccordEvents(
      ref,
      client,
      serverKey: key,
      currentUserId: session.userId,
      selfDomain: session.server.homeDomain,
      isActive: () => _activeKey == key,
    );
    _connections[key] = _Conn(
      client: client,
      disposeEvents: disposeEvents,
      session: session,
    );
    client.login();

    if (makeActive) return _makeActive(key);
    return state;
  }

  /// Promotes the connection [key] to active: snapshots the outgoing server's
  /// live spaces into its rail cache, seeds the shared rail from [key]'s cache,
  /// mirrors its gateway status onto the global banner, and publishes the
  /// logged-in state. Existing panes/controllers then transparently read the
  /// new active client.
  AccordAuthState _makeActive(String key) {
    final conn = _connections[key];
    if (conn == null) return state;

    final connections = ref.read(connectionsControllerProvider.notifier);

    // Capture the outgoing active server's live spaces (incl. roles, which only
    // the shared controller has) so they persist while it's backgrounded.
    final prevKey = _activeKey;
    if (prevKey != null && prevKey != key) {
      final liveSpaces = ref.read(spacesControllerProvider);
      if (liveSpaces != null) connections.setSpaces(prevKey, liveSpaces);
    }

    _activeKey = key;
    connections.setActive(key);

    // Seed the shared rail/space controllers from this connection's cache so
    // panes have data immediately; the gateway READY refreshes it.
    final cached = connections.spacesFor(key);
    ref.read(spacesControllerProvider.notifier).setSpaces(cached);

    final status =
        ref.read(connectionsControllerProvider).connectionFor(key)?.status ??
        ConnectionStatus.connecting;
    ref.read(connectionControllerProvider.notifier).set(status);
    ref.read(readyControllerProvider.notifier).setReady(true);

    final next = AccordAuthLoggedIn(client: conn.client, session: conn.session);
    state = next;
    unawaited(_store.persistActive(conn.session));
    return next;
  }

  AccordAuthState _fail(String message) {
    final next = AccordAuthFailed(message);
    state = next;
    return next;
  }
}

/// Result of an add-a-server attempt while already logged in. Distinct from the
/// global [AccordAuthState] so the dialog can surface its own MFA/error flow
/// without disturbing the active connection.
class AddServerOutcome {
  final bool ok;
  final String? error;
  final String? mfaTicket;

  const AddServerOutcome._({this.ok = false, this.error, this.mfaTicket});

  factory AddServerOutcome.ok() => const AddServerOutcome._(ok: true);
  factory AddServerOutcome.error(String message) =>
      AddServerOutcome._(error: message);
  factory AddServerOutcome.mfa(String ticket) =>
      AddServerOutcome._(mfaTicket: ticket);

  bool get needsMfa => mfaTicket != null;
}
