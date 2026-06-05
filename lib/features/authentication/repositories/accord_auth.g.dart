// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_auth.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Authentication + connection lifecycle against an Accord server. The Accord
/// replacement for the Discord-specific `Auth` provider: it owns the live
/// [AccordClient], drives login (credentials → optional MFA → token), persists
/// the session for restore-on-launch, and tears everything down on logout.

@ProviderFor(AccordAuth)
const accordAuthProvider = AccordAuthProvider._();

/// Authentication + connection lifecycle against an Accord server. The Accord
/// replacement for the Discord-specific `Auth` provider: it owns the live
/// [AccordClient], drives login (credentials → optional MFA → token), persists
/// the session for restore-on-launch, and tears everything down on logout.
final class AccordAuthProvider
    extends $NotifierProvider<AccordAuth, AccordAuthState> {
  /// Authentication + connection lifecycle against an Accord server. The Accord
  /// replacement for the Discord-specific `Auth` provider: it owns the live
  /// [AccordClient], drives login (credentials → optional MFA → token), persists
  /// the session for restore-on-launch, and tears everything down on logout.
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

String _$accordAuthHash() => r'604bde085143e4c74a3c777eb1e0a266c3496ffc';

/// Authentication + connection lifecycle against an Accord server. The Accord
/// replacement for the Discord-specific `Auth` provider: it owns the live
/// [AccordClient], drives login (credentials → optional MFA → token), persists
/// the session for restore-on-launch, and tears everything down on logout.

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
