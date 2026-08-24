import 'dart:convert';
import 'dart:math';

import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';
import 'package:universal_platform/universal_platform.dart';

/// Low-level storage for local device profiles: the global registry box and the
/// per-profile `accord-session` / `accord-settings` box (re)opening.
///
/// Isolation strategy: the **default** profile keeps the canonical box files at
/// the root data dir (so data created before profiles existed is preserved),
/// while every other native profile gets its own `profiles/<id>` directory.
/// On Web, where Hive ignores filesystem paths and stores IndexedDB data by box
/// name, non-default profiles use deterministic profile-specific box names.
/// The default profile keeps the canonical names on every platform so existing
/// pre-profile data remains available.
class ProfileStore {
  ProfileStore._();

  static const registryBoxName = 'profile-registry';
  static const _registryKey = 'registry';
  static const sessionBoxName = 'accord-session';
  static const settingsBoxName = 'accord-settings';

  /// Root Hive data dir (native only; null on web). Captured in [bootstrap].
  static String? _rootPath;
  static bool _useWebBoxNamespaces = UniversalPlatform.isWeb;

  static String get _storageProfileId =>
      Hive.isBoxOpen(registryBoxName) ? activeId : DeviceProfile.defaultId;

  /// The currently active session/settings box names.
  static String get activeSessionBoxName =>
      _boxNameForProfile(sessionBoxName, _storageProfileId);
  static String get activeSettingsBoxName =>
      _boxNameForProfile(settingsBoxName, _storageProfileId);

  static Box get sessionBox => Hive.box(activeSessionBoxName);
  static Box get settingsBox => Hive.box(activeSettingsBoxName);

  /// Opens the registry box, ensures a default profile exists, and opens the
  /// active profile's session/settings boxes. Defensive: any failure falls back
  /// to opening the canonical boxes at the root so the app always boots.
  static Future<void> bootstrap(
    String? rootPath, {
    @visibleForTesting bool? webForTesting,
  }) async {
    _useWebBoxNamespaces = webForTesting ?? UniversalPlatform.isWeb;
    _rootPath = _useWebBoxNamespaces ? null : rootPath;
    try {
      await Hive.openBox(registryBoxName);
      _ensureDefault();
      await _openProfileBoxes(activeId);
    } catch (e) {
      debugPrint('Profile bootstrap failed ($e); using default storage.');
      final failedId = Hive.isBoxOpen(registryBoxName)
          ? activeId
          : DeviceProfile.defaultId;
      await _closeProfileBoxes(failedId);
      if (Hive.isBoxOpen(registryBoxName)) {
        _ensureDefault();
        _putProfiles(profiles, activeId: DeviceProfile.defaultId);
      }
      await _openProfileBoxes(DeviceProfile.defaultId);
    }
  }

  static Box get _registry => Hive.box(registryBoxName);

  static Map<dynamic, dynamic> get _raw {
    final v = _registry.get(_registryKey);
    return v is Map ? v : const {};
  }

  static void _writeRaw(List<DeviceProfile> profiles, String activeId) {
    _registry.put(_registryKey, {
      'profiles': [for (final p in profiles) p.toJson()],
      'activeId': activeId,
    });
  }

  /// Seeds the registry with a single default profile when empty.
  static void _ensureDefault() {
    if (profiles.isEmpty) {
      _writeRaw(const [
        DeviceProfile(id: DeviceProfile.defaultId, name: 'Default'),
      ], DeviceProfile.defaultId);
    }
  }

  static List<DeviceProfile> get profiles {
    final list = _raw['profiles'];
    if (list is! List) return const [];
    return [
      for (final p in list)
        if (p is Map) DeviceProfile.fromJson(p),
    ];
  }

  static String get activeId {
    final id = (_raw['activeId'] ?? DeviceProfile.defaultId).toString();
    // Guard against a dangling active id (e.g. deleted out of band).
    return profiles.any((p) => p.id == id) ? id : DeviceProfile.defaultId;
  }

  static DeviceProfile? get active =>
      profiles.where((p) => p.id == activeId).firstOrNull;

  static void _putProfiles(List<DeviceProfile> profiles, {String? activeId}) =>
      _writeRaw(profiles, activeId ?? ProfileStore.activeId);

  /// The directory for [id]'s boxes: the root for the default profile (and on
  /// web, where path is ignored), else `profiles/<id>`.
  static String? _dirFor(String id) {
    if (id == DeviceProfile.defaultId || _rootPath == null) return _rootPath;
    final profilesRoot = p.normalize(
      p.absolute(p.join(_rootPath!, 'profiles')),
    );
    final profileDir = p.normalize(p.absolute(p.join(profilesRoot, id)));
    if (!p.isWithin(profilesRoot, profileDir)) {
      throw ArgumentError.value(id, 'id', 'Unsafe profile storage id');
    }
    return profileDir;
  }

  static String _boxNameForProfile(String baseName, String id) {
    if (!_useWebBoxNamespaces || id == DeviceProfile.defaultId) return baseName;
    final namespace = sha256.convert(utf8.encode(id));
    return '$baseName-profile-$namespace';
  }

  static Future<void> _openProfileBoxes(String id) async {
    final path = _dirFor(id);
    if (path != null && !_useWebBoxNamespaces) {
      final dir = Directory(path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }
    await Hive.openBox(_boxNameForProfile(sessionBoxName, id), path: path);
    await Hive.openBox(_boxNameForProfile(settingsBoxName, id), path: path);
  }

  static Future<void> _closeProfileBoxes(String id) async {
    final sessionName = _boxNameForProfile(sessionBoxName, id);
    final settingsName = _boxNameForProfile(settingsBoxName, id);
    if (Hive.isBoxOpen(sessionName)) {
      await Hive.box(sessionName).close();
    }
    if (Hive.isBoxOpen(settingsName)) {
      await Hive.box(settingsName).close();
    }
  }

  /// Closes the current profile's session/settings boxes and reopens [id]'s,
  /// recording it as active. The caller is responsible for rebuilding the
  /// provider tree afterwards (see the app restart in main.dart).
  static Future<void> switchTo(String id) async {
    if (!profiles.any((profile) => profile.id == id)) {
      throw ArgumentError.value(id, 'id', 'Unknown profile');
    }
    final previousId = activeId;
    if (id == previousId) return;

    await _closeProfileBoxes(previousId);
    try {
      await _openProfileBoxes(id);
      _putProfiles(profiles, activeId: id);
    } catch (error, stackTrace) {
      await _closeProfileBoxes(id);
      await _openProfileBoxes(previousId);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  // ── Registry mutations ────────────────────────────────────────────────────

  static String _slugify(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'(^-+)|(-+$)'), '');
    var slug = base.isEmpty ? 'profile' : base;
    final existing = profiles.map((p) => p.id).toSet();
    if (!existing.contains(slug)) return slug;
    var i = 2;
    while (existing.contains('$slug-$i')) {
      i++;
    }
    return '$slug-$i';
  }

  /// Creates a new profile with [name] and optional [pin]. Returns its id.
  static String create(String name, {String? pin}) {
    final id = _slugify(name);
    final salt = pin == null || pin.isEmpty ? '' : _randomSalt();
    final hash = pin == null || pin.isEmpty ? '' : hashPin(salt, pin);
    final next = [
      ...profiles,
      DeviceProfile(
        id: id,
        name: name.trim().isEmpty ? id : name.trim(),
        pinSalt: salt,
        pinHash: hash,
      ),
    ];
    _putProfiles(next);
    return id;
  }

  static void rename(String id, String name) {
    final next = [
      for (final p in profiles)
        if (p.id == id)
          p.copyWith(name: name.trim().isEmpty ? p.name : name.trim())
        else
          p,
    ];
    _putProfiles(next);
  }

  /// Deletes [id] (never the default) and removes its storage directory. If it
  /// was active, the default becomes active. Returns false for the default.
  static Future<bool> delete(String id) async {
    if (id == DeviceProfile.defaultId) return false;
    if (!profiles.any((profile) => profile.id == id)) return false;

    String? dir;
    try {
      dir = _dirFor(id);
    } catch (e) {
      debugPrint('Refusing to remove unsafe profile dir for $id: $e');
      return false;
    }

    final wasActive = activeId == id;
    if (wasActive) await switchTo(DeviceProfile.defaultId);
    if (_useWebBoxNamespaces) {
      try {
        await Hive.deleteBoxFromDisk(_boxNameForProfile(sessionBoxName, id));
        await Hive.deleteBoxFromDisk(_boxNameForProfile(settingsBoxName, id));
      } catch (e) {
        debugPrint('Failed to remove Web profile boxes for $id: $e');
        return false;
      }
    } else if (dir != null) {
      try {
        final d = Directory(dir);
        if (d.existsSync()) d.deleteSync(recursive: true);
      } catch (e) {
        debugPrint('Failed to remove profile dir for $id: $e');
        return false;
      }
    }
    final next = [
      for (final p in profiles)
        if (p.id != id) p,
    ];
    _putProfiles(next);
    return true;
  }

  /// Sets or clears [id]'s PIN ([pin] empty/null clears it).
  static void setPin(String id, String? pin) {
    final clearing = pin == null || pin.isEmpty;
    final salt = clearing ? '' : _randomSalt();
    final hash = clearing ? '' : hashPin(salt, pin);
    final next = [
      for (final p in profiles)
        if (p.id == id) p.copyWith(pinSalt: salt, pinHash: hash) else p,
    ];
    _putProfiles(next);
  }

  /// Verifies [pin] against [id]'s stored hash.
  static bool verifyPin(String id, String pin) {
    final profile = profiles.where((p) => p.id == id).firstOrNull;
    if (profile == null || !profile.hasPin) return true;
    return hashPin(profile.pinSalt, pin) == profile.pinHash;
  }

  // ── PIN hashing ───────────────────────────────────────────────────────────

  static String _randomSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Iterated salted SHA-256 for the casual in-app PIN gate.
  ///
  /// This verifier is deliberately not described as encryption or as an
  /// at-rest security boundary; profile Hive data remains readable on disk.
  static String hashPin(String salt, String pin) {
    List<int> digest = utf8.encode('$salt:$pin');
    for (var i = 0; i < 10000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
