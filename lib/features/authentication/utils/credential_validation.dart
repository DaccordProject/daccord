/// Client-side registration credential rules, shared by the login screen and
/// the Add-a-Server dialog. Returns the first failing rule's message, or null
/// when all pass. The server enforces these authoritatively; this only fails
/// fast with a friendly message before a round trip.
String? validateRegistrationCredentials({
  required String username,
  required String password,
  required bool tosRequired,
  required bool tosAccepted,
}) {
  final usernameError = validateRegistrationUsername(username);
  if (usernameError != null) return usernameError;
  if (password.length < 8) {
    return 'Password must be at least 8 characters.';
  }
  if (tosRequired && !tosAccepted) {
    return 'You must accept the Terms of Service.';
  }
  return null;
}

/// The username rule on its own, for the `AccordAuth` register paths that
/// take already-validated forms but still guard callers that bypass the UI.
/// Usernames are the public login identifier (login looks up by username, not
/// email), so email-like input is rejected rather than silently accepted as a
/// misleading account name.
String? validateRegistrationUsername(String username) =>
    username.contains('@') ? "Username can't be an email address." : null;

/// Client-side validation shared by both forced-password-reset surfaces.
String? validatePasswordChangeCredentials({
  required String oldPassword,
  required String newPassword,
  required String confirmation,
}) {
  if (oldPassword.isEmpty || newPassword.isEmpty) {
    return 'Enter your current and new password.';
  }
  if (newPassword.length < 8) {
    return 'New password must be at least 8 characters.';
  }
  if (newPassword != confirmation) return 'Passwords do not match.';
  return null;
}
