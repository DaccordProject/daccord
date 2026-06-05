// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'typing.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The set of users currently typing in a channel, keyed by channel ID. Each
/// user is held for [_typingTimeout] after their last event, then expires.
/// Returns user IDs in arrival order; the UI resolves them to names via the
/// member cache.

@ProviderFor(TypingController)
const typingControllerProvider = TypingControllerFamily._();

/// The set of users currently typing in a channel, keyed by channel ID. Each
/// user is held for [_typingTimeout] after their last event, then expires.
/// Returns user IDs in arrival order; the UI resolves them to names via the
/// member cache.
final class TypingControllerProvider
    extends $NotifierProvider<TypingController, List<String>> {
  /// The set of users currently typing in a channel, keyed by channel ID. Each
  /// user is held for [_typingTimeout] after their last event, then expires.
  /// Returns user IDs in arrival order; the UI resolves them to names via the
  /// member cache.
  const TypingControllerProvider._({
    required TypingControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'typingControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$typingControllerHash();

  @override
  String toString() {
    return r'typingControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TypingController create() => TypingController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TypingControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$typingControllerHash() => r'ccd08c145d3d64f7137f87cdaa31c11bc2ca3b38';

/// The set of users currently typing in a channel, keyed by channel ID. Each
/// user is held for [_typingTimeout] after their last event, then expires.
/// Returns user IDs in arrival order; the UI resolves them to names via the
/// member cache.

final class TypingControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          TypingController,
          List<String>,
          List<String>,
          List<String>,
          String
        > {
  const TypingControllerFamily._()
    : super(
        retry: null,
        name: r'typingControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The set of users currently typing in a channel, keyed by channel ID. Each
  /// user is held for [_typingTimeout] after their last event, then expires.
  /// Returns user IDs in arrival order; the UI resolves them to names via the
  /// member cache.

  TypingControllerProvider call(String channelId) =>
      TypingControllerProvider._(argument: channelId, from: this);

  @override
  String toString() => r'typingControllerProvider';
}

/// The set of users currently typing in a channel, keyed by channel ID. Each
/// user is held for [_typingTimeout] after their last event, then expires.
/// Returns user IDs in arrival order; the UI resolves them to names via the
/// member cache.

abstract class _$TypingController extends $Notifier<List<String>> {
  late final _$args = ref.$arg as String;
  String get channelId => _$args;

  List<String> build(String channelId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<List<String>, List<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<String>, List<String>>,
              List<String>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
