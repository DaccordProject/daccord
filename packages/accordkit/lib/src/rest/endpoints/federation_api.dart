import '../endpoint_base.dart';
import '../rest_result.dart';

/// Peer-to-peer federation routes.
///
/// Federation is server-to-server: these calls run against the user's own
/// connected Accord server, which then performs the signed cross-server
/// handshake on the user's behalf.
class FederationApi extends EndpointBase {
  FederationApi(super.rest);

  /// Joins a space homed on a remote federated server identified by [domain]
  /// (the home server's domain) and [spaceId] (the home server's bare space
  /// ID). The connected server runs the signed join handshake, applies the
  /// returned snapshot as a local replica, and responds with
  /// `{ "data": { "space_id": "<qualified>" } }` — the mirrored, qualified
  /// space ID to use as the local handle.
  ///
  /// Errors surface via [RestResult.error] (e.g. federation disabled, the
  /// space is not federation-enabled, or the user is banned).
  Future<RestResult> joinSpace(String domain, String spaceId) {
    return rest.makeRequest(
      'POST',
      '/federation/spaces/join',
      body: {'domain': domain, 'space_id': spaceId},
    );
  }
}
