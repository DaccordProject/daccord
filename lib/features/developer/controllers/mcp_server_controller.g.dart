// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_server_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the desktop-only local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags. The server runs only while Developer Mode **and**
/// the MCP toggle are both on (mirroring the reference client's two-step
/// opt-in); it restarts when the port changes. The bearer token and allowed
/// tool groups are read live by the server, so changing those takes effect
/// without a restart.
///
/// On web (no `dart:io`) the [McpServer] facade is a no-op, so this controller
/// is inert there.

@ProviderFor(McpServerController)
const mcpServerControllerProvider = McpServerControllerProvider._();

/// Owns the desktop-only local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags. The server runs only while Developer Mode **and**
/// the MCP toggle are both on (mirroring the reference client's two-step
/// opt-in); it restarts when the port changes. The bearer token and allowed
/// tool groups are read live by the server, so changing those takes effect
/// without a restart.
///
/// On web (no `dart:io`) the [McpServer] facade is a no-op, so this controller
/// is inert there.
final class McpServerControllerProvider
    extends $NotifierProvider<McpServerController, McpServerState> {
  /// Owns the desktop-only local MCP server lifecycle, driven by the persisted
  /// [SettingsController] flags. The server runs only while Developer Mode **and**
  /// the MCP toggle are both on (mirroring the reference client's two-step
  /// opt-in); it restarts when the port changes. The bearer token and allowed
  /// tool groups are read live by the server, so changing those takes effect
  /// without a restart.
  ///
  /// On web (no `dart:io`) the [McpServer] facade is a no-op, so this controller
  /// is inert there.
  const McpServerControllerProvider._()
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
    r'2bac7b0fd691164df5c45b7e54851ace3158b054';

/// Owns the desktop-only local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags. The server runs only while Developer Mode **and**
/// the MCP toggle are both on (mirroring the reference client's two-step
/// opt-in); it restarts when the port changes. The bearer token and allowed
/// tool groups are read live by the server, so changing those takes effect
/// without a restart.
///
/// On web (no `dart:io`) the [McpServer] facade is a no-op, so this controller
/// is inert there.

abstract class _$McpServerController extends $Notifier<McpServerState> {
  McpServerState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<McpServerState, McpServerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<McpServerState, McpServerState>,
              McpServerState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
