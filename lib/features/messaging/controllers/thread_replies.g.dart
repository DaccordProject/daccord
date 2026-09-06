// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_replies.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A thread's replies (excluding the root message), keyed by
/// (channelId, rootId), ordered oldest→newest as the server returns them.
/// Self-loads via `messages.listThread` the first time it's watched (once
/// logged in) and is kept in sync by thread-scoped message
/// create/update/delete gateway events. `null` means "not loaded yet".

@ProviderFor(ThreadRepliesController)
const threadRepliesControllerProvider = ThreadRepliesControllerFamily._();

/// A thread's replies (excluding the root message), keyed by
/// (channelId, rootId), ordered oldest→newest as the server returns them.
/// Self-loads via `messages.listThread` the first time it's watched (once
/// logged in) and is kept in sync by thread-scoped message
/// create/update/delete gateway events. `null` means "not loaded yet".
final class ThreadRepliesControllerProvider
    extends $NotifierProvider<ThreadRepliesController, List<AccordMessage>?> {
  /// A thread's replies (excluding the root message), keyed by
  /// (channelId, rootId), ordered oldest→newest as the server returns them.
  /// Self-loads via `messages.listThread` the first time it's watched (once
  /// logged in) and is kept in sync by thread-scoped message
  /// create/update/delete gateway events. `null` means "not loaded yet".
  const ThreadRepliesControllerProvider._({
    required ThreadRepliesControllerFamily super.from,
    required (String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'threadRepliesControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$threadRepliesControllerHash();

  @override
  String toString() {
    return r'threadRepliesControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ThreadRepliesController create() => ThreadRepliesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordMessage>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordMessage>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThreadRepliesControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$threadRepliesControllerHash() =>
    r'93c50331c274f54e798a18975c210aac27e17423';

/// A thread's replies (excluding the root message), keyed by
/// (channelId, rootId), ordered oldest→newest as the server returns them.
/// Self-loads via `messages.listThread` the first time it's watched (once
/// logged in) and is kept in sync by thread-scoped message
/// create/update/delete gateway events. `null` means "not loaded yet".

final class ThreadRepliesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ThreadRepliesController,
          List<AccordMessage>?,
          List<AccordMessage>?,
          List<AccordMessage>?,
          (String, String, String)
        > {
  const ThreadRepliesControllerFamily._()
    : super(
        retry: null,
        name: r'threadRepliesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A thread's replies (excluding the root message), keyed by
  /// (channelId, rootId), ordered oldest→newest as the server returns them.
  /// Self-loads via `messages.listThread` the first time it's watched (once
  /// logged in) and is kept in sync by thread-scoped message
  /// create/update/delete gateway events. `null` means "not loaded yet".

  ThreadRepliesControllerProvider call(
    String serverKey,
    String channelId,
    String rootId,
  ) => ThreadRepliesControllerProvider._(
    argument: (serverKey, channelId, rootId),
    from: this,
  );

  @override
  String toString() => r'threadRepliesControllerProvider';
}

/// A thread's replies (excluding the root message), keyed by
/// (channelId, rootId), ordered oldest→newest as the server returns them.
/// Self-loads via `messages.listThread` the first time it's watched (once
/// logged in) and is kept in sync by thread-scoped message
/// create/update/delete gateway events. `null` means "not loaded yet".

abstract class _$ThreadRepliesController
    extends $Notifier<List<AccordMessage>?> {
  late final _$args = ref.$arg as (String, String, String);
  String get serverKey => _$args.$1;
  String get channelId => _$args.$2;
  String get rootId => _$args.$3;

  List<AccordMessage>? build(String serverKey, String channelId, String rootId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args.$1, _$args.$2, _$args.$3);
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
