// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'load_failed.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether a self-loading cache's initial REST fetch failed (a non-2xx
/// response, a network error, or a timeout).
///
/// The cache controllers hold `null` for "no data", which on its own cannot
/// tell a pane still loading apart from one whose load failed — so a failed
/// fetch used to render as a permanent spinner. This flag is the second bit:
/// `null` + not failed = loading, `null` + failed = show an error with a Retry.
///
/// Written by the controller that owns the fetch (cleared on success, set once
/// its retries are exhausted) and by a pane's Retry button before it
/// re-triggers the load. Keyed by [scope] (which cache: `members`, `messages`,
/// `channels`, `spaces`), the owning connection's [serverKey], and the [id]
/// within it (the space or channel; empty for connection-wide caches).
///
/// Don't watch this provider directly — each feature exposes a named helper
/// (`membersLoadFailedProvider`, `channelsLoadFailedProvider`, …) that fills in
/// its own scope.

@ProviderFor(LoadFailed)
const loadFailedProvider = LoadFailedFamily._();

/// Whether a self-loading cache's initial REST fetch failed (a non-2xx
/// response, a network error, or a timeout).
///
/// The cache controllers hold `null` for "no data", which on its own cannot
/// tell a pane still loading apart from one whose load failed — so a failed
/// fetch used to render as a permanent spinner. This flag is the second bit:
/// `null` + not failed = loading, `null` + failed = show an error with a Retry.
///
/// Written by the controller that owns the fetch (cleared on success, set once
/// its retries are exhausted) and by a pane's Retry button before it
/// re-triggers the load. Keyed by [scope] (which cache: `members`, `messages`,
/// `channels`, `spaces`), the owning connection's [serverKey], and the [id]
/// within it (the space or channel; empty for connection-wide caches).
///
/// Don't watch this provider directly — each feature exposes a named helper
/// (`membersLoadFailedProvider`, `channelsLoadFailedProvider`, …) that fills in
/// its own scope.
final class LoadFailedProvider extends $NotifierProvider<LoadFailed, bool> {
  /// Whether a self-loading cache's initial REST fetch failed (a non-2xx
  /// response, a network error, or a timeout).
  ///
  /// The cache controllers hold `null` for "no data", which on its own cannot
  /// tell a pane still loading apart from one whose load failed — so a failed
  /// fetch used to render as a permanent spinner. This flag is the second bit:
  /// `null` + not failed = loading, `null` + failed = show an error with a Retry.
  ///
  /// Written by the controller that owns the fetch (cleared on success, set once
  /// its retries are exhausted) and by a pane's Retry button before it
  /// re-triggers the load. Keyed by [scope] (which cache: `members`, `messages`,
  /// `channels`, `spaces`), the owning connection's [serverKey], and the [id]
  /// within it (the space or channel; empty for connection-wide caches).
  ///
  /// Don't watch this provider directly — each feature exposes a named helper
  /// (`membersLoadFailedProvider`, `channelsLoadFailedProvider`, …) that fills in
  /// its own scope.
  const LoadFailedProvider._({
    required LoadFailedFamily super.from,
    required (String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'loadFailedProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$loadFailedHash();

  @override
  String toString() {
    return r'loadFailedProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  LoadFailed create() => LoadFailed();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LoadFailedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$loadFailedHash() => r'09220fe5f012b97226a7fabcb21e7fd0566a869c';

/// Whether a self-loading cache's initial REST fetch failed (a non-2xx
/// response, a network error, or a timeout).
///
/// The cache controllers hold `null` for "no data", which on its own cannot
/// tell a pane still loading apart from one whose load failed — so a failed
/// fetch used to render as a permanent spinner. This flag is the second bit:
/// `null` + not failed = loading, `null` + failed = show an error with a Retry.
///
/// Written by the controller that owns the fetch (cleared on success, set once
/// its retries are exhausted) and by a pane's Retry button before it
/// re-triggers the load. Keyed by [scope] (which cache: `members`, `messages`,
/// `channels`, `spaces`), the owning connection's [serverKey], and the [id]
/// within it (the space or channel; empty for connection-wide caches).
///
/// Don't watch this provider directly — each feature exposes a named helper
/// (`membersLoadFailedProvider`, `channelsLoadFailedProvider`, …) that fills in
/// its own scope.

final class LoadFailedFamily extends $Family
    with
        $ClassFamilyOverride<
          LoadFailed,
          bool,
          bool,
          bool,
          (String, String, String)
        > {
  const LoadFailedFamily._()
    : super(
        retry: null,
        name: r'loadFailedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Whether a self-loading cache's initial REST fetch failed (a non-2xx
  /// response, a network error, or a timeout).
  ///
  /// The cache controllers hold `null` for "no data", which on its own cannot
  /// tell a pane still loading apart from one whose load failed — so a failed
  /// fetch used to render as a permanent spinner. This flag is the second bit:
  /// `null` + not failed = loading, `null` + failed = show an error with a Retry.
  ///
  /// Written by the controller that owns the fetch (cleared on success, set once
  /// its retries are exhausted) and by a pane's Retry button before it
  /// re-triggers the load. Keyed by [scope] (which cache: `members`, `messages`,
  /// `channels`, `spaces`), the owning connection's [serverKey], and the [id]
  /// within it (the space or channel; empty for connection-wide caches).
  ///
  /// Don't watch this provider directly — each feature exposes a named helper
  /// (`membersLoadFailedProvider`, `channelsLoadFailedProvider`, …) that fills in
  /// its own scope.

  LoadFailedProvider call(String scope, String serverKey, String id) =>
      LoadFailedProvider._(argument: (scope, serverKey, id), from: this);

  @override
  String toString() => r'loadFailedProvider';
}

/// Whether a self-loading cache's initial REST fetch failed (a non-2xx
/// response, a network error, or a timeout).
///
/// The cache controllers hold `null` for "no data", which on its own cannot
/// tell a pane still loading apart from one whose load failed — so a failed
/// fetch used to render as a permanent spinner. This flag is the second bit:
/// `null` + not failed = loading, `null` + failed = show an error with a Retry.
///
/// Written by the controller that owns the fetch (cleared on success, set once
/// its retries are exhausted) and by a pane's Retry button before it
/// re-triggers the load. Keyed by [scope] (which cache: `members`, `messages`,
/// `channels`, `spaces`), the owning connection's [serverKey], and the [id]
/// within it (the space or channel; empty for connection-wide caches).
///
/// Don't watch this provider directly — each feature exposes a named helper
/// (`membersLoadFailedProvider`, `channelsLoadFailedProvider`, …) that fills in
/// its own scope.

abstract class _$LoadFailed extends $Notifier<bool> {
  late final _$args = ref.$arg as (String, String, String);
  String get scope => _$args.$1;
  String get serverKey => _$args.$2;
  String get id => _$args.$3;

  bool build(String scope, String serverKey, String id);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args.$1, _$args.$2, _$args.$3);
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
