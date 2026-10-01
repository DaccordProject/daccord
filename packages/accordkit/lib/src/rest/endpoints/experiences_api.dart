import '../../models/experience.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// The single networking boundary for both turn-based and real-time games.
/// Mutations never automatically replay after a rate-limit response.
class ExperiencesApi extends EndpointBase {
  ExperiencesApi(super.rest);
  String _space(String id) => '/spaces/${Uri.encodeComponent(id)}';
  String _game(String space, String game) =>
      '${_space(space)}/experiences/${Uri.encodeComponent(game)}';
  String _session(String space, String id) =>
      '${_space(space)}/arcade/sessions/${Uri.encodeComponent(id)}';

  Future<RestResult> directory(String space) async =>
      (await rest.makeRequest('GET', '${_space(space)}/experiences/directory'))
          .deserializeArray(AccordExperienceManifest.fromJson);
  Future<RestResult> arcade(String space) =>
      rest.makeRequest('GET', '${_space(space)}/arcade');
  Future<RestResult> configureArcade(String space, {required bool enabled}) =>
      rest.makeRequest('PATCH', '${_space(space)}/arcade',
          body: {'enabled': enabled}, retryOnRateLimit: false);
  Future<RestResult> enable(String space, String game, String version) =>
      rest.makeRequest('PUT', _game(space, game),
          body: {'version': version}, retryOnRateLimit: false);
  Future<RestResult> configure(String space, String game,
          {required bool enabled, int turnTimeoutSeconds = 0}) =>
      rest.makeRequest('PATCH', _game(space, game),
          body: {
            'enabled': enabled,
            'turn_timeout_seconds': turnTimeoutSeconds
          },
          retryOnRateLimit: false);
  Future<RestResult> remove(String space, String game) =>
      rest.makeRequest('DELETE', _game(space, game), retryOnRateLimit: false);
  Future<RestResult> package(String space, String game) =>
      rest.makeRequest('GET', '${_game(space, game)}/package');
  Future<RestResult> sessions(String space) async =>
      (await rest.makeRequest('GET', '${_space(space)}/arcade/sessions'))
          .deserializeArray(AccordExperienceSession.fromJson);
  Future<RestResult> session(String space, String id) async =>
      (await rest.makeRequest('GET', _session(space, id)))
          .deserialize(AccordExperienceSession.fromJson);
  Future<RestResult> create(String space, String game,
          {bool inviteOnly = false, List<String> invited = const []}) async =>
      (await rest.makeRequest('POST', '${_space(space)}/arcade/sessions',
              body: {
                'game_id': game,
                'invite_only': inviteOnly,
                'invited': invited
              },
              retryOnRateLimit: false))
          .deserialize(AccordExperienceSession.fromJson);
  Future<RestResult> membership(
          String space, String id, String operation, int revision,
          {bool spectator = false, bool ready = false}) async =>
      (await rest.makeRequest('POST', '${_session(space, id)}/members',
              body: {
                'operation': operation,
                'revision': revision,
                'spectator': spectator,
                'ready': ready
              },
              retryOnRateLimit: false))
          .deserialize(AccordExperienceSession.fromJson);
  Future<RestResult> action(String space, String id, int revision, String kind,
          {int a = 0, int b = 0, String? promotion}) async =>
      (await rest.makeRequest('POST', '${_session(space, id)}/actions',
              body: {
                'revision': revision,
                'kind': kind,
                'a': a,
                'b': b,
                if (promotion != null) 'promotion': promotion
              },
              retryOnRateLimit: false))
          .deserialize(AccordExperienceSession.fromJson);
}
