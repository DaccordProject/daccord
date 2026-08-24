// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_emojis.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A space's custom emoji, keyed by space ID. Self-loads via `emojis.list` the
/// first time it's watched (once logged in). `null` means "not loaded yet";
/// an empty list means the space has no custom emoji.

@ProviderFor(AccordEmojisController)
const accordEmojisControllerProvider = AccordEmojisControllerFamily._();

/// A space's custom emoji, keyed by space ID. Self-loads via `emojis.list` the
/// first time it's watched (once logged in). `null` means "not loaded yet";
/// an empty list means the space has no custom emoji.
final class AccordEmojisControllerProvider
    extends $NotifierProvider<AccordEmojisController, List<AccordEmoji>?> {
  /// A space's custom emoji, keyed by space ID. Self-loads via `emojis.list` the
  /// first time it's watched (once logged in). `null` means "not loaded yet";
  /// an empty list means the space has no custom emoji.
  const AccordEmojisControllerProvider._({
    required AccordEmojisControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'accordEmojisControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accordEmojisControllerHash();

  @override
  String toString() {
    return r'accordEmojisControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AccordEmojisController create() => AccordEmojisController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordEmoji>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordEmoji>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AccordEmojisControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accordEmojisControllerHash() =>
    r'3f85d1a5b5c12933f465d56448d4ed94a36ec98a';

/// A space's custom emoji, keyed by space ID. Self-loads via `emojis.list` the
/// first time it's watched (once logged in). `null` means "not loaded yet";
/// an empty list means the space has no custom emoji.

final class AccordEmojisControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AccordEmojisController,
          List<AccordEmoji>?,
          List<AccordEmoji>?,
          List<AccordEmoji>?,
          (String, String)
        > {
  const AccordEmojisControllerFamily._()
    : super(
        retry: null,
        name: r'accordEmojisControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// A space's custom emoji, keyed by space ID. Self-loads via `emojis.list` the
  /// first time it's watched (once logged in). `null` means "not loaded yet";
  /// an empty list means the space has no custom emoji.

  AccordEmojisControllerProvider call(String serverKey, String spaceId) =>
      AccordEmojisControllerProvider._(
        argument: (serverKey, spaceId),
        from: this,
      );

  @override
  String toString() => r'accordEmojisControllerProvider';
}

/// A space's custom emoji, keyed by space ID. Self-loads via `emojis.list` the
/// first time it's watched (once logged in). `null` means "not loaded yet";
/// an empty list means the space has no custom emoji.

abstract class _$AccordEmojisController extends $Notifier<List<AccordEmoji>?> {
  late final _$args = ref.$arg as (String, String);
  String get serverKey => _$args.$1;
  String get spaceId => _$args.$2;

  List<AccordEmoji>? build(String serverKey, String spaceId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args.$1, _$args.$2);
    final ref = this.ref as $Ref<List<AccordEmoji>?, List<AccordEmoji>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AccordEmoji>?, List<AccordEmoji>?>,
              List<AccordEmoji>?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
