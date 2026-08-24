// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'forum_posts.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A forum channel's top-level posts (thread roots), keyed by channel ID, in
/// server order (the board sorts for display). Self-loads via
/// `messages.listPosts` the first time it's watched (once logged in) and is
/// kept in sync by top-level message create/update/delete gateway events.
/// `null` means "not loaded yet".

@ProviderFor(ForumPostsController)
const forumPostsControllerProvider = ForumPostsControllerFamily._();

/// A forum channel's top-level posts (thread roots), keyed by channel ID, in
/// server order (the board sorts for display). Self-loads via
/// `messages.listPosts` the first time it's watched (once logged in) and is
/// kept in sync by top-level message create/update/delete gateway events.
/// `null` means "not loaded yet".
final class ForumPostsControllerProvider
    extends $NotifierProvider<ForumPostsController, List<AccordMessage>?> {
  /// A forum channel's top-level posts (thread roots), keyed by channel ID, in
  /// server order (the board sorts for display). Self-loads via
  /// `messages.listPosts` the first time it's watched (once logged in) and is
  /// kept in sync by top-level message create/update/delete gateway events.
  /// `null` means "not loaded yet".
  const ForumPostsControllerProvider._({
    required ForumPostsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'forumPostsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$forumPostsControllerHash();

  @override
  String toString() {
    return r'forumPostsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ForumPostsController create() => ForumPostsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordMessage>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordMessage>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ForumPostsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$forumPostsControllerHash() =>
    r'5781e9618e9101b3e86f66ee3dc3a3d262eef4c4';

/// A forum channel's top-level posts (thread roots), keyed by channel ID, in
/// server order (the board sorts for display). Self-loads via
/// `messages.listPosts` the first time it's watched (once logged in) and is
/// kept in sync by top-level message create/update/delete gateway events.
/// `null` means "not loaded yet".

final class ForumPostsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ForumPostsController,
          List<AccordMessage>?,
          List<AccordMessage>?,
          List<AccordMessage>?,
          String
        > {
  const ForumPostsControllerFamily._()
    : super(
        retry: null,
        name: r'forumPostsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A forum channel's top-level posts (thread roots), keyed by channel ID, in
  /// server order (the board sorts for display). Self-loads via
  /// `messages.listPosts` the first time it's watched (once logged in) and is
  /// kept in sync by top-level message create/update/delete gateway events.
  /// `null` means "not loaded yet".

  ForumPostsControllerProvider call(String channelId) =>
      ForumPostsControllerProvider._(argument: channelId, from: this);

  @override
  String toString() => r'forumPostsControllerProvider';
}

/// A forum channel's top-level posts (thread roots), keyed by channel ID, in
/// server order (the board sorts for display). Self-loads via
/// `messages.listPosts` the first time it's watched (once logged in) and is
/// kept in sync by top-level message create/update/delete gateway events.
/// `null` means "not loaded yet".

abstract class _$ForumPostsController extends $Notifier<List<AccordMessage>?> {
  late final _$args = ref.$arg as String;
  String get channelId => _$args;

  List<AccordMessage>? build(String channelId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
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
