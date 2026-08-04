// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(callRingtone)
const callRingtoneProvider = CallRingtoneProvider._();

final class CallRingtoneProvider
    extends $FunctionalProvider<CallRingtone, CallRingtone, CallRingtone>
    with $Provider<CallRingtone> {
  const CallRingtoneProvider._()
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
/// declining an incoming ring. The actual media session is owned by
/// [VoiceController]; this controller layers the ring/accept/decline signaling
/// on top, mirroring how the server models a DM call as "voice join + signaling"
/// (accordserver #32).

@ProviderFor(CallController)
const callControllerProvider = CallControllerProvider._();

/// Orchestrates DM voice/video calls: placing an outgoing call (join voice +
/// `call/ring`), reacting to the `call.*` gateway events, and accepting or
/// declining an incoming ring. The actual media session is owned by
/// [VoiceController]; this controller layers the ring/accept/decline signaling
/// on top, mirroring how the server models a DM call as "voice join + signaling"
/// (accordserver #32).
final class CallControllerProvider
    extends $NotifierProvider<CallController, CallState> {
  /// Orchestrates DM voice/video calls: placing an outgoing call (join voice +
  /// `call/ring`), reacting to the `call.*` gateway events, and accepting or
  /// declining an incoming ring. The actual media session is owned by
  /// [VoiceController]; this controller layers the ring/accept/decline signaling
  /// on top, mirroring how the server models a DM call as "voice join + signaling"
  /// (accordserver #32).
  const CallControllerProvider._()
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

String _$callControllerHash() => r'91b94d8aa746fad76d61b42b5f590267c579df22';

/// Orchestrates DM voice/video calls: placing an outgoing call (join voice +
/// `call/ring`), reacting to the `call.*` gateway events, and accepting or
/// declining an incoming ring. The actual media session is owned by
/// [VoiceController]; this controller layers the ring/accept/decline signaling
/// on top, mirroring how the server models a DM call as "voice join + signaling"
/// (accordserver #32).

abstract class _$CallController extends $Notifier<CallState> {
  CallState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<CallState, CallState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CallState, CallState>,
              CallState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
