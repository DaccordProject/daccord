import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/controllers/ready.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/controllers/accord_event_handler.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/utils/space_cache.dart';
import 'package:bonfire/features/spaces/controllers/space.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
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
  static const _sessionBoxName = 'accord-session';
  static const _sessionKey = 'session';
  static const _accountsKey = 'accounts';

  final Map<String, _Conn> _connections = {};
  String? _activeKey;

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
    // Usernames are the public login identifier (login is by username, not
    // email); reject email-like values before hitting the server. The server
    // enforces this authoritatively as well.
    if (username.contains('@')) {
      return _fail("Username can't be an email address.");
    }
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
    final box = await Hive.openBox(_sessionBoxName);
    final raw = box.get(_sessionKey);
    if (raw == null) {
      return const AccordAuthLoggedOut();
    }

    AccordSession? active;
    try {
      active = AccordSession.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      debugPrint('Failed to restore Accord session: $e');
      await box.delete(_sessionKey);
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

    final box = await Hive.openBox(_sessionBoxName);
    await box.delete(_sessionKey);

    ref.read(connectionsControllerProvider.notifier).clear();
    ref.invalidate(readStateControllerProvider);
    ref.read(openTabsControllerProvider.notifier).clear();
    unawaited(SpaceCache.clear());
    ref.read(spacesControllerProvider.notifier).setSpaces(const []);
    ref
        .read(connectionControllerProvider.notifier)
        .set(ConnectionStatus.disconnected);
    ref.read(readyControllerProvider.notifier).setReady(false);
    state = const AccordAuthLoggedOut();
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
      await _persist(session);
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
    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.login({
        'username': username,
        'password': password,
      });
      if (!result.ok) {
        return AddServerOutcome.error(result.error?.message ?? 'Login failed');
      }
      final data = result.data;
      if (data is Map && data['mfa_required'] == true) {
        return AddServerOutcome.mfa(data['ticket']?.toString() ?? '');
      }
      return await _completeAddServer(server, data);
    } catch (e) {
      return AddServerOutcome.error(e.toString());
    } finally {
      await authClient.dispose();
    }
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
    final authClient = _restClientFor(server);
    try {
      final dn = displayName?.trim();
      final result = await authClient.auth.register({
        'username': username,
        'password': password,
        'display_name': (dn == null || dn.isEmpty) ? username : dn,
      });
      if (!result.ok) {
        return AddServerOutcome.error(
          result.error?.message ?? 'Registration failed',
        );
      }
      return await _completeAddServer(server, result.data);
    } catch (e) {
      return AddServerOutcome.error(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  /// Completes an MFA challenge raised by [addServerWithCredentials].
  Future<AddServerOutcome> addServerSubmitMfa(
    AccordServer server,
    String ticket,
    String code,
  ) async {
    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.loginMfa({
        'ticket': ticket,
        'code': code,
      });
      if (!result.ok) {
        return AddServerOutcome.error(
          result.error?.message ?? 'Invalid two-factor code',
        );
      }
      return await _completeAddServer(server, result.data);
    } catch (e) {
      return AddServerOutcome.error(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  Future<AddServerOutcome> _completeAddServer(
    AccordServer server,
    Object? data,
  ) async {
    if (data is! Map) return AddServerOutcome.error('Malformed auth response');
    final token = data['token']?.toString();
    final user = data['user'];
    if (token == null || user is! AccordUser) {
      return AddServerOutcome.error('Auth response missing token or user');
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
    await _persist(session);
    await _addConnection(session, makeActive: true);
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
      final user = me.data as AccordUser;
      return AccordSession(
        server: server,
        token: token,
        tokenType: tokenType,
        userId: user.id,
        username: user.displayName ?? user.username,
        avatar: user.avatar,
        isAdmin: user.isAdmin,
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
    return await _addConnection(session, makeActive: true);
  }

  AccordAuthState _resetRequired(AccordSession pending, {String? error}) {
    final next = AccordAuthPasswordResetRequired(pending, error: error);
    state = next;
    return next;
  }

  /// Persists [session] as the active session and upserts it into the saved
  /// account list (keyed by user + server) for the account switcher. Enforces
  /// one account per server: any other saved account on the same server is
  /// dropped, so signing in as a new user replaces the old one rather than
  /// leaving a stale duplicate.
  Future<void> _persist(AccordSession session) async {
    final box = await Hive.openBox(_sessionBoxName);
    await box.put(_sessionKey, session.toJson());
    final accounts = _readAccounts(box);
    final key = _accountKey(session);
    accounts.removeWhere((k, v) {
      if (k == key || v is! Map) return false;
      try {
        final other = AccordSession.fromJson(Map<String, dynamic>.from(v));
        return other.server.baseUrl == session.server.baseUrl;
      } catch (_) {
        return false;
      }
    });
    accounts[key] = session.toJson();
    await box.put(_accountsKey, accounts);
  }

  /// Records [session] as the persisted *active* pointer without touching the
  /// saved-accounts list (already persisted when first added).
  Future<void> _persistActive(AccordSession session) async {
    final box = await Hive.openBox(_sessionBoxName);
    await box.put(_sessionKey, session.toJson());
  }

  String _accountKey(AccordSession session) => session.key;

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

  /// Switches the active session to a previously saved [session]. If it is
  /// already connected this just flips active; otherwise it connects it.
  Future<AccordAuthState> switchTo(AccordSession session) async {
    final key = _accountKey(session);
    if (_connections.containsKey(key)) {
      await _persistActive(session);
      return _makeActive(key);
    }
    state = const AccordAuthInProgress();
    try {
      await _persist(session);
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
    final box = await Hive.openBox(_sessionBoxName);
    final accounts = _readAccounts(box);
    accounts.remove(key);
    await box.put(_accountsKey, accounts);

    final conn = _connections.remove(key);
    if (conn != null) {
      conn.disposeEvents();
      await conn.client.dispose();
      ref.read(connectionsControllerProvider.notifier).remove(key);
    }
    ref.invalidate(readStateControllerProvider(key));
    ref.read(openTabsControllerProvider.notifier).removeForServer(key);
    unawaited(SpaceCache.remove(key));

    if (_activeKey == key) {
      _activeKey = null;
      final next = _connections.keys.isNotEmpty
          ? _connections.keys.first
          : null;
      if (next != null) {
        await _persistActive(_connections[next]!.session);
        _makeActive(next);
      } else {
        await logout();
      }
      return;
    }

    // Clear a stale active pointer left behind by a logged-out removal.
    final rawActive = box.get(_sessionKey);
    if (rawActive is Map) {
      try {
        final stored = AccordSession.fromJson(
          Map<String, dynamic>.from(rawActive),
        );
        if (_accountKey(stored) == key) {
          await box.delete(_sessionKey);
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
    for (final space in cached) {
      ref.read(spaceControllerProvider(space.id).notifier).setSpace(space);
    }

    final status =
        ref.read(connectionsControllerProvider).connectionFor(key)?.status ??
        ConnectionStatus.connecting;
    ref.read(connectionControllerProvider.notifier).set(status);
    ref.read(readyControllerProvider.notifier).setReady(true);

    final next = AccordAuthLoggedIn(client: conn.client, session: conn.session);
    state = next;
    unawaited(_persistActive(conn.session));
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
