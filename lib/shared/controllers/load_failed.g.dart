// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'load_failed.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether a self-loading cache's initial REST fetch failed. Cache controllers
/// hold `null` for "no data", so this is the second bit: `null` + not failed =
/// loading, `null` + failed = show an error with Retry.
///
/// Keyed by [scope] (`members`, `messages`, `channels`, `spaces`), the owning
/// connection's [serverKey], and the space/channel [id] (empty for
/// connection-wide caches). Watch it through each feature's named helper
/// (`membersLoadFailedProvider`, …), not directly.

@ProviderFor(LoadFailed)
final loadFailedProvider = LoadFailedFamily._();

/// Whether a self-loading cache's initial REST fetch failed. Cache controllers
/// hold `null` for "no data", so this is the second bit: `null` + not failed =
/// loading, `null` + failed = show an error with Retry.
///
/// Keyed by [scope] (`members`, `messages`, `channels`, `spaces`), the owning
/// connection's [serverKey], and the space/channel [id] (empty for
/// connection-wide caches). Watch it through each feature's named helper
/// (`membersLoadFailedProvider`, …), not directly.
final class LoadFailedProvider extends $NotifierProvider<LoadFailed, bool> {
  /// Whether a self-loading cache's initial REST fetch failed. Cache controllers
  /// hold `null` for "no data", so this is the second bit: `null` + not failed =
  /// loading, `null` + failed = show an error with Retry.
  ///
  /// Keyed by [scope] (`members`, `messages`, `channels`, `spaces`), the owning
  /// connection's [serverKey], and the space/channel [id] (empty for
  /// connection-wide caches). Watch it through each feature's named helper
  /// (`membersLoadFailedProvider`, …), not directly.
  LoadFailedProvider._({
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

/// Whether a self-loading cache's initial REST fetch failed. Cache controllers
/// hold `null` for "no data", so this is the second bit: `null` + not failed =
/// loading, `null` + failed = show an error with Retry.
///
/// Keyed by [scope] (`members`, `messages`, `channels`, `spaces`), the owning
/// connection's [serverKey], and the space/channel [id] (empty for
/// connection-wide caches). Watch it through each feature's named helper
/// (`membersLoadFailedProvider`, …), not directly.

final class LoadFailedFamily extends $Family
    with
        $ClassFamilyOverride<
          LoadFailed,
          bool,
          bool,
          bool,
          (String, String, String)
        > {
  LoadFailedFamily._()
    : super(
        retry: null,
        name: r'loadFailedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Whether a self-loading cache's initial REST fetch failed. Cache controllers
  /// hold `null` for "no data", so this is the second bit: `null` + not failed =
  /// loading, `null` + failed = show an error with Retry.
  ///
  /// Keyed by [scope] (`members`, `messages`, `channels`, `spaces`), the owning
  /// connection's [serverKey], and the space/channel [id] (empty for
  /// connection-wide caches). Watch it through each feature's named helper
  /// (`membersLoadFailedProvider`, …), not directly.

  LoadFailedProvider call(String scope, String serverKey, String id) =>
      LoadFailedProvider._(argument: (scope, serverKey, id), from: this);

  @override
  String toString() => r'loadFailedProvider';
}

/// Whether a self-loading cache's initial REST fetch failed. Cache controllers
/// hold `null` for "no data", so this is the second bit: `null` + not failed =
/// loading, `null` + failed = show an error with Retry.
///
/// Keyed by [scope] (`members`, `messages`, `channels`, `spaces`), the owning
/// connection's [serverKey], and the space/channel [id] (empty for
/// connection-wide caches). Watch it through each feature's named helper
/// (`membersLoadFailedProvider`, …), not directly.

abstract class _$LoadFailed extends $Notifier<bool> {
  late final _$args = ref.$arg as (String, String, String);
  String get scope => _$args.$1;
  String get serverKey => _$args.$2;
  String get id => _$args.$3;

  bool build(String scope, String serverKey, String id);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}
