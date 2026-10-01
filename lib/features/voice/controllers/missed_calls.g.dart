// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'missed_calls.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Unanswered incoming DM calls, keyed by channel id.
///
/// Recorded by [CallController] when a ring ends without a local accept
/// (`call.cancel`/`call.end` while still ringing, or our client-side ring
/// timeout — accordserver implements no ring timer of its own). An **explicitly
/// declined** call is deliberately *not* recorded: the user already saw and
/// answered the prompt, so re-surfacing it as an unread badge would be noise.
///
/// **Session-only.** The entries live in memory and are gone after a restart:
/// the record is an attention cue rather than a call log, and Accord has no
/// call-history API to reconcile against.
///
/// Keyed by channel id alone; ids are per-server snowflakes, so two servers
/// minting the same DM channel id could (unlikely) collide.

@ProviderFor(MissedCallsController)
final missedCallsControllerProvider = MissedCallsControllerProvider._();

/// Unanswered incoming DM calls, keyed by channel id.
///
/// Recorded by [CallController] when a ring ends without a local accept
/// (`call.cancel`/`call.end` while still ringing, or our client-side ring
/// timeout — accordserver implements no ring timer of its own). An **explicitly
/// declined** call is deliberately *not* recorded: the user already saw and
/// answered the prompt, so re-surfacing it as an unread badge would be noise.
///
/// **Session-only.** The entries live in memory and are gone after a restart:
/// the record is an attention cue rather than a call log, and Accord has no
/// call-history API to reconcile against.
///
/// Keyed by channel id alone; ids are per-server snowflakes, so two servers
/// minting the same DM channel id could (unlikely) collide.
final class MissedCallsControllerProvider
    extends $NotifierProvider<MissedCallsController, Map<String, MissedCall>> {
  /// Unanswered incoming DM calls, keyed by channel id.
  ///
  /// Recorded by [CallController] when a ring ends without a local accept
  /// (`call.cancel`/`call.end` while still ringing, or our client-side ring
  /// timeout — accordserver implements no ring timer of its own). An **explicitly
  /// declined** call is deliberately *not* recorded: the user already saw and
  /// answered the prompt, so re-surfacing it as an unread badge would be noise.
  ///
  /// **Session-only.** The entries live in memory and are gone after a restart:
  /// the record is an attention cue rather than a call log, and Accord has no
  /// call-history API to reconcile against.
  ///
  /// Keyed by channel id alone; ids are per-server snowflakes, so two servers
  /// minting the same DM channel id could (unlikely) collide.
  MissedCallsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'missedCallsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$missedCallsControllerHash();

  @$internal
  @override
  MissedCallsController create() => MissedCallsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, MissedCall> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, MissedCall>>(value),
    );
  }
}

String _$missedCallsControllerHash() =>
    r'b7f121c6d62b7b7e2c66e864d77d0b0d7c78b688';

/// Unanswered incoming DM calls, keyed by channel id.
///
/// Recorded by [CallController] when a ring ends without a local accept
/// (`call.cancel`/`call.end` while still ringing, or our client-side ring
/// timeout — accordserver implements no ring timer of its own). An **explicitly
/// declined** call is deliberately *not* recorded: the user already saw and
/// answered the prompt, so re-surfacing it as an unread badge would be noise.
///
/// **Session-only.** The entries live in memory and are gone after a restart:
/// the record is an attention cue rather than a call log, and Accord has no
/// call-history API to reconcile against.
///
/// Keyed by channel id alone; ids are per-server snowflakes, so two servers
/// minting the same DM channel id could (unlikely) collide.

abstract class _$MissedCallsController
    extends $Notifier<Map<String, MissedCall>> {
  Map<String, MissedCall> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<Map<String, MissedCall>, Map<String, MissedCall>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, MissedCall>, Map<String, MissedCall>>,
              Map<String, MissedCall>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
