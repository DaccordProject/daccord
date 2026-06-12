import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// On-disk cache of each server's last-known space list, keyed by connection
/// key (`userId@baseUrl`).
///
/// Spaces otherwise live only in memory and are populated from the gateway
/// READY. That means a server which is offline at launch — or slow to connect —
/// has no spaces to show, so its icons vanish from the rail entirely. Persisting
/// the last-known list lets the rail render those spaces immediately (dimmed,
/// while unreachable); the gateway READY refreshes them once it connects.
///
/// Stored as a JSON string per key so nested role/emoji maps round-trip cleanly
/// (Hive's own nested-map typing is lossy). Every method is best-effort and
/// never throws — a cache miss just falls back to "no spaces yet".
class SpaceCache {
  static const boxName = 'space-cache';

  static Box get _box => Hive.box(boxName);

  /// Persists [spaces] (including hydrated roles/emojis) for connection [key].
  static Future<void> save(String key, List<AccordSpace> spaces) async {
    try {
      await _box.put(key, jsonEncode([for (final s in spaces) s.toJson()]));
    } catch (e) {
      debugPrint('Failed to cache spaces for $key: $e');
    }
  }

  /// The last-known spaces for connection [key], or empty if none are cached.
  static List<AccordSpace> load(String key) {
    try {
      final raw = _box.get(key);
      if (raw is! String) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final s in decoded)
          if (s is Map) AccordSpace.fromJson(Map<String, dynamic>.from(s)),
      ];
    } catch (e) {
      debugPrint('Failed to read cached spaces for $key: $e');
      return const [];
    }
  }

  /// Drops the cached spaces for connection [key] (account removed/replaced).
  static Future<void> remove(String key) async {
    try {
      await _box.delete(key);
    } catch (_) {}
  }

  /// Drops every cached server (full logout).
  static Future<void> clear() async {
    try {
      await _box.clear();
    } catch (_) {}
  }
}
