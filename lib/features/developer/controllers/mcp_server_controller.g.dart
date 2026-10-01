// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_server_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags: it runs only while Developer Mode **and** the
/// MCP toggle are on, and restarts when the port changes. The bearer token and
/// allowed tool groups are read live, so changing them needs no restart.
///
/// [isDeveloperModeAvailable] gates it explicitly because [McpServer] resolves
/// to the real `dart:io` listener on iOS and Android too, where a persisted
/// `developerMode` flag must not start one.

@ProviderFor(McpServerController)
final mcpServerControllerProvider = McpServerControllerProvider._();

/// Owns the local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags: it runs only while Developer Mode **and** the
/// MCP toggle are on, and restarts when the port changes. The bearer token and
/// allowed tool groups are read live, so changing them needs no restart.
///
/// [isDeveloperModeAvailable] gates it explicitly because [McpServer] resolves
/// to the real `dart:io` listener on iOS and Android too, where a persisted
/// `developerMode` flag must not start one.
final class McpServerControllerProvider
    extends $NotifierProvider<McpServerController, McpServerState> {
  /// Owns the local MCP server lifecycle, driven by the persisted
  /// [SettingsController] flags: it runs only while Developer Mode **and** the
  /// MCP toggle are on, and restarts when the port changes. The bearer token and
  /// allowed tool groups are read live, so changing them needs no restart.
  ///
  /// [isDeveloperModeAvailable] gates it explicitly because [McpServer] resolves
  /// to the real `dart:io` listener on iOS and Android too, where a persisted
  /// `developerMode` flag must not start one.
  McpServerControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpServerControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpServerControllerHash();

  @$internal
  @override
  McpServerController create() => McpServerController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(McpServerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<McpServerState>(value),
    );
  }
}

String _$mcpServerControllerHash() =>
    r'f33c3565108bfb1481a3f18153c5cad3564ab225';

/// Owns the local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags: it runs only while Developer Mode **and** the
/// MCP toggle are on, and restarts when the port changes. The bearer token and
/// allowed tool groups are read live, so changing them needs no restart.
///
/// [isDeveloperModeAvailable] gates it explicitly because [McpServer] resolves
/// to the real `dart:io` listener on iOS and Android too, where a persisted
/// `developerMode` flag must not start one.

abstract class _$McpServerController extends $Notifier<McpServerState> {
  McpServerState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<McpServerState, McpServerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<McpServerState, McpServerState>,
              McpServerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
