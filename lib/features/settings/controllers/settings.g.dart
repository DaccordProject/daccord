// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Local client preferences (theme, notifications, recent emoji), persisted to
/// the `accord-settings` Hive box (opened in `setupHive`). Watched by `main`
/// to build the active [ThemeData] and by the notification + emoji layers.

@ProviderFor(SettingsController)
const settingsControllerProvider = SettingsControllerProvider._();

/// Local client preferences (theme, notifications, recent emoji), persisted to
/// the `accord-settings` Hive box (opened in `setupHive`). Watched by `main`
/// to build the active [ThemeData] and by the notification + emoji layers.
final class SettingsControllerProvider
    extends $NotifierProvider<SettingsController, AccordSettings> {
  /// Local client preferences (theme, notifications, recent emoji), persisted to
  /// the `accord-settings` Hive box (opened in `setupHive`). Watched by `main`
  /// to build the active [ThemeData] and by the notification + emoji layers.
  const SettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsControllerHash();

  @$internal
  @override
  SettingsController create() => SettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccordSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccordSettings>(value),
    );
  }
}

String _$settingsControllerHash() =>
    r'be9474487c6a2a0407da260d77793f71e16004a5';

/// Local client preferences (theme, notifications, recent emoji), persisted to
/// the `accord-settings` Hive box (opened in `setupHive`). Watched by `main`
/// to build the active [ThemeData] and by the notification + emoji layers.

abstract class _$SettingsController extends $Notifier<AccordSettings> {
  AccordSettings build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AccordSettings, AccordSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AccordSettings, AccordSettings>,
              AccordSettings,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
