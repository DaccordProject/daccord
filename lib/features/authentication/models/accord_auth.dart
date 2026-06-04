import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/server/models/accord_server.dart';

/// State for the Accord authentication flow. The Accord analogue of Bonfire's
/// `AuthResponse` union, typed against accordkit instead of firebridge.
sealed class AccordAuthState {
  const AccordAuthState();
}

/// No login attempted, or the user has signed out.
class AccordAuthLoggedOut extends AccordAuthState {
  const AccordAuthLoggedOut();
}

/// A login or session restore is underway.
class AccordAuthInProgress extends AccordAuthState {
  const AccordAuthInProgress();
}

/// Credentials were accepted but the server requires a second factor.
/// [ticket] and [server] are carried back into [AccordAuth.submitMfa].
class AccordAuthMfaRequired extends AccordAuthState {
  final String ticket;
  final AccordServer server;
  const AccordAuthMfaRequired({required this.ticket, required this.server});
}

/// A fully authenticated session backed by a live [AccordClient].
class AccordAuthLoggedIn extends AccordAuthState {
  final AccordClient client;
  final AccordSession session;
  const AccordAuthLoggedIn({required this.client, required this.session});
}

/// A login failure with a human-readable [message].
class AccordAuthFailed extends AccordAuthState {
  final String message;
  const AccordAuthFailed(this.message);
}
