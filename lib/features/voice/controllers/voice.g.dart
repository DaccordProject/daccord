// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voice.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Orchestrates voice channel join/leave and media toggles (reference:
/// `client_voice.gd`). Owns a single [VoiceSession] (the LiveKit transport) and
/// pushes runtime self-state to the server via `updateVoiceState`.

@ProviderFor(VoiceController)
final voiceControllerProvider = VoiceControllerProvider._();

/// Orchestrates voice channel join/leave and media toggles (reference:
/// `client_voice.gd`). Owns a single [VoiceSession] (the LiveKit transport) and
/// pushes runtime self-state to the server via `updateVoiceState`.
final class VoiceControllerProvider
    extends $NotifierProvider<VoiceController, VoiceConnection> {
  /// Orchestrates voice channel join/leave and media toggles (reference:
  /// `client_voice.gd`). Owns a single [VoiceSession] (the LiveKit transport) and
  /// pushes runtime self-state to the server via `updateVoiceState`.
  VoiceControllerProvider._()
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

String _$voiceControllerHash() => r'98e08c23023e0de28064ea5895c7e7aa9214f68d';

/// Orchestrates voice channel join/leave and media toggles (reference:
/// `client_voice.gd`). Owns a single [VoiceSession] (the LiveKit transport) and
/// pushes runtime self-state to the server via `updateVoiceState`.

abstract class _$VoiceController extends $Notifier<VoiceConnection> {
  VoiceConnection build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VoiceConnection, VoiceConnection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VoiceConnection, VoiceConnection>,
              VoiceConnection,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
