import '../../models/invite.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Invite management: fetch, delete, accept, list, and create.
class InvitesApi extends EndpointBase {
  InvitesApi(super.rest);

  /// Fetches invite details by code.
  Future<RestResult> fetch(String code) async {
    final result = await rest.makeRequest('GET', '/invites/$code');
    return result.deserialize(AccordInvite.fromJson);
  }

  /// Deletes (revokes) an invite by code.
  Future<RestResult> delete(String code) {
    return rest.makeRequest('DELETE', '/invites/$code');
  }

  /// Accepts an invite, joining the associated space.
  Future<RestResult> accept(String code) {
    return rest.makeRequest('POST', '/invites/$code/accept');
  }

  /// Lists all active invites for a space.
  Future<RestResult> listSpace(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/invites');
    return result.deserializeArray(AccordInvite.fromJson);
  }

  /// Lists all active invites for a channel.
  Future<RestResult> listChannel(String channelId) async {
    final result =
        await rest.makeRequest('GET', '/channels/$channelId/invites');
    return result.deserializeArray(AccordInvite.fromJson);
  }

  /// Creates a space-level invite. [data] may include `max_age`/`max_uses`/
  /// `temporary`.
  Future<RestResult> createSpace(String spaceId,
      {Map<String, dynamic> data = const {}}) async {
    final result =
        await rest.makeRequest('POST', '/spaces/$spaceId/invites', body: data);
    return result.deserialize(AccordInvite.fromJson);
  }

  /// Creates a channel-level invite. [data] may include `max_age`/`max_uses`/
  /// `temporary`.
  Future<RestResult> createChannel(String channelId,
      {Map<String, dynamic> data = const {}}) async {
    final result = await rest
        .makeRequest('POST', '/channels/$channelId/invites', body: data);
    return result.deserialize(AccordInvite.fromJson);
  }
}
