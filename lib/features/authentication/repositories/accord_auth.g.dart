// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_auth.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Authentication + connection lifecycle against Accord servers. The Accord
/// replacement for the Discord-specific `Auth` provider.
///
/// In the multi-server model this holds N live [AccordClient]s at once (one per
/// connected server, keyed by `userId@baseUrl`) and tracks which one is
/// *active*. `state` (an [AccordAuthLoggedIn]) and [client] always refer to the
/// active connection, so every existing pane/controller keeps reading the active
/// server unchanged. Background connections stay logged in (gateways open,
/// spaces cached in `ConnectionsController`) so the rail can show every server's
/// spaces at once; selecting a space on another server flips the active
/// connection without re-authenticating.

@ProviderFor(AccordAuth)
const accordAuthProvider = AccordAuthProvider._();

/// Authentication + connection lifecycle against Accord servers. The Accord
/// replacement for the Discord-specific `Auth` provider.
///
/// In the multi-server model this holds N live [AccordClient]s at once (one per
/// connected server, keyed by `userId@baseUrl`) and tracks which one is
/// *active*. `state` (an [AccordAuthLoggedIn]) and [client] always refer to the
/// active connection, so every existing pane/controller keeps reading the active
/// server unchanged. Background connections stay logged in (gateways open,
/// spaces cached in `ConnectionsController`) so the rail can show every server's
/// spaces at once; selecting a space on another server flips the active
/// connection without re-authenticating.
final class AccordAuthProvider
    extends $NotifierProvider<AccordAuth, AccordAuthState> {
  /// Authentication + connection lifecycle against Accord servers. The Accord
  /// replacement for the Discord-specific `Auth` provider.
  ///
  /// In the multi-server model this holds N live [AccordClient]s at once (one per
  /// connected server, keyed by `userId@baseUrl`) and tracks which one is
  /// *active*. `state` (an [AccordAuthLoggedIn]) and [client] always refer to the
  /// active connection, so every existing pane/controller keeps reading the active
  /// server unchanged. Background connections stay logged in (gateways open,
  /// spaces cached in `ConnectionsController`) so the rail can show every server's
  /// spaces at once; selecting a space on another server flips the active
  /// connection without re-authenticating.
  const AccordAuthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accordAuthProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accordAuthHash();

  @$internal
  @override
  AccordAuth create() => AccordAuth();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccordAuthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccordAuthState>(value),
    );
  }
}

String _$accordAuthHash() => r'658a86062a3a2b4d5ade7dc67ee61bde1024177e';

/// Authentication + connection lifecycle against Accord servers. The Accord
/// replacement for the Discord-specific `Auth` provider.
///
/// In the multi-server model this holds N live [AccordClient]s at once (one per
/// connected server, keyed by `userId@baseUrl`) and tracks which one is
/// *active*. `state` (an [AccordAuthLoggedIn]) and [client] always refer to the
/// active connection, so every existing pane/controller keeps reading the active
/// server unchanged. Background connections stay logged in (gateways open,
/// spaces cached in `ConnectionsController`) so the rail can show every server's
/// spaces at once; selecting a space on another server flips the active
/// connection without re-authenticating.

abstract class _$AccordAuth extends $Notifier<AccordAuthState> {
  AccordAuthState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AccordAuthState, AccordAuthState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AccordAuthState, AccordAuthState>,
              AccordAuthState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
