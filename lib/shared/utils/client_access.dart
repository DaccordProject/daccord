import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
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

/// Active client and session access for widgets.
/// Use `watch*` in builds and `read*` in callbacks.
extension AccordClientWidgetRef on WidgetRef {
  AccordClient? get accordClient =>
      read(accordAuthProvider.select(_clientFromState));

  String? watchActiveServerKey() =>
      watch(connectionsControllerProvider.select((state) => state.activeKey));

  String? readActiveServerKey() =>
      read(connectionsControllerProvider).activeKey;

  String? watchUserId() => watch(accordAuthProvider.select(_userIdFromState));
  String? readUserId() => read(accordAuthProvider.select(_userIdFromState));

  String? watchCdnUrl() => watch(accordAuthProvider.select(_cdnUrlFromState));
  String? readCdnUrl() => read(accordAuthProvider.select(_cdnUrlFromState));

  String? watchHomeDomain() =>
      watch(accordAuthProvider.select(_homeDomainFromState));

  bool watchIsAdmin() => watch(accordAuthProvider.select(_isAdminFromState));
  bool readIsAdmin() => read(accordAuthProvider.select(_isAdminFromState));
}

/// Client access for provider/notifier `Ref` contexts.
extension AccordClientRef on Ref {
  AccordClient? get accordClient =>
      read(accordAuthProvider.select(_clientFromState));

  String? readActiveServerKey() =>
      read(connectionsControllerProvider).activeKey;

  /// Watches the active client so controller builds reload on account changes.
  AccordClient? watchAccordClient() =>
      watch(accordAuthProvider.select(_clientFromState));

  /// Returns the active client only while it still owns [serverKey]. Provider
  /// families use this with a server-qualified key so a switch rebuilds the
  /// old family to null and late requests can be rejected.
  AccordClient? watchAccordClientFor(String serverKey) => watch(
    accordAuthProvider.select(
      (state) => state is AccordAuthLoggedIn && state.session.key == serverKey
          ? state.client
          : state is AccordAuthLoggedIn && serverKey.isEmpty
          ? state.client
          : null,
    ),
  );

  bool isCurrentAccordClient(String serverKey, AccordClient client) {
    final state = read(accordAuthProvider);
    return state is AccordAuthLoggedIn &&
        (state.session.key == serverKey || serverKey.isEmpty) &&
        identical(state.client, client);
  }
}
