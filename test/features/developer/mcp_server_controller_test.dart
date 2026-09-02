import 'dart:io';

import 'package:bonfire/features/developer/controllers/mcp_server_controller.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mcp-controller-test');
    Hive.init(tempDir.path);
    await Hive.openBox('accord-settings');
  });

  tearDown(() async {
    debugDeveloperModeAvailable = null;
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Persists fully-enabled MCP settings on a free port and returns that port.
  Future<int> seedEnabledSettings() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    await Hive.box('accord-settings').put(
      'settings',
      AccordSettings(
        developerMode: true,
        mcpEnabled: true,
        mcpPort: port,
        mcpToken: 'test-token',
      ).toJson(),
    );
    return port;
  }

  test('starts when developer mode is available for this build', () async {
    // Positive control for the gate below: with the same settings and the
    // platform gate open, the server really does listen.
    debugDeveloperModeAvailable = true;
    await seedEnabledSettings();

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(mcpServerControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(mcpServerControllerProvider).listening, isTrue);
  });

  test('never starts where developer mode is unavailable', () async {
    // Mobile and app-store builds: `mcp_server.dart` still resolves to the real
    // dart:io server (dart.library.io is true on iOS/Android), so the gate has
    // to be enforced here or a persisted flag would open a listener inside the
    // store binary (#292).
    debugDeveloperModeAvailable = false;
    final port = await seedEnabledSettings();

    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(settingsControllerProvider).developerMode, isTrue);
    container.read(mcpServerControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(mcpServerControllerProvider).listening, isFalse);
    final canBind = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await canBind.close();
  });

  test(
    'does not start from persisted enabled flags with an empty token',
    () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      await Hive.box('accord-settings').put(
        'settings',
        AccordSettings(
          developerMode: true,
          mcpEnabled: true,
          mcpPort: port,
        ).toJson(),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(settingsControllerProvider).mcpToken, isEmpty);
      container.read(mcpServerControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(container.read(mcpServerControllerProvider).listening, isFalse);
      final canBind = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await canBind.close();
    },
  );
}
