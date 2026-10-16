// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_fingerprint.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app-wide [DeviceFingerprint]. Tests override it so no platform channel
/// or vault is touched.

@ProviderFor(deviceFingerprint)
final deviceFingerprintProvider = DeviceFingerprintProvider._();

/// The app-wide [DeviceFingerprint]. Tests override it so no platform channel
/// or vault is touched.

final class DeviceFingerprintProvider
    extends
        $FunctionalProvider<
          DeviceFingerprint,
          DeviceFingerprint,
          DeviceFingerprint
        >
    with $Provider<DeviceFingerprint> {
  /// The app-wide [DeviceFingerprint]. Tests override it so no platform channel
  /// or vault is touched.
  DeviceFingerprintProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceFingerprintProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceFingerprintHash();

  @$internal
  @override
  $ProviderElement<DeviceFingerprint> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DeviceFingerprint create(Ref ref) {
    return deviceFingerprint(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeviceFingerprint value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeviceFingerprint>(value),
    );
  }
}

String _$deviceFingerprintHash() => r'8d35a6e4e6fe117036d732dd6108c77a38a4148c';
