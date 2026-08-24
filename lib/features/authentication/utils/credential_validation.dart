/// Client-side registration credential rules, shared by the login screen
/// (`accord_login.dart`) and the Add-a-Server dialog (`add_server_dialog.dart`).
/// Rules are checked in order and the first failing rule's message is
/// returned (`null` when all pass), so callers keep their existing
/// first-error-wins banner behaviour.
///
/// The server enforces all of these authoritatively as well — these checks
/// only exist to fail fast with a friendly message before a network round
/// trip. `AccordAuth`'s register paths repeat the username rule server-side
/// of the forms for callers that bypass the UI.
String? validateRegistrationCredentials({
  required String username,
  required String password,
  required bool tosRequired,
  required bool tosAccepted,
}) {
  // Usernames are the public login identifier (login looks up by username,
  // not email), so reject email-like input rather than silently accepting a
  // misleading account name.
  if (username.contains('@')) {
    return "Username can't be an email address.";
  }
  if (password.length < 8) {
    return 'Password must be at least 8 characters.';
  }
  if (tosRequired && !tosAccepted) {
    return 'You must accept the Terms of Service.';
  }
  return null;
}

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
