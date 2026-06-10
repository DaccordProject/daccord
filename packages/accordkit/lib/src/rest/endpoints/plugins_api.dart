import 'dart:typed_data';

import '../../models/plugin_manifest.dart';
import '../endpoint_base.dart';
import '../multipart_form.dart';
import '../rest_result.dart';

/// Server plugin management: list, install, delete, downloads, sessions,
/// roles, action dispatch, and leaderboards.
class PluginsApi extends EndpointBase {
  PluginsApi(super.rest);

  /// Lists installed plugins for a space, optionally filtered by [type].
  Future<RestResult> listPlugins(String spaceId, {String type = ''}) async {
    final query = <String, dynamic>{};
    if (type.isNotEmpty) query['type'] = type;
    final result =
        await rest.makeRequest('GET', '/spaces/$spaceId/plugins', query: query);
    return result.deserializeArray(AccordPluginManifest.fromJson);
  }

  /// Installs a plugin by uploading a manifest and optional bundle (admin).
  Future<RestResult> installPlugin(
    String spaceId,
    Map<String, dynamic> manifest, {
    Uint8List? bundleData,
    String filename = 'plugin.daccord-plugin',
  }) async {
    final form = MultipartForm();
    form.addJson('manifest', manifest);
    if (bundleData != null && bundleData.isNotEmpty) {
      form.addFile('bundle', filename, bundleData,
          contentType: 'application/zip');
    }
    final result = await rest.makeMultipartRequest(
        'POST', '/spaces/$spaceId/plugins', form);
    return result.deserialize(AccordPluginManifest.fromJson);
  }

  /// Uninstalls a plugin (admin).
  Future<RestResult> deletePlugin(String spaceId, String pluginId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId/plugins/$pluginId');
  }

  /// Downloads the Lua source for a scripted plugin (raw bytes).
  Future<RestResult> getSource(String pluginId) {
    return rest.makeRawRequest('/plugins/$pluginId/source');
  }

  /// Downloads the full plugin bundle ZIP for a native plugin (raw bytes).
  Future<RestResult> getBundle(String pluginId) {
    return rest.makeRawRequest('/plugins/$pluginId/bundle');
  }

  /// Returns active sessions for a channel.
  Future<RestResult> getChannelSessions(String channelId) {
    return rest.makeRequest('GET', '/channels/$channelId/sessions/active');
  }

  /// Returns active sessions across all channels in a space.
  Future<RestResult> getSpaceSessions(String spaceId) {
    return rest.makeRequest('GET', '/spaces/$spaceId/sessions/active');
  }

  /// Creates an activity session in a voice channel.
  Future<RestResult> createSession(String pluginId, String channelId) {
    return rest.makeRequest('POST', '/plugins/$pluginId/sessions',
        body: {'channel_id': channelId});
  }

  /// Ends an activity session.
  Future<RestResult> deleteSession(String pluginId, String sessionId) {
    return rest.makeRequest('DELETE', '/plugins/$pluginId/sessions/$sessionId');
  }

  /// Transitions session state (host only). [state] is "running" or "ended".
  Future<RestResult> updateSessionState(
      String pluginId, String sessionId, String state) {
    return rest.makeRequest('PATCH', '/plugins/$pluginId/sessions/$sessionId',
        body: {'state': state});
  }

  /// Leaves an activity session (non-host).
  Future<RestResult> leaveSession(String pluginId, String sessionId) {
    return rest.makeRequest(
        'POST', '/plugins/$pluginId/sessions/$sessionId/leave');
  }

  /// Assigns a participant role. [role] is "player" or "spectator".
  Future<RestResult> assignRole(
      String pluginId, String sessionId, String userId, String role) {
    return rest.makeRequest(
        'POST', '/plugins/$pluginId/sessions/$sessionId/roles',
        body: {'user_id': userId, 'role': role});
  }

  /// Sends a plugin action (e.g. game move) for scripted plugins.
  Future<RestResult> sendAction(
      String pluginId, String sessionId, Map<String, dynamic> data) {
    return rest.makeRequest(
        'POST', '/plugins/$pluginId/sessions/$sessionId/actions',
        body: data);
  }

  // ── Leaderboards ───────────────────────────────────────────────────────

  /// Submits a score to a leaderboard.
  Future<RestResult> leaderboardSubmit(
      String pluginId, String boardId, double score,
      {Map<String, dynamic> metadata = const {}}) {
    final body = <String, dynamic>{'score': score};
    if (metadata.isNotEmpty) body['metadata'] = metadata;
    return rest.makeRequest(
        'POST', '/plugins/$pluginId/leaderboards/$boardId/submit',
        body: body);
  }

  /// Returns the top entries for a leaderboard.
  Future<RestResult> leaderboardGet(String pluginId, String boardId,
      {int limit = 50}) {
    return rest.makeRequest('GET', '/plugins/$pluginId/leaderboards/$boardId',
        query: {'limit': limit.toString()});
  }

  /// Returns leaderboard entries around the current user's rank.
  Future<RestResult> leaderboardAround(String pluginId, String boardId,
      {int limit = 10}) {
    return rest.makeRequest(
        'GET', '/plugins/$pluginId/leaderboards/$boardId/around',
        query: {'limit': limit.toString()});
  }

  /// Returns a specific user's leaderboard entry.
  Future<RestResult> leaderboardGetUser(
      String pluginId, String boardId, String userId) {
    return rest.makeRequest(
        'GET', '/plugins/$pluginId/leaderboards/$boardId/user/$userId');
  }
}
