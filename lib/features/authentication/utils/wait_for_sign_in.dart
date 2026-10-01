import 'dart:async';

import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Completes with true once the session is logged in (immediately when it
/// already is), or false if that hasn't happened within [timeout].
Future<bool> waitForSignIn(
  WidgetRef ref, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  if (ref.read(accordAuthProvider) is AccordAuthLoggedIn) return true;
  final completer = Completer<bool>();
  final sub = ref.listenManual<AccordAuthState>(accordAuthProvider, (_, next) {
    if (next is AccordAuthLoggedIn && !completer.isCompleted) {
      completer.complete(true);
    }
  });
  try {
    return await completer.future.timeout(timeout, onTimeout: () => false);
  } finally {
    sub.close();
  }
}
