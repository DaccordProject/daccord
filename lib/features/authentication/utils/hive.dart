import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';
import 'package:universal_platform/universal_platform.dart';

Future<void> setupHive() async {
  String? rootPath;
  if (!UniversalPlatform.isWeb) {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory('${appDocumentDir.path}/daccord/data');
    if (!dataDir.existsSync()) {
      dataDir.createSync(recursive: true);
    }
    Hive.init(dataDir.path);
    rootPath = dataDir.path;
  }
  await Hive.openBox("auth");
  await Hive.openBox("last-location");
  await Hive.openBox("last-guild-channels");
  await Hive.openBox("added-accounts");
  // Device-global desktop window geometry (size/position/maximized), restored
  // before the first frame by `setupDesktopWindow`.
  await Hive.openBox("window-state");
  // The active local device profile owns the `accord-session` (persisted
  // server + token + user for session restore) and `accord-settings` (client
  // preferences) boxes — bootstrap opens them from the active profile's
  // storage (the default profile uses the root dir, preserving existing data).
  await ProfileStore.bootstrap(rootPath);
}
