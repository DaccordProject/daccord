// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voice.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Orchestrates voice channel join/leave and media toggles, the Dart port of
/// the reference `client_voice.gd` + the voice slice of its `AppState`. Owns a
/// single [VoiceSession] (the LiveKit transport) and pushes runtime self-state
/// to the server over the gateway via `updateVoiceState`.

@ProviderFor(VoiceController)
const voiceControllerProvider = VoiceControllerProvider._();

/// Orchestrates voice channel join/leave and media toggles, the Dart port of
/// the reference `client_voice.gd` + the voice slice of its `AppState`. Owns a
/// single [VoiceSession] (the LiveKit transport) and pushes runtime self-state
/// to the server over the gateway via `updateVoiceState`.
final class VoiceControllerProvider
    extends $NotifierProvider<VoiceController, VoiceConnection> {
  /// Orchestrates voice channel join/leave and media toggles, the Dart port of
  /// the reference `client_voice.gd` + the voice slice of its `AppState`. Owns a
  /// single [VoiceSession] (the LiveKit transport) and pushes runtime self-state
  /// to the server over the gateway via `updateVoiceState`.
  const VoiceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceControllerHash();

  @$internal
  @override
  VoiceController create() => VoiceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VoiceConnection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VoiceConnection>(value),
    );
  }
}

String _$voiceControllerHash() => r'418cd737015a29ba2cc87221707ab52c1e0a5963';

/// Orchestrates voice channel join/leave and media toggles, the Dart port of
/// the reference `client_voice.gd` + the voice slice of its `AppState`. Owns a
/// single [VoiceSession] (the LiveKit transport) and pushes runtime self-state
/// to the server over the gateway via `updateVoiceState`.

abstract class _$VoiceController extends $Notifier<VoiceConnection> {
  VoiceConnection build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<VoiceConnection, VoiceConnection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VoiceConnection, VoiceConnection>,
              VoiceConnection,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
