import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connections.g.dart';

/// One connected (or connecting) Accord server in the multi-server rail.
///
/// Holds only what the rail needs to render — the [session] (for the server
/// label/CDN), the gateway [status], and a cached [spaces] list. The live
/// [AccordClient] itself lives in `AccordAuth`, which owns connection
/// lifecycle; this is pure UI state so the rail can show every server's spaces
/// at once while only the active server's panes are live.
class AccordConnection {
  final AccordSession session;
  final ConnectionStatus status;

  /// This server's spaces. For the active connection the authoritative list is
  /// `spacesControllerProvider`; this cache is what the rail shows for the
  /// *other* (background) servers and what seeds the active list on a switch.
  final List<AccordSpace> spaces;

  const AccordConnection({
    required this.session,
    required this.status,
    this.spaces = const [],
  });

  /// Stable identity: user + server, matching `AccordAuth`'s account key.
  String get key => '${session.userId}@${session.server.baseUrl}';

  AccordConnection copyWith({
    ConnectionStatus? status,
    List<AccordSpace>? spaces,
  }) =>
      AccordConnection(
        session: session,
        status: status ?? this.status,
        spaces: spaces ?? this.spaces,
      );
}

/// The set of connected servers and which one is active (drives the panes).
class ConnectionsState {
  final List<AccordConnection> connections;
  final String? activeKey;

  const ConnectionsState({this.connections = const [], this.activeKey});

  ConnectionsState copyWith({
    List<AccordConnection>? connections,
    String? activeKey,
    bool clearActive = false,
  }) =>
      ConnectionsState(
        connections: connections ?? this.connections,
        activeKey: clearActive ? null : (activeKey ?? this.activeKey),
      );

  AccordConnection? get active =>
      connectionFor(activeKey);

  AccordConnection? connectionFor(String? key) {
    if (key == null) return null;
    for (final c in connections) {
      if (c.key == key) return c;
    }
    return null;
  }

  bool get hasMultiple => connections.length > 1;
}

/// Rail-level registry of every connected server (see [AccordConnection]).
///
/// `AccordAuth` writes connection lifecycle here; the gateway event handler
/// writes each server's space cache here. The space rail watches this to render
/// spaces grouped across all connected servers.
@Riverpod(keepAlive: true)
class ConnectionsController extends _$ConnectionsController {
  @override
  ConnectionsState build() => const ConnectionsState();

  /// Adds [session] as a connecting server (or updates its session in place).
  void register(AccordSession session, {ConnectionStatus? status}) {
    final key = '${session.userId}@${session.server.baseUrl}';
    final existing = state.connectionFor(key);
    final conn = AccordConnection(
      session: session,
      status: status ?? existing?.status ?? ConnectionStatus.connecting,
      spaces: existing?.spaces ?? const [],
    );
    state = state.copyWith(connections: _upsert(conn));
  }

  void setStatus(String key, ConnectionStatus status) {
    final existing = state.connectionFor(key);
    if (existing == null) return;
    state = state.copyWith(
      connections: _upsert(existing.copyWith(status: status)),
    );
  }

  /// Replaces a server's cached space list (e.g. after a READY space load).
  void setSpaces(String key, List<AccordSpace> spaces) {
    final existing = state.connectionFor(key);
    if (existing == null) return;
    state = state.copyWith(
      connections: _upsert(existing.copyWith(spaces: spaces)),
    );
  }

  void upsertSpace(String key, AccordSpace space) {
    final existing = state.connectionFor(key);
    if (existing == null) return;
    final spaces = [...existing.spaces];
    final i = spaces.indexWhere((s) => s.id == space.id);
    if (i >= 0) {
      spaces[i] = space;
    } else {
      spaces.add(space);
    }
    state = state.copyWith(connections: _upsert(existing.copyWith(spaces: spaces)));
  }

  void removeSpace(String key, String spaceId) {
    final existing = state.connectionFor(key);
    if (existing == null) return;
    state = state.copyWith(
      connections: _upsert(existing.copyWith(
        spaces: existing.spaces.where((s) => s.id != spaceId).toList(),
      )),
    );
  }

  /// The cached spaces for [key], used to seed the active list on a switch.
  List<AccordSpace> spacesFor(String key) =>
      state.connectionFor(key)?.spaces ?? const [];

  void setActive(String? key) {
    if (key == state.activeKey) return;
    state = state.copyWith(activeKey: key, clearActive: key == null);
  }

  void remove(String key) {
    final remaining = state.connections.where((c) => c.key != key).toList();
    final nextActive = state.activeKey == key ? null : state.activeKey;
    state = ConnectionsState(connections: remaining, activeKey: nextActive);
  }

  void clear() => state = const ConnectionsState();

  List<AccordConnection> _upsert(AccordConnection conn) {
    final list = [...state.connections];
    final i = list.indexWhere((c) => c.key == conn.key);
    if (i >= 0) {
      list[i] = conn;
    } else {
      list.add(conn);
    }
    return list;
  }
}
