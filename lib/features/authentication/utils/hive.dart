import 'package:bonfire/features/messaging/utils/pending_upload_store.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/server/utils/space_cache.dart';
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
  // Last-known space list per server, so the rail can render a server's spaces
  // (dimmed, while unreachable) before/without a successful gateway connect.
  await Hive.openBox(SpaceCache.boxName);
  // Device-global desktop window geometry (size/position/maximized), restored
  // before the first frame by `setupDesktopWindow`.
  await Hive.openBox("window-state");
  // Per-connection AutoMod-held upload IDs, so a "processing" placeholder
  // survives a restart and READY can ask the server how each one ended.
  await Hive.openBox(PendingUploadStore.boxName);
  // Opens the active device profile's `accord-session` and `accord-settings`
  // boxes (the default profile uses the root dir).
  await ProfileStore.bootstrap(rootPath);
}
