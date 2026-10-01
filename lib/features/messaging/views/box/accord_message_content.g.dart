// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_message_content.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Keep syntax identity stable so MarkdownViewer retains its parse on rebuild.
/// Only mention-bearing content loads the member roster; fetching it backfills
/// each member even when the sidebar is collapsed.

@ProviderFor(_spaceMarkupSyntaxes)
final _spaceMarkupSyntaxesProvider = _SpaceMarkupSyntaxesFamily._();

/// Keep syntax identity stable so MarkdownViewer retains its parse on rebuild.
/// Only mention-bearing content loads the member roster; fetching it backfills
/// each member even when the sidebar is collapsed.

final class _SpaceMarkupSyntaxesProvider
    extends
        $FunctionalProvider<List<md.Syntax>, List<md.Syntax>, List<md.Syntax>>
    with $Provider<List<md.Syntax>> {
  /// Keep syntax identity stable so MarkdownViewer retains its parse on rebuild.
  /// Only mention-bearing content loads the member roster; fetching it backfills
  /// each member even when the sidebar is collapsed.
  _SpaceMarkupSyntaxesProvider._({
    required _SpaceMarkupSyntaxesFamily super.from,
    required (String, String, String?, {bool withMembers}) super.argument,
  }) : super(
         retry: null,
         name: r'_spaceMarkupSyntaxesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$_spaceMarkupSyntaxesHash();

  @override
  String toString() {
    return r'_spaceMarkupSyntaxesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<List<md.Syntax>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<md.Syntax> create(Ref ref) {
    final argument =
        this.argument as (String, String, String?, {bool withMembers});
    return _spaceMarkupSyntaxes(
      ref,
      argument.$1,
      argument.$2,
      argument.$3,
      withMembers: argument.withMembers,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<md.Syntax> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<md.Syntax>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _SpaceMarkupSyntaxesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$_spaceMarkupSyntaxesHash() =>
    r'71f1929de284a6ddfd2b4788304575d1dc99db49';

/// Keep syntax identity stable so MarkdownViewer retains its parse on rebuild.
/// Only mention-bearing content loads the member roster; fetching it backfills
/// each member even when the sidebar is collapsed.

final class _SpaceMarkupSyntaxesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          List<md.Syntax>,
          (String, String, String?, {bool withMembers})
        > {
  _SpaceMarkupSyntaxesFamily._()
    : super(
        retry: null,
        name: r'_spaceMarkupSyntaxesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Keep syntax identity stable so MarkdownViewer retains its parse on rebuild.
  /// Only mention-bearing content loads the member roster; fetching it backfills
  /// each member even when the sidebar is collapsed.

  _SpaceMarkupSyntaxesProvider call(
    String serverKey,
    String spaceId,
    String? cdnUrl, {
    required bool withMembers,
  }) => _SpaceMarkupSyntaxesProvider._(
    argument: (serverKey, spaceId, cdnUrl, withMembers: withMembers),
    from: this,
  );

  @override
  String toString() => r'_spaceMarkupSyntaxesProvider';
}
