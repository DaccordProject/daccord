// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profiles_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Reactive view over the local device-profile registry. Delegates persistence
/// to [ProfileStore] and re-reads after each mutation so the profiles page and
/// the lock gate update together.

@ProviderFor(ProfilesController)
const profilesControllerProvider = ProfilesControllerProvider._();

/// Reactive view over the local device-profile registry. Delegates persistence
/// to [ProfileStore] and re-reads after each mutation so the profiles page and
/// the lock gate update together.
final class ProfilesControllerProvider
    extends $NotifierProvider<ProfilesController, List<DeviceProfile>> {
  /// Reactive view over the local device-profile registry. Delegates persistence
  /// to [ProfileStore] and re-reads after each mutation so the profiles page and
  /// the lock gate update together.
  const ProfilesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profilesControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profilesControllerHash();

  @$internal
  @override
  ProfilesController create() => ProfilesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<DeviceProfile> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<DeviceProfile>>(value),
    );
  }
}

String _$profilesControllerHash() =>
    r'74cc74f88f4caa71077cb02c9efab45c8225ff8c';

/// Reactive view over the local device-profile registry. Delegates persistence
/// to [ProfileStore] and re-reads after each mutation so the profiles page and
/// the lock gate update together.

abstract class _$ProfilesController extends $Notifier<List<DeviceProfile>> {
  List<DeviceProfile> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<List<DeviceProfile>, List<DeviceProfile>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<DeviceProfile>, List<DeviceProfile>>,
              List<DeviceProfile>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
