// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'muted_channels.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Server-backed channel mutes for one connected account.
///
/// Both the channel header and context menu use this cache so opening either
/// surface does not refetch the full mute list or leave the other one stale.

@ProviderFor(MutedChannelsController)
const mutedChannelsControllerProvider = MutedChannelsControllerFamily._();

/// Server-backed channel mutes for one connected account.
///
/// Both the channel header and context menu use this cache so opening either
/// surface does not refetch the full mute list or leave the other one stale.
final class MutedChannelsControllerProvider
    extends $AsyncNotifierProvider<MutedChannelsController, Set<String>> {
  /// Server-backed channel mutes for one connected account.
  ///
  /// Both the channel header and context menu use this cache so opening either
  /// surface does not refetch the full mute list or leave the other one stale.
  const MutedChannelsControllerProvider._({
    required MutedChannelsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mutedChannelsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mutedChannelsControllerHash();

  @override
  String toString() {
    return r'mutedChannelsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MutedChannelsController create() => MutedChannelsController();

  @override
  bool operator ==(Object other) {
    return other is MutedChannelsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mutedChannelsControllerHash() =>
    r'f6c660e096a20220f545602edd8c75bb86372470';

/// Server-backed channel mutes for one connected account.
///
/// Both the channel header and context menu use this cache so opening either
/// surface does not refetch the full mute list or leave the other one stale.

final class MutedChannelsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MutedChannelsController,
          AsyncValue<Set<String>>,
          Set<String>,
          FutureOr<Set<String>>,
          String
        > {
  const MutedChannelsControllerFamily._()
    : super(
        retry: null,
        name: r'mutedChannelsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Server-backed channel mutes for one connected account.
  ///
  /// Both the channel header and context menu use this cache so opening either
  /// surface does not refetch the full mute list or leave the other one stale.

  MutedChannelsControllerProvider call(String serverKey) =>
      MutedChannelsControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'mutedChannelsControllerProvider';
}

/// Server-backed channel mutes for one connected account.
///
/// Both the channel header and context menu use this cache so opening either
/// surface does not refetch the full mute list or leave the other one stale.

abstract class _$MutedChannelsController extends $AsyncNotifier<Set<String>> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  FutureOr<Set<String>> build(String serverKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<AsyncValue<Set<String>>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Set<String>>, Set<String>>,
              AsyncValue<Set<String>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
