import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

AccordClient? _clientFromState(AccordAuthState s) =>
    s is AccordAuthLoggedIn ? s.client : null;

/// The currently authenticated [AccordClient], or `null` when logged out.
///
/// Centralizes the `accordAuthProvider.select(...)` lookup that was otherwise
/// copy-pasted into ~20 `ConsumerState` getters across the app.
extension AccordClientWidgetRef on WidgetRef {
  AccordClient? get accordClient =>
      read(accordAuthProvider.select(_clientFromState));
}

/// Same as [AccordClientWidgetRef], for provider/notifier `Ref` contexts.
extension AccordClientRef on Ref {
  AccordClient? get accordClient =>
      read(accordAuthProvider.select(_clientFromState));
}
