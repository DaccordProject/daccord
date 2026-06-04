// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_messages.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A channel's recent message history, keyed by channel ID.

@ProviderFor(AccordMessagesController)
const accordMessagesControllerProvider = AccordMessagesControllerFamily._();

/// A channel's recent message history, keyed by channel ID.
final class AccordMessagesControllerProvider
    extends $NotifierProvider<AccordMessagesController, List<AccordMessage>?> {
  /// A channel's recent message history, keyed by channel ID.
  const AccordMessagesControllerProvider._({
    required AccordMessagesControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'accordMessagesControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accordMessagesControllerHash();

  @override
  String toString() {
    return r'accordMessagesControllerProvider'
        ''
        '($argument)';
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
    r'00000000000000000000000000000accordmessages';

/// A channel's recent message history, keyed by channel ID.

final class AccordMessagesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AccordMessagesController,
          List<AccordMessage>?,
          List<AccordMessage>?,
          List<AccordMessage>?,
          String
        > {
  const AccordMessagesControllerFamily._()
    : super(
        retry: null,
        name: r'accordMessagesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// A channel's recent message history, keyed by channel ID.

  AccordMessagesControllerProvider call(String channelId) =>
      AccordMessagesControllerProvider._(argument: channelId, from: this);

  @override
  String toString() => r'accordMessagesControllerProvider';
}

/// A channel's recent message history, keyed by channel ID.

abstract class _$AccordMessagesController
    extends $Notifier<List<AccordMessage>?> {
  late final _$args = ref.$arg as String;
  String get channelId => _$args;

  List<AccordMessage>? build(String channelId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref =
        this.ref as $Ref<List<AccordMessage>?, List<AccordMessage>?>;
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
