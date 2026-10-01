import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/server/models/accord_server_limits.dart';
import 'package:bonfire/shared/utils/client_access.dart';
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
/// it just leaves the fallback in place.
@Riverpod(keepAlive: true)
class ServerLimitsController extends _$ServerLimitsController {
  @override
  AccordServerLimits build() {
    final client = ref.watchAccordClient();
    if (client != null) {
      // Off the build frame: build() must stay synchronous, and the first read
      // should not wait on the network.
      Future.microtask(() => _refresh(client));
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
  Future<void> _refresh(AccordClient client) async {
    final result = await client.rest.makeRequest('GET', '/settings');
    if (!ref.mounted) return;
    // Switching accounts mid-flight rebuilds this controller against a new
    // client; a late reply from the old server must not overwrite the new
    // server's limits.
    if (!identical(client, ref.accordClient)) return;
    final map = result.ok ? asMap(result.data) : null;
    // The server wraps payloads in `{ "data": { ... } }`; proxied responses
    // may not.
    final limits = AccordServerLimits.fromSettings(asMap(map?['data']) ?? map);
    if (limits != state) state = limits;
  }
}
