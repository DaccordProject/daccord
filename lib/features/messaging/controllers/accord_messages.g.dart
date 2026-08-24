// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_messages.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A channel's recent message history, keyed by channel ID, ordered
/// oldest→newest for display. Self-loads via `messages.list` the first time
/// it's watched (once logged in) and is kept in sync by message
/// create/update/delete gateway events. `null` means "not loaded yet".

@ProviderFor(AccordMessagesController)
const accordMessagesControllerProvider = AccordMessagesControllerFamily._();

/// A channel's recent message history, keyed by channel ID, ordered
/// oldest→newest for display. Self-loads via `messages.list` the first time
/// it's watched (once logged in) and is kept in sync by message
/// create/update/delete gateway events. `null` means "not loaded yet".
final class AccordMessagesControllerProvider
    extends $NotifierProvider<AccordMessagesController, List<AccordMessage>?> {
  /// A channel's recent message history, keyed by channel ID, ordered
  /// oldest→newest for display. Self-loads via `messages.list` the first time
  /// it's watched (once logged in) and is kept in sync by message
  /// create/update/delete gateway events. `null` means "not loaded yet".
  const AccordMessagesControllerProvider._({
    required AccordMessagesControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'accordMessagesControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accordMessagesControllerHash();

  @override
  String toString() {
    return r'accordMessagesControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AccordMessagesController create() => AccordMessagesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordMessage>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordMessage>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AccordMessagesControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accordMessagesControllerHash() =>
    r'60a173190f02487fbf0f601ea0f2ee5435aa4a45';

/// A channel's recent message history, keyed by channel ID, ordered
/// oldest→newest for display. Self-loads via `messages.list` the first time
/// it's watched (once logged in) and is kept in sync by message
/// create/update/delete gateway events. `null` means "not loaded yet".

final class AccordMessagesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AccordMessagesController,
          List<AccordMessage>?,
          List<AccordMessage>?,
          List<AccordMessage>?,
          (String, String)
        > {
  const AccordMessagesControllerFamily._()
    : super(
        retry: null,
        name: r'accordMessagesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A channel's recent message history, keyed by channel ID, ordered
  /// oldest→newest for display. Self-loads via `messages.list` the first time
  /// it's watched (once logged in) and is kept in sync by message
  /// create/update/delete gateway events. `null` means "not loaded yet".

  AccordMessagesControllerProvider call(String serverKey, String channelId) =>
      AccordMessagesControllerProvider._(
        argument: (serverKey, channelId),
        from: this,
      );

  @override
  String toString() => r'accordMessagesControllerProvider';
}

/// A channel's recent message history, keyed by channel ID, ordered
/// oldest→newest for display. Self-loads via `messages.list` the first time
/// it's watched (once logged in) and is kept in sync by message
/// create/update/delete gateway events. `null` means "not loaded yet".

abstract class _$AccordMessagesController
    extends $Notifier<List<AccordMessage>?> {
  late final _$args = ref.$arg as (String, String);
  String get serverKey => _$args.$1;
  String get channelId => _$args.$2;

  List<AccordMessage>? build(String serverKey, String channelId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args.$1, _$args.$2);
    final ref = this.ref as $Ref<List<AccordMessage>?, List<AccordMessage>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AccordMessage>?, List<AccordMessage>?>,
              List<AccordMessage>?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
