// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voice_states.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Global cache of who is in which voice channel, keyed `channel_id → {user_id
/// → state}`. Mirrors the reference client's `_voice_state_cache` (there an
/// `Array` per channel; a nested map here makes user moves/removals O(1)).
///
/// Seeded from the gateway READY payload's voice states and from
/// `channels.fetchVoiceStates`, then kept in sync by `voice.state_update`
/// events (all wired in `accord_event_handler.dart`). A `voice.state_update`
/// with a null `channelId` means the user left voice entirely.

@ProviderFor(VoiceStatesController)
const voiceStatesControllerProvider = VoiceStatesControllerProvider._();

/// Global cache of who is in which voice channel, keyed `channel_id → {user_id
/// → state}`. Mirrors the reference client's `_voice_state_cache` (there an
/// `Array` per channel; a nested map here makes user moves/removals O(1)).
///
/// Seeded from the gateway READY payload's voice states and from
/// `channels.fetchVoiceStates`, then kept in sync by `voice.state_update`
/// events (all wired in `accord_event_handler.dart`). A `voice.state_update`
/// with a null `channelId` means the user left voice entirely.
final class VoiceStatesControllerProvider
    extends
        $NotifierProvider<
          VoiceStatesController,
          Map<String, Map<String, AccordVoiceState>>
        > {
  /// Global cache of who is in which voice channel, keyed `channel_id → {user_id
  /// → state}`. Mirrors the reference client's `_voice_state_cache` (there an
  /// `Array` per channel; a nested map here makes user moves/removals O(1)).
  ///
  /// Seeded from the gateway READY payload's voice states and from
  /// `channels.fetchVoiceStates`, then kept in sync by `voice.state_update`
  /// events (all wired in `accord_event_handler.dart`). A `voice.state_update`
  /// with a null `channelId` means the user left voice entirely.
  const VoiceStatesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceStatesControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceStatesControllerHash();

  @$internal
  @override
  VoiceStatesController create() => VoiceStatesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, Map<String, AccordVoiceState>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Map<String, Map<String, AccordVoiceState>>>(value),
    );
  }
}

String _$voiceStatesControllerHash() =>
    r'429e660737a94db6f04afc9e36048ee0e51ae79d';

/// Global cache of who is in which voice channel, keyed `channel_id → {user_id
/// → state}`. Mirrors the reference client's `_voice_state_cache` (there an
/// `Array` per channel; a nested map here makes user moves/removals O(1)).
///
/// Seeded from the gateway READY payload's voice states and from
/// `channels.fetchVoiceStates`, then kept in sync by `voice.state_update`
/// events (all wired in `accord_event_handler.dart`). A `voice.state_update`
/// with a null `channelId` means the user left voice entirely.

abstract class _$VoiceStatesController
    extends $Notifier<Map<String, Map<String, AccordVoiceState>>> {
  Map<String, Map<String, AccordVoiceState>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<
              Map<String, Map<String, AccordVoiceState>>,
              Map<String, Map<String, AccordVoiceState>>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, Map<String, AccordVoiceState>>,
                Map<String, Map<String, AccordVoiceState>>
              >,
              Map<String, Map<String, AccordVoiceState>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
