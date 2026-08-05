import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/server/models/accord_server_limits.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_limits.g.dart';

/// The connected server's upload limits, refreshed on connect.
///
/// Watches the authenticated client, so switching accounts or servers resets to
/// [AccordServerLimits.fallback] and re-fetches — the limits belong to the
/// deployment, not to the app.
///
/// The fetch is fire-and-forget on purpose: the composer must be usable the
/// instant a channel opens, so it starts on the fallback limits and tightens
/// (or loosens) them a round-trip later. A failed fetch is not an error state —
/// it just leaves the fallback in place, which is what the client did
/// unconditionally before this existed.
@Riverpod(keepAlive: true)
class ServerLimitsController extends _$ServerLimitsController {
  bool _disposed = false;

  @override
  AccordServerLimits build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final client = ref.watchAccordClient();
    if (client != null) {
      // Off the build frame: build() must stay synchronous, and the first read
      // should not wait on the network.
      Future.microtask(() => refresh(client));
    }
    return AccordServerLimits.fallback;
  }

  /// Fetches `GET /settings` and applies whatever limits it reports.
  ///
  /// `/settings` is the public, client-facing settings subset (upload limits,
  /// server name, registration policy, ToS) as opposed to the admin-only
  /// `/admin/settings`; accordkit exposes the latter as `client.admin.settings`
  /// but has no binding for the former, so this makes the raw request the same
  /// way `AccordAuth.fetchServerSettings` does pre-login.
  Future<void> refresh(AccordClient client) async {
    final settings = await _fetchSettings(client);
    if (_disposed) return;
    // Switching accounts mid-flight rebuilds this controller against a new
    // client; a late reply from the old server must not overwrite the new
    // server's limits.
    if (!identical(client, ref.accordClient)) return;
    final limits = AccordServerLimits.fromSettings(settings);
    if (limits != state) state = limits;
  }

  /// Applies an already-fetched settings payload (null when the fetch failed).
  void applySettings(Map<String, dynamic>? settings) {
    if (_disposed) return;
    state = AccordServerLimits.fromSettings(settings);
  }

  Future<Map<String, dynamic>?> _fetchSettings(AccordClient client) async {
    try {
      final result = await client.rest.makeRequest('GET', '/settings');
      if (!result.ok || result.data is! Map) return null;
      final map = Map<String, dynamic>.from(result.data as Map);
      // The server wraps payloads in `{ "data": { ... } }`; older/proxied
      // responses may not.
      final inner = map['data'];
      return inner is Map ? Map<String, dynamic>.from(inner) : map;
    } catch (e) {
      debugPrint('Failed to read server upload limits: $e');
      return null;
    }
  }
}
