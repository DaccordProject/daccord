import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

AccordClient? _clientFromState(AccordAuthState s) =>
    s is AccordAuthLoggedIn ? s.client : null;

String? _userIdFromState(AccordAuthState s) =>
    s is AccordAuthLoggedIn ? s.session.userId : null;

String? _cdnUrlFromState(AccordAuthState s) =>
    s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null;

String? _homeDomainFromState(AccordAuthState s) =>
    s is AccordAuthLoggedIn ? s.session.server.homeDomain : null;

bool _isAdminFromState(AccordAuthState s) =>
    s is AccordAuthLoggedIn && s.session.isAdmin;

/// The currently authenticated [AccordClient], or `null` when logged out.
///
/// Centralizes the `accordAuthProvider.select(...)` lookup that was otherwise
/// copy-pasted into ~20 `ConsumerState` getters across the app. The
/// `watch*`/`read*` pairs cover the same authenticated-session fields (user id,
/// CDN base, instance-admin flag) that were likewise inlined at ~40 sites; use
/// the `watch*` variant in `build`/widgets and the `read*` variant in callbacks.
extension AccordClientWidgetRef on WidgetRef {
  AccordClient? get accordClient =>
      read(accordAuthProvider.select(_clientFromState));

  String? watchUserId() => watch(accordAuthProvider.select(_userIdFromState));
  String? readUserId() => read(accordAuthProvider.select(_userIdFromState));

  String? watchCdnUrl() => watch(accordAuthProvider.select(_cdnUrlFromState));
  String? readCdnUrl() => read(accordAuthProvider.select(_cdnUrlFromState));

  String? watchHomeDomain() =>
      watch(accordAuthProvider.select(_homeDomainFromState));
  String? readHomeDomain() =>
      read(accordAuthProvider.select(_homeDomainFromState));

  bool watchIsAdmin() => watch(accordAuthProvider.select(_isAdminFromState));
  bool readIsAdmin() => read(accordAuthProvider.select(_isAdminFromState));
}

/// Same as [AccordClientWidgetRef], for provider/notifier `Ref` contexts.
extension AccordClientRef on Ref {
  AccordClient? get accordClient =>
      read(accordAuthProvider.select(_clientFromState));

  /// The currently authenticated client, re-read on every auth change.
  ///
  /// Use in a controller `build` so the controller rebuilds (and reloads) when
  /// the active account/session changes. Replaces the copy-pasted
  /// `ref.watch(accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null))`.
  AccordClient? watchAccordClient() =>
      watch(accordAuthProvider.select(_clientFromState));

  String? watchUserId() => watch(accordAuthProvider.select(_userIdFromState));
  String? readUserId() => read(accordAuthProvider.select(_userIdFromState));

  String? watchCdnUrl() => watch(accordAuthProvider.select(_cdnUrlFromState));
  String? readCdnUrl() => read(accordAuthProvider.select(_cdnUrlFromState));

  String? watchHomeDomain() =>
      watch(accordAuthProvider.select(_homeDomainFromState));
  String? readHomeDomain() =>
      read(accordAuthProvider.select(_homeDomainFromState));

  bool watchIsAdmin() => watch(accordAuthProvider.select(_isAdminFromState));
  bool readIsAdmin() => read(accordAuthProvider.select(_isAdminFromState));
}
