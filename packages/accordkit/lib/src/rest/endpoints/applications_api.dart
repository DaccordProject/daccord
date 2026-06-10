import '../endpoint_base.dart';
import '../rest_result.dart';

/// Application management: create, fetch/update current app, reset bot token.
class ApplicationsApi extends EndpointBase {
  ApplicationsApi(super.rest);

  /// Creates a new application.
  Future<RestResult> create(Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/applications', body: data);
  }

  /// Fetches the current application's details.
  Future<RestResult> getMe() {
    return rest.makeRequest('GET', '/applications/@me');
  }

  /// Updates the current application's settings.
  Future<RestResult> updateMe(Map<String, dynamic> data) {
    return rest.makeRequest('PATCH', '/applications/@me', body: data);
  }

  /// Resets the current application's bot token, invalidating the old one.
  Future<RestResult> resetToken() {
    return rest.makeRequest('POST', '/applications/@me/reset-token');
  }
}
