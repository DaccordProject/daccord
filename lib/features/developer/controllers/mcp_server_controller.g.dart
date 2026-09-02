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
/// The desktop-only part is enforced here rather than assumed: [McpServer]
/// resolves to the real `dart:io` implementation on *any* platform with
/// `dart:library.io` — which includes iOS and Android — so without this gate a
/// persisted `developerMode` flag would start a real HTTP listener on a phone or
/// inside a store build. [isDeveloperModeAvailable] is the single source of
/// truth, shared with the settings UI that offers the toggle.
///
/// On web (no `dart:io`) the [McpServer] facade is a no-op, so this controller
/// is inert there too.

@ProviderFor(McpServerController)
const mcpServerControllerProvider = McpServerControllerProvider._();

/// Owns the desktop-only local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags. The server runs only while Developer Mode **and**
/// the MCP toggle are both on (mirroring the reference client's two-step
/// opt-in); it restarts when the port changes. The bearer token and allowed
/// tool groups are read live by the server, so changing those takes effect
/// without a restart.
///
/// The desktop-only part is enforced here rather than assumed: [McpServer]
/// resolves to the real `dart:io` implementation on *any* platform with
/// `dart:library.io` — which includes iOS and Android — so without this gate a
/// persisted `developerMode` flag would start a real HTTP listener on a phone or
/// inside a store build. [isDeveloperModeAvailable] is the single source of
/// truth, shared with the settings UI that offers the toggle.
///
/// On web (no `dart:io`) the [McpServer] facade is a no-op, so this controller
/// is inert there too.
final class McpServerControllerProvider
    extends $NotifierProvider<McpServerController, McpServerState> {
  /// Owns the desktop-only local MCP server lifecycle, driven by the persisted
  /// [SettingsController] flags. The server runs only while Developer Mode **and**
  /// the MCP toggle are both on (mirroring the reference client's two-step
  /// opt-in); it restarts when the port changes. The bearer token and allowed
  /// tool groups are read live by the server, so changing those takes effect
  /// without a restart.
  ///
  /// The desktop-only part is enforced here rather than assumed: [McpServer]
  /// resolves to the real `dart:io` implementation on *any* platform with
  /// `dart:library.io` — which includes iOS and Android — so without this gate a
  /// persisted `developerMode` flag would start a real HTTP listener on a phone or
  /// inside a store build. [isDeveloperModeAvailable] is the single source of
  /// truth, shared with the settings UI that offers the toggle.
  ///
  /// On web (no `dart:io`) the [McpServer] facade is a no-op, so this controller
  /// is inert there too.
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
    r'4729c9d96fe693efdf6b902c15ea5fdae1f1bc88';

/// Owns the desktop-only local MCP server lifecycle, driven by the persisted
/// [SettingsController] flags. The server runs only while Developer Mode **and**
/// the MCP toggle are both on (mirroring the reference client's two-step
/// opt-in); it restarts when the port changes. The bearer token and allowed
/// tool groups are read live by the server, so changing those takes effect
/// without a restart.
///
/// The desktop-only part is enforced here rather than assumed: [McpServer]
/// resolves to the real `dart:io` implementation on *any* platform with
/// `dart:library.io` — which includes iOS and Android — so without this gate a
/// persisted `developerMode` flag would start a real HTTP listener on a phone or
/// inside a store build. [isDeveloperModeAvailable] is the single source of
/// truth, shared with the settings UI that offers the toggle.
///
/// On web (no `dart:io`) the [McpServer] facade is a no-op, so this controller
/// is inert there too.

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
