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

  /// Logs in directly with an existing [token] (e.g. a bot token or one pasted
  /// by the user). Fetches the account, persists the session, and connects.
  Future<AccordAuthState> loginWithToken({
    required AccordServer server,
    required String token,
    String tokenType = 'User',
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
    String tokenType = 'User',
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
      tokenType: 'User',
      userId: user.id,
      username: user.displayName ?? user.username,
      avatar: user.avatar,
    );
    await _persist(session);
    return await _connect(session);
  }

  Future<void> _persist(AccordSession session) async {
    final box = await Hive.openBox(_sessionBoxName);
    await box.put(_sessionKey, session.toJson());
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
