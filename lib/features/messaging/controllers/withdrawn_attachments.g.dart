// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'withdrawn_attachments.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Attachments the server has withdrawn from messages on one connection —
/// an AutoMod rejection/removal after publication, or any `message.update`
/// that shrank an attachment list. Keyed by [attachmentKey] (ID, else URL).
///
/// Two consumers: open viewers (the image lightbox) watch it and close when
/// the attachment they're showing disappears, and [withdraw] evicts the
/// withdrawn URLs from the image cache so a rebuild can't repaint them from
/// disk. Bounded — the last [maxRemembered] withdrawals.

@ProviderFor(WithdrawnAttachmentsController)
const withdrawnAttachmentsControllerProvider =
    WithdrawnAttachmentsControllerFamily._();

/// Attachments the server has withdrawn from messages on one connection —
/// an AutoMod rejection/removal after publication, or any `message.update`
/// that shrank an attachment list. Keyed by [attachmentKey] (ID, else URL).
///
/// Two consumers: open viewers (the image lightbox) watch it and close when
/// the attachment they're showing disappears, and [withdraw] evicts the
/// withdrawn URLs from the image cache so a rebuild can't repaint them from
/// disk. Bounded — the last [maxRemembered] withdrawals.
final class WithdrawnAttachmentsControllerProvider
    extends $NotifierProvider<WithdrawnAttachmentsController, Set<String>> {
  /// Attachments the server has withdrawn from messages on one connection —
  /// an AutoMod rejection/removal after publication, or any `message.update`
  /// that shrank an attachment list. Keyed by [attachmentKey] (ID, else URL).
  ///
  /// Two consumers: open viewers (the image lightbox) watch it and close when
  /// the attachment they're showing disappears, and [withdraw] evicts the
  /// withdrawn URLs from the image cache so a rebuild can't repaint them from
  /// disk. Bounded — the last [maxRemembered] withdrawals.
  const WithdrawnAttachmentsControllerProvider._({
    required WithdrawnAttachmentsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'withdrawnAttachmentsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$withdrawnAttachmentsControllerHash();

  @override
  String toString() {
    return r'withdrawnAttachmentsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WithdrawnAttachmentsController create() => WithdrawnAttachmentsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WithdrawnAttachmentsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$withdrawnAttachmentsControllerHash() =>
    r'79bf6ba7a2036c3e3e05228c2caa572f9205903e';

/// Attachments the server has withdrawn from messages on one connection —
/// an AutoMod rejection/removal after publication, or any `message.update`
/// that shrank an attachment list. Keyed by [attachmentKey] (ID, else URL).
///
/// Two consumers: open viewers (the image lightbox) watch it and close when
/// the attachment they're showing disappears, and [withdraw] evicts the
/// withdrawn URLs from the image cache so a rebuild can't repaint them from
/// disk. Bounded — the last [maxRemembered] withdrawals.

final class WithdrawnAttachmentsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          WithdrawnAttachmentsController,
          Set<String>,
          Set<String>,
          Set<String>,
          String
        > {
  const WithdrawnAttachmentsControllerFamily._()
    : super(
        retry: null,
        name: r'withdrawnAttachmentsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Attachments the server has withdrawn from messages on one connection —
  /// an AutoMod rejection/removal after publication, or any `message.update`
  /// that shrank an attachment list. Keyed by [attachmentKey] (ID, else URL).
  ///
  /// Two consumers: open viewers (the image lightbox) watch it and close when
  /// the attachment they're showing disappears, and [withdraw] evicts the
  /// withdrawn URLs from the image cache so a rebuild can't repaint them from
  /// disk. Bounded — the last [maxRemembered] withdrawals.

  WithdrawnAttachmentsControllerProvider call(String serverKey) =>
      WithdrawnAttachmentsControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'withdrawnAttachmentsControllerProvider';
}

/// Attachments the server has withdrawn from messages on one connection —
/// an AutoMod rejection/removal after publication, or any `message.update`
/// that shrank an attachment list. Keyed by [attachmentKey] (ID, else URL).
///
/// Two consumers: open viewers (the image lightbox) watch it and close when
/// the attachment they're showing disappears, and [withdraw] evicts the
/// withdrawn URLs from the image cache so a rebuild can't repaint them from
/// disk. Bounded — the last [maxRemembered] withdrawals.

abstract class _$WithdrawnAttachmentsController extends $Notifier<Set<String>> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  Set<String> build(String serverKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
