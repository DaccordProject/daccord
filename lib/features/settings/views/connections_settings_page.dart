import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/components/settings_scaffold.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the OAuth Connections page: the third-party accounts linked to the
/// current user, each with a Disconnect action. Ports the reference client's
/// `server_settings.gd` `_build_connections_page` (`GET /users/@me/connections`
/// + `DELETE /users/@me/connections/{id}`).
Future<void> showConnectionsSettings(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
}

/// A linked third-party connection (raw — accordkit returns untyped JSON here).
class _Connection {
  const _Connection({required this.id, required this.type, required this.name});

  final String id;
  final String type;
  final String name;
}

class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key, this.embedded = false});

  /// When true, renders the connection list on its own — no [SettingsScaffold]
  /// chrome and no internal scroll view — so the wide settings layout can
  /// inline it as a card in the Account pane instead of pushing a route.
  final bool embedded;

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  bool _loading = true;
  String? _error;

  /// True once the server has told us it has no connections endpoint at all
  /// (see [_unsupportedStatuses]). Distinct from "loaded, but empty".
  bool _unsupported = false;
  List<_Connection> _connections = const [];
  final Set<String> _disconnecting = {};

  AccordClient? get _client => ref.accordClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) {
      setState(() {
        _loading = false;
        _error = 'Not connected.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _unsupported = false;
    });
    final result = await client.users.listConnections();
    if (!mounted) return;
    if (!result.ok) {
      if (_unsupportedStatuses.contains(result.statusCode)) {
        setState(() {
          _loading = false;
          _unsupported = true;
          _connections = const [];
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Failed to load connections.';
      });
      return;
    }
    final data = result.data;
    final list = <_Connection>[];
    if (data is List) {
      for (final raw in data) {
        if (raw is Map) {
          list.add(
            _Connection(
              id: (raw['id'] ?? '').toString(),
              type: (raw['type'] ?? 'Unknown').toString(),
              name: (raw['name'] ?? '').toString(),
            ),
          );
        }
      }
    }
    setState(() {
      _loading = false;
      _connections = list;
    });
  }

  Future<void> _disconnect(_Connection conn) async {
    final client = _client;
    if (client == null || conn.id.isEmpty || _disconnecting.contains(conn.id)) {
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: 'Disconnect',
      message:
          'Disconnect ${conn.type}${conn.name.isNotEmpty ? ' (${conn.name})' : ''}?',
      confirmLabel: 'Disconnect',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _disconnecting.add(conn.id));
    final result = await client.rest.makeRequest(
      'DELETE',
      '/users/@me/connections/${conn.id}',
    );
    if (!mounted) return;
    setState(() => _disconnecting.remove(conn.id));
    if (!result.ok) {
      showErrorSnack(context, result, prefix: 'Failed');
      return;
    }
    setState(() {
      _connections = [
        for (final c in _connections)
          if (c.id != conn.id) c,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Embedded, on a server without the endpoint: drop the card entirely rather
    // than leave a "Connections" heading that can never hold anything (#292).
    if (widget.embedded && _unsupported) return const SizedBox.shrink();
    if (widget.embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Connections',
            trailing: IconButton(
              tooltip: 'Refresh',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
          ..._embeddedChildren(colors),
        ],
      );
    }
    return SettingsScaffold(
      title: 'Connections',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _body(colors),
    );
  }

  Widget _body(BonfireThemeExtension colors) {
    if (_loading) {
      return const LoadingView();
    }
    if (_error != null) {
      return InlineError(_error!);
    }
    if (_connections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _unsupported ? _unsupportedMessage : _emptyMessage,
            textAlign: TextAlign.center,
            style: _hint(colors),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: _connectionTiles(colors),
    );
  }

  /// Same state machine as [_body], but every arm is intrinsically sized so it
  /// can sit inside the Account pane's card column.
  List<Widget> _embeddedChildren(BonfireThemeExtension colors) {
    if (_loading) {
      return const [SizedBox(height: 72, child: LoadingView())];
    }
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: InlineError(_error!, centered: false),
        ),
      ];
    }
    if (_connections.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(_emptyMessage, style: _hint(colors)),
        ),
      ];
    }
    return _connectionTiles(colors);
  }

  /// HTTP statuses that mean "this server has no connections endpoint": the
  /// route is absent (404), unimplemented (501), or exists but doesn't answer
  /// GET (405). None of them is something the user can retry or fix, so they
  /// render as a neutral statement of capability rather than a red error — the
  /// live server currently 404s here, which is what put a permanent "Failed to
  /// load connections." at the top of the Account pane (#292).
  static const _unsupportedStatuses = {404, 405, 501};

  static const _emptyMessage =
      'No connections linked.\n\nLinked third-party accounts (OAuth) will '
      'appear here.';

  static const _unsupportedMessage =
      "This server doesn't support linked third-party accounts.";

  TextStyle _hint(BonfireThemeExtension colors) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.gray);

  List<Widget> _connectionTiles(BonfireThemeExtension colors) => [
    for (final conn in _connections)
      ListTile(
        leading: Icon(Icons.link, color: colors.dirtyWhite),
        title: Text(conn.type),
        subtitle: conn.name.isEmpty ? null : Text(conn.name),
        trailing: _disconnecting.contains(conn.id)
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.red,
                  side: BorderSide(color: colors.red),
                ),
                onPressed: () => _disconnect(conn),
                child: const Text('Disconnect'),
              ),
      ),
  ];
}
