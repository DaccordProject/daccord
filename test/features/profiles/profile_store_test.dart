import 'dart:io';

import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('profile-store-test-');
    Hive.init(root.path);
    await ProfileStore.bootstrap(root.path);
  });

  tearDown(() async {
    await Hive.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('switching keeps native session and settings data isolated', () async {
    await Hive.box(ProfileStore.sessionBoxName).put('session', 'default');
    await Hive.box(ProfileStore.settingsBoxName).put('theme', 'dark');
    final workId = ProfileStore.create('Work');

    await ProfileStore.switchTo(workId);

    expect(ProfileStore.activeId, workId);
    expect(Hive.box(ProfileStore.sessionBoxName).get('session'), isNull);
    expect(Hive.box(ProfileStore.settingsBoxName).get('theme'), isNull);
    await Hive.box(ProfileStore.sessionBoxName).put('session', 'work');
    await Hive.box(ProfileStore.settingsBoxName).put('theme', 'light');

    await ProfileStore.switchTo(DeviceProfile.defaultId);

    expect(Hive.box(ProfileStore.sessionBoxName).get('session'), 'default');
    expect(Hive.box(ProfileStore.settingsBoxName).get('theme'), 'dark');

    await ProfileStore.switchTo(workId);

    expect(Hive.box(ProfileStore.sessionBoxName).get('session'), 'work');
    expect(Hive.box(ProfileStore.settingsBoxName).get('theme'), 'light');
  });

  test('deletion removes only the selected native profile directory', () async {
    final sharedSentinel = File(p.join(root.path, 'shared.keep'))
      ..writeAsStringSync('shared');
    final firstId = ProfileStore.create('First');
    final secondId = ProfileStore.create('Second');

    await ProfileStore.switchTo(firstId);
    await Hive.box(ProfileStore.sessionBoxName).put('owner', firstId);
    await ProfileStore.switchTo(secondId);
    await Hive.box(ProfileStore.sessionBoxName).put('owner', secondId);
    await ProfileStore.switchTo(DeviceProfile.defaultId);

    final firstDir = Directory(p.join(root.path, 'profiles', firstId));
    final secondDir = Directory(p.join(root.path, 'profiles', secondId));
    expect(firstDir.existsSync(), isTrue);
    expect(secondDir.existsSync(), isTrue);

    expect(await ProfileStore.delete(firstId), isTrue);

    expect(firstDir.existsSync(), isFalse);
    expect(secondDir.existsSync(), isTrue);
    expect(sharedSentinel.readAsStringSync(), 'shared');
    expect(root.existsSync(), isTrue);
    expect(
      ProfileStore.profiles.map((profile) => profile.id),
      contains(secondId),
    );
  });

  test('the default profile and shared root cannot be deleted', () async {
    final sentinel = File(p.join(root.path, 'default.keep'))
      ..writeAsStringSync('default');

    expect(await ProfileStore.delete(DeviceProfile.defaultId), isFalse);

    expect(root.existsSync(), isTrue);
    expect(sentinel.readAsStringSync(), 'default');
    expect(
      ProfileStore.profiles.map((profile) => profile.id),
      contains(DeviceProfile.defaultId),
    );
  });

  test('a failed switch restores the previous profile and its boxes', () async {
    await Hive.box(ProfileStore.sessionBoxName).put('session', 'default');
    await Hive.box(ProfileStore.settingsBoxName).put('theme', 'dark');
    final brokenId = ProfileStore.create('Broken');
    Directory(p.join(root.path, 'profiles')).createSync(recursive: true);
    File(
      p.join(root.path, 'profiles', brokenId),
    ).writeAsStringSync('not a dir');

    await expectLater(
      ProfileStore.switchTo(brokenId),
      throwsA(isA<FileSystemException>()),
    );

    expect(ProfileStore.activeId, DeviceProfile.defaultId);
    expect(Hive.isBoxOpen(ProfileStore.sessionBoxName), isTrue);
    expect(Hive.isBoxOpen(ProfileStore.settingsBoxName), isTrue);
    expect(Hive.box(ProfileStore.sessionBoxName).get('session'), 'default');
    expect(Hive.box(ProfileStore.settingsBoxName).get('theme'), 'dark');
  });
}
