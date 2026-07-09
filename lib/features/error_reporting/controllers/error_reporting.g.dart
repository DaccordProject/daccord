// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_reporting.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Opt-in error reporting to a self-hosted GlitchTip (Sentry-compatible)
/// instance. Port of the reference client's `error_reporting.gd` autoload:
/// nothing is initialized — and no network request ever happens — until the
/// user enables [AccordSettings.errorReportingEnabled] (first-launch consent
/// dialog or the settings toggle). State is whether reporting is active.
///
/// Once active it also captures unhandled [FlutterError]s and uncaught async
/// errors, scrubbed through [scrubPiiText]. Breadcrumbs (navigation, message
/// sent, voice errors) carry structural IDs only — never content.

@ProviderFor(ErrorReportingController)
const errorReportingControllerProvider = ErrorReportingControllerProvider._();

/// Opt-in error reporting to a self-hosted GlitchTip (Sentry-compatible)
/// instance. Port of the reference client's `error_reporting.gd` autoload:
/// nothing is initialized — and no network request ever happens — until the
/// user enables [AccordSettings.errorReportingEnabled] (first-launch consent
/// dialog or the settings toggle). State is whether reporting is active.
///
/// Once active it also captures unhandled [FlutterError]s and uncaught async
/// errors, scrubbed through [scrubPiiText]. Breadcrumbs (navigation, message
/// sent, voice errors) carry structural IDs only — never content.
final class ErrorReportingControllerProvider
    extends $NotifierProvider<ErrorReportingController, bool> {
  /// Opt-in error reporting to a self-hosted GlitchTip (Sentry-compatible)
  /// instance. Port of the reference client's `error_reporting.gd` autoload:
  /// nothing is initialized — and no network request ever happens — until the
  /// user enables [AccordSettings.errorReportingEnabled] (first-launch consent
  /// dialog or the settings toggle). State is whether reporting is active.
  ///
  /// Once active it also captures unhandled [FlutterError]s and uncaught async
  /// errors, scrubbed through [scrubPiiText]. Breadcrumbs (navigation, message
  /// sent, voice errors) carry structural IDs only — never content.
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
    r'cd1c309b763f2fedd371e01cde7baf5b61736a39';

/// Opt-in error reporting to a self-hosted GlitchTip (Sentry-compatible)
/// instance. Port of the reference client's `error_reporting.gd` autoload:
/// nothing is initialized — and no network request ever happens — until the
/// user enables [AccordSettings.errorReportingEnabled] (first-launch consent
/// dialog or the settings toggle). State is whether reporting is active.
///
/// Once active it also captures unhandled [FlutterError]s and uncaught async
/// errors, scrubbed through [scrubPiiText]. Breadcrumbs (navigation, message
/// sent, voice errors) carry structural IDs only — never content.

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
