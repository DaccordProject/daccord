import 'dart:io';

import 'package:bonfire/features/developer/controllers/mcp_server_controller.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
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
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
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
