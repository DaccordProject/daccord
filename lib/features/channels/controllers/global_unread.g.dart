// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'global_unread.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The unread state of the *whole app*, across every connected server.
///
/// Drives the desktop taskbar/dock badge (`TaskbarBadgeController`) and is
/// reusable for a future tray icon or mobile app-icon badge. Kept alive because
/// its consumers are services, not widgets, and it must keep updating while the
/// window is minimised.

@ProviderFor(globalUnread)
const globalUnreadProvider = GlobalUnreadProvider._();

/// The unread state of the *whole app*, across every connected server.
///
/// Drives the desktop taskbar/dock badge (`TaskbarBadgeController`) and is
/// reusable for a future tray icon or mobile app-icon badge. Kept alive because
/// its consumers are services, not widgets, and it must keep updating while the
/// window is minimised.

final class GlobalUnreadProvider
    extends $FunctionalProvider<GlobalUnread, GlobalUnread, GlobalUnread>
    with $Provider<GlobalUnread> {
  /// The unread state of the *whole app*, across every connected server.
  ///
  /// Drives the desktop taskbar/dock badge (`TaskbarBadgeController`) and is
  /// reusable for a future tray icon or mobile app-icon badge. Kept alive because
  /// its consumers are services, not widgets, and it must keep updating while the
  /// window is minimised.
  const GlobalUnreadProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'globalUnreadProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$globalUnreadHash();

  @$internal
  @override
  $ProviderElement<GlobalUnread> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GlobalUnread create(Ref ref) {
    return globalUnread(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GlobalUnread value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GlobalUnread>(value),
    );
  }
}

String _$globalUnreadHash() => r'4d164416e7524584ee25944461db0b3ba7993672';
