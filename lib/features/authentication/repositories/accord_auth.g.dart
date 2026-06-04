// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_auth.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Authentication + connection lifecycle against an Accord server.

@ProviderFor(AccordAuth)
const accordAuthProvider = AccordAuthProvider._();

/// Authentication + connection lifecycle against an Accord server.
final class AccordAuthProvider
    extends $NotifierProvider<AccordAuth, AccordAuthState> {
  /// Authentication + connection lifecycle against an Accord server.
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

String _$accordAuthHash() => r'0000000000000000000000000000000accordauth';

/// Authentication + connection lifecycle against an Accord server.

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
