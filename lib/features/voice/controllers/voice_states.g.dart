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
const voiceStatesControllerProvider = VoiceStatesControllerFamily._();

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
  const VoiceStatesControllerProvider._({
    required VoiceStatesControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'voiceStatesControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$voiceStatesControllerHash();

  @override
  String toString() {
    return r'voiceStatesControllerProvider'
        ''
        '($argument)';
  }

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

  @override
  bool operator ==(Object other) {
    return other is VoiceStatesControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$voiceStatesControllerHash() =>
    r'4ef41d5e68b3300356e7f6c380f3c0352ffbf420';

/// Global cache of who is in which voice channel, keyed `channel_id → {user_id
/// → state}`. Mirrors the reference client's `_voice_state_cache` (there an
/// `Array` per channel; a nested map here makes user moves/removals O(1)).
///
/// Seeded from the gateway READY payload's voice states and from
/// `channels.fetchVoiceStates`, then kept in sync by `voice.state_update`
/// events (all wired in `accord_event_handler.dart`). A `voice.state_update`
/// with a null `channelId` means the user left voice entirely.

final class VoiceStatesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          VoiceStatesController,
          Map<String, Map<String, AccordVoiceState>>,
          Map<String, Map<String, AccordVoiceState>>,
          Map<String, Map<String, AccordVoiceState>>,
          String
        > {
  const VoiceStatesControllerFamily._()
    : super(
        retry: null,
        name: r'voiceStatesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Global cache of who is in which voice channel, keyed `channel_id → {user_id
  /// → state}`. Mirrors the reference client's `_voice_state_cache` (there an
  /// `Array` per channel; a nested map here makes user moves/removals O(1)).
  ///
  /// Seeded from the gateway READY payload's voice states and from
  /// `channels.fetchVoiceStates`, then kept in sync by `voice.state_update`
  /// events (all wired in `accord_event_handler.dart`). A `voice.state_update`
  /// with a null `channelId` means the user left voice entirely.

  VoiceStatesControllerProvider call(String serverKey) =>
      VoiceStatesControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'voiceStatesControllerProvider';
}

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
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  Map<String, Map<String, AccordVoiceState>> build(String serverKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
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
