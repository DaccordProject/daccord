// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(callRingtone)
final callRingtoneProvider = CallRingtoneProvider._();

final class CallRingtoneProvider
    extends $FunctionalProvider<CallRingtone, CallRingtone, CallRingtone>
    with $Provider<CallRingtone> {
  CallRingtoneProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'callRingtoneProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$callRingtoneHash();

  @$internal
  @override
  $ProviderElement<CallRingtone> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CallRingtone create(Ref ref) {
    return callRingtone(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CallRingtone value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CallRingtone>(value),
    );
  }
}

String _$callRingtoneHash() => r'ea4321143cf6dbd77936e59a484393163e432a1a';

/// Orchestrates DM voice/video calls: placing an outgoing call (join voice +
/// `call/ring`), reacting to the `call.*` gateway events, and accepting or
/// declining an incoming ring. The media session is owned by [VoiceController];
/// this layers the ring/accept/decline signaling on top, matching the server's
/// model of a DM call as "voice join + signaling".

@ProviderFor(CallController)
final callControllerProvider = CallControllerProvider._();

/// Orchestrates DM voice/video calls: placing an outgoing call (join voice +
/// `call/ring`), reacting to the `call.*` gateway events, and accepting or
/// declining an incoming ring. The media session is owned by [VoiceController];
/// this layers the ring/accept/decline signaling on top, matching the server's
/// model of a DM call as "voice join + signaling".
final class CallControllerProvider
    extends $NotifierProvider<CallController, CallState> {
  /// Orchestrates DM voice/video calls: placing an outgoing call (join voice +
  /// `call/ring`), reacting to the `call.*` gateway events, and accepting or
  /// declining an incoming ring. The media session is owned by [VoiceController];
  /// this layers the ring/accept/decline signaling on top, matching the server's
  /// model of a DM call as "voice join + signaling".
  CallControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'callControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$callControllerHash();

  @$internal
  @override
  CallController create() => CallController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CallState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CallState>(value),
    );
  }
}

String _$callControllerHash() => r'c5421e11c01cc8952339d2eb1f23c6822b0beb25';

/// Orchestrates DM voice/video calls: placing an outgoing call (join voice +
/// `call/ring`), reacting to the `call.*` gateway events, and accepting or
/// declining an incoming ring. The media session is owned by [VoiceController];
/// this layers the ring/accept/decline signaling on top, matching the server's
/// model of a DM call as "voice join + signaling".

abstract class _$CallController extends $Notifier<CallState> {
  CallState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CallState, CallState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CallState, CallState>,
              CallState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
