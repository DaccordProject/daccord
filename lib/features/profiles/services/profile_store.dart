import 'dart:convert';
import 'dart:math';

import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:universal_io/io.dart';
import 'package:universal_platform/universal_platform.dart';

/// Low-level storage for local device profiles: the global registry box and the
/// per-profile `accord-session` / `accord-settings` box (re)opening.
///
/// Isolation strategy: the **default** profile keeps the canonical box files at
/// the root data dir (so data created before profiles existed is preserved),
/// while every other profile gets its own `profiles/<id>` directory. The box
/// *names* never change, so the session/settings/tab controllers keep reading
/// `Hive.box('accord-session')` / `'accord-settings'` unmodified — they simply
/// resolve to whichever profile's files were opened at boot / on switch.
///
/// Note: directory isolation applies on native platforms. On web Hive ignores
/// the path (storage is keyed by box name in IndexedDB), so profiles there
/// share storage; the registry + PIN gate still work.
class ProfileStore {
  ProfileStore._();

  static const registryBoxName = 'profile-registry';
  static const _registryKey = 'registry';
  static const sessionBoxName = 'accord-session';
  static const settingsBoxName = 'accord-settings';

  /// Root Hive data dir (native only; null on web). Captured in [bootstrap].
  static String? _rootPath;

  /// Opens the registry box, ensures a default profile exists, and opens the
  /// active profile's session/settings boxes. Defensive: any failure falls back
  /// to opening the canonical boxes at the root so the app always boots.
  static Future<void> bootstrap(String? rootPath) async {
    _rootPath = rootPath;
    try {
      await Hive.openBox(registryBoxName);
      _ensureDefault();
      await _openProfileBoxes(activeId);
    } catch (e) {
      debugPrint('Profile bootstrap failed ($e); using default storage.');
      if (!Hive.isBoxOpen(sessionBoxName)) {
        await Hive.openBox(sessionBoxName);
      }
      if (!Hive.isBoxOpen(settingsBoxName)) {
        await Hive.openBox(settingsBoxName);
      }
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
    return '$_rootPath/profiles/$id';
  }

  static Future<void> _openProfileBoxes(String id) async {
    final path = _dirFor(id);
    if (path != null && !UniversalPlatform.isWeb) {
      final dir = Directory(path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }
    await Hive.openBox(sessionBoxName, path: path);
    await Hive.openBox(settingsBoxName, path: path);
  }

  /// Closes the current profile's session/settings boxes and reopens [id]'s,
  /// recording it as active. The caller is responsible for rebuilding the
  /// provider tree afterwards (see the app restart in main.dart).
  static Future<void> switchTo(String id) async {
    if (Hive.isBoxOpen(sessionBoxName)) await Hive.box(sessionBoxName).close();
    if (Hive.isBoxOpen(settingsBoxName))
      await Hive.box(settingsBoxName).close();
    _putProfiles(profiles, activeId: id);
    await _openProfileBoxes(id);
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
    final wasActive = activeId == id;
    if (wasActive) await switchTo(DeviceProfile.defaultId);
    final next = [
      for (final p in profiles)
        if (p.id != id) p,
    ];
    _putProfiles(next);
    final dir = _dirFor(id);
    if (dir != null && !UniversalPlatform.isWeb) {
      try {
        final d = Directory(dir);
        if (d.existsSync()) d.deleteSync(recursive: true);
      } catch (e) {
        debugPrint('Failed to remove profile dir for $id: $e');
      }
    }
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

  /// Iterated salted SHA-256 of [pin] — a lightweight stand-in for the
  /// reference's PBKDF2, sufficient for a local device-access PIN gate.
  static String hashPin(String salt, String pin) {
    List<int> digest = utf8.encode('$salt:$pin');
    for (var i = 0; i < 10000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
