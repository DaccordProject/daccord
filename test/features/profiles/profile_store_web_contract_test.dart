import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:universal_io/io.dart';
import 'package:universal_platform/universal_platform.dart';

void main() {
  Directory? root;
  String? isolatedSessionBoxName;
  String? isolatedSettingsBoxName;

  setUp(() async {
    if (UniversalPlatform.isWeb) {
      await Hive.deleteBoxFromDisk(ProfileStore.registryBoxName);
      await Hive.deleteBoxFromDisk(ProfileStore.sessionBoxName);
      await Hive.deleteBoxFromDisk(ProfileStore.settingsBoxName);
    } else {
      root = Directory.systemTemp.createTempSync('profile-store-web-test-');
      Hive.init(root!.path);
    }
    await ProfileStore.bootstrap(null, webForTesting: true);
  });

  tearDown(() async {
    await Hive.close();
    for (final boxName in {
      isolatedSessionBoxName,
      isolatedSettingsBoxName,
      ProfileStore.registryBoxName,
      ProfileStore.sessionBoxName,
      ProfileStore.settingsBoxName,
    }) {
      if (boxName != null) await Hive.deleteBoxFromDisk(boxName);
    }
    final temp = root;
    if (temp != null && temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('Web profiles use isolated Hive box namespaces', () async {
    expect(ProfileStore.activeSessionBoxName, ProfileStore.sessionBoxName);
    expect(ProfileStore.activeSettingsBoxName, ProfileStore.settingsBoxName);
    await ProfileStore.sessionBox.put('session', 'default');
    await ProfileStore.settingsBox.put('theme', 'dark');
    final workId = ProfileStore.create('Work');

    await ProfileStore.switchTo(workId);

    final workSessionBoxName = isolatedSessionBoxName =
        ProfileStore.activeSessionBoxName;
    final workSettingsBoxName = isolatedSettingsBoxName =
        ProfileStore.activeSettingsBoxName;
    expect(workSessionBoxName, isNot(ProfileStore.sessionBoxName));
    expect(workSettingsBoxName, isNot(ProfileStore.settingsBoxName));
    expect(Hive.isBoxOpen(ProfileStore.sessionBoxName), isFalse);
    expect(Hive.isBoxOpen(ProfileStore.settingsBoxName), isFalse);
    expect(ProfileStore.sessionBox.get('session'), isNull);
    expect(ProfileStore.settingsBox.get('theme'), isNull);
    await ProfileStore.sessionBox.put('session', 'work');
    await ProfileStore.settingsBox.put('theme', 'light');

    await ProfileStore.switchTo(DeviceProfile.defaultId);

    expect(ProfileStore.activeSessionBoxName, ProfileStore.sessionBoxName);
    expect(ProfileStore.activeSettingsBoxName, ProfileStore.settingsBoxName);
    expect(ProfileStore.sessionBox.get('session'), 'default');
    expect(ProfileStore.settingsBox.get('theme'), 'dark');

    await ProfileStore.switchTo(workId);

    expect(ProfileStore.activeSessionBoxName, workSessionBoxName);
    expect(ProfileStore.activeSettingsBoxName, workSettingsBoxName);
    expect(ProfileStore.sessionBox.get('session'), 'work');
    expect(ProfileStore.settingsBox.get('theme'), 'light');
  });
}
