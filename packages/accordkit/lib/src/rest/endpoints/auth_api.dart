import '../../models/user.dart';
import '../../utils/json_utils.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Authentication routes (register, login, MFA, guest tokens, 2FA, sessions).
///
/// On successful register/login, [RestResult.data] is a map shaped like
/// `{ "user": AccordUser, "token": String, "force_password_reset"?: true }`.
class AuthApi extends EndpointBase {
  AuthApi(super.rest);

  /// Registers a new user account. [data] needs `username` and `password`,
  /// optionally `display_name`.
  Future<RestResult> register(Map<String, dynamic> data) async {
    final result = await rest.makeRequest('POST', '/auth/register', body: data);
    final d = result.data;
    if (result.ok && d is Map<String, dynamic>) {
      result.data = _parseAuthResponse(d);
    }
    return result;
  }

  /// Logs in with existing credentials. Returns the auth map, or
  /// `{ "mfa_required": true, "ticket": String }` when 2FA is enabled.
  Future<RestResult> login(Map<String, dynamic> data) async {
    final result = await rest.makeRequest('POST', '/auth/login', body: data);
    final d = result.data;
    if (result.ok && d is Map<String, dynamic>) {
      if (d['mfa_required'] != true) {
        result.data = _parseAuthResponse(d);
      }
    }
    return result;
  }

  /// Completes MFA login with a TOTP or backup code. [data] needs `ticket`
  /// and `code`.
  Future<RestResult> loginMfa(Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('POST', '/auth/login/mfa', body: data);
    final d = result.data;
    if (result.ok && d is Map<String, dynamic>) {
      result.data = _parseAuthResponse(d);
    }
    return result;
  }

  /// Requests a short-lived guest token for anonymous read-only access.
  Future<RestResult> guest() {
    return rest.makeRequest('POST', '/auth/guest');
  }

  /// Changes the current user's password. [data] needs `old_password` and
  /// `new_password`.
  Future<RestResult> changePassword(Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/auth/change-password', body: data);
  }

  /// Enables 2FA, returning a TOTP secret and otpauth URI. [data] needs
  /// `password`.
  Future<RestResult> enable2fa(Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/auth/2fa/enable', body: data);
  }

  /// Verifies a 2FA code during setup. [data] needs `code`.
  Future<RestResult> verify2fa(Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/auth/2fa/verify', body: data);
  }

  /// Disables 2FA. [data] needs `password`.
  Future<RestResult> disable2fa(Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/auth/2fa/disable', body: data);
  }

  /// Regenerates 2FA backup codes. [data] needs `password`.
  Future<RestResult> regenerateBackupCodes(Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/auth/2fa/backup-codes', body: data);
  }

  /// Revokes all sessions for the current user.
  Future<RestResult> revokeAllSessions() {
    return rest.makeRequest('POST', '/auth/sessions/revoke-all');
  }

  Map<String, dynamic> _parseAuthResponse(Map<String, dynamic> d) {
    final parsed = <String, dynamic>{};
    final user = asMap(d['user']);
    if (user != null) parsed['user'] = AccordUser.fromJson(user);
    if (d.containsKey('token')) parsed['token'] = asString(d['token']);
    if (d['force_password_reset'] == true) {
      parsed['force_password_reset'] = true;
    }
    return parsed;
  }
}
