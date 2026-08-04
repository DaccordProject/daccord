// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'taskbar_badge.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Mirrors [globalUnreadProvider] onto the OS taskbar/dock icon.
///
/// Deliberately a "service" with no state of its own: it exists so unread state
/// reaches the platform *live*, including while the window is minimised or
/// backgrounded, which is the whole point — a transient local notification is
/// otherwise the only signal that something arrived.
///
/// Kept alive by a `ref.watch` in `MainWindow`, matching
/// `BackgroundConnectionController` / the MCP server controller.

@ProviderFor(TaskbarBadgeController)
const taskbarBadgeControllerProvider = TaskbarBadgeControllerProvider._();

/// Mirrors [globalUnreadProvider] onto the OS taskbar/dock icon.
///
/// Deliberately a "service" with no state of its own: it exists so unread state
/// reaches the platform *live*, including while the window is minimised or
/// backgrounded, which is the whole point — a transient local notification is
/// otherwise the only signal that something arrived.
///
/// Kept alive by a `ref.watch` in `MainWindow`, matching
/// `BackgroundConnectionController` / the MCP server controller.
final class TaskbarBadgeControllerProvider
    extends $NotifierProvider<TaskbarBadgeController, void> {
  /// Mirrors [globalUnreadProvider] onto the OS taskbar/dock icon.
  ///
  /// Deliberately a "service" with no state of its own: it exists so unread state
  /// reaches the platform *live*, including while the window is minimised or
  /// backgrounded, which is the whole point — a transient local notification is
  /// otherwise the only signal that something arrived.
  ///
  /// Kept alive by a `ref.watch` in `MainWindow`, matching
  /// `BackgroundConnectionController` / the MCP server controller.
  const TaskbarBadgeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'taskbarBadgeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$taskbarBadgeControllerHash();

  @$internal
  @override
  TaskbarBadgeController create() => TaskbarBadgeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$taskbarBadgeControllerHash() =>
    r'6901e28292b6e7444a649e73f4886aba99efe4e5';

/// Mirrors [globalUnreadProvider] onto the OS taskbar/dock icon.
///
/// Deliberately a "service" with no state of its own: it exists so unread state
/// reaches the platform *live*, including while the window is minimised or
/// backgrounded, which is the whole point — a transient local notification is
/// otherwise the only signal that something arrived.
///
/// Kept alive by a `ref.watch` in `MainWindow`, matching
/// `BackgroundConnectionController` / the MCP server controller.

abstract class _$TaskbarBadgeController extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    build();
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleValue(ref, null);
  }
}
