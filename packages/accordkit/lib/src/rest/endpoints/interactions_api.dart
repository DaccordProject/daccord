import '../endpoint_base.dart';
import '../rest_result.dart';

/// Application command and interaction-response management.
class InteractionsApi extends EndpointBase {
  InteractionsApi(super.rest);

  /// Lists all global application commands.
  Future<RestResult> listGlobalCommands(String appId) {
    return rest.makeRequest('GET', '/applications/$appId/commands');
  }

  /// Creates a global application command.
  Future<RestResult> createGlobalCommand(
      String appId, Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/applications/$appId/commands',
        body: data);
  }

  /// Fetches a single global command by ID.
  Future<RestResult> getGlobalCommand(String appId, String commandId) {
    return rest.makeRequest('GET', '/applications/$appId/commands/$commandId');
  }

  /// Updates an existing global command.
  Future<RestResult> updateGlobalCommand(
      String appId, String commandId, Map<String, dynamic> data) {
    return rest.makeRequest('PATCH', '/applications/$appId/commands/$commandId',
        body: data);
  }

  /// Deletes a global command.
  Future<RestResult> deleteGlobalCommand(String appId, String commandId) {
    return rest.makeRequest(
        'DELETE', '/applications/$appId/commands/$commandId');
  }

  /// Overwrites all global commands with [data]; absent ones are deleted.
  Future<RestResult> bulkOverwriteGlobal(String appId, List<dynamic> data) {
    return rest.makeRequest('PUT', '/applications/$appId/commands', body: data);
  }

  /// Lists all commands registered to a specific space.
  Future<RestResult> listSpaceCommands(String appId, String spaceId) {
    return rest.makeRequest(
        'GET', '/applications/$appId/spaces/$spaceId/commands');
  }

  /// Creates a command scoped to a specific space.
  Future<RestResult> createSpaceCommand(
      String appId, String spaceId, Map<String, dynamic> data) {
    return rest.makeRequest(
        'POST', '/applications/$appId/spaces/$spaceId/commands',
        body: data);
  }

  /// Sends an initial response to an interaction.
  Future<RestResult> respond(
      String interactionId, String token, Map<String, dynamic> data) {
    return rest.makeRequest(
        'POST', '/interactions/$interactionId/$token/callback',
        body: data);
  }

  /// Edits the original interaction response message.
  Future<RestResult> editOriginal(
      String appId, String token, Map<String, dynamic> data) {
    return rest.makeRequest(
        'PATCH', '/webhooks/$appId/$token/messages/@original',
        body: data);
  }

  /// Deletes the original interaction response message.
  Future<RestResult> deleteOriginal(String appId, String token) {
    return rest.makeRequest(
        'DELETE', '/webhooks/$appId/$token/messages/@original');
  }

  /// Sends a follow-up message (valid for up to 15 minutes).
  Future<RestResult> followup(
      String appId, String token, Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/webhooks/$appId/$token', body: data);
  }
}
