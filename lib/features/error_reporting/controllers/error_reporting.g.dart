// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_reporting.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ErrorReportingController)
const errorReportingControllerProvider = ErrorReportingControllerProvider._();

final class ErrorReportingControllerProvider
    extends $NotifierProvider<ErrorReportingController, bool> {
  const ErrorReportingControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'errorReportingControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$errorReportingControllerHash();

  @$internal
  @override
  ErrorReportingController create() => ErrorReportingController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$errorReportingControllerHash() =>
    r'0000000000000000000000000000000000000000';

abstract class _$ErrorReportingController extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
