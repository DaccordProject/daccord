import 'dart:convert';

import 'package:bonfire/features/messaging/models/pending_upload.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

/// On-disk record of each connection's AutoMod-held uploads, keyed by
/// connection key (`userId@baseUrl`) — the same scoping as `SpaceCache`.
///
/// A held upload can take minutes (a scanner backlog) or days (a moderator
/// queue) to resolve, so the IDs have to outlive the process: after a restart
/// the READY handler asks the server about every outstanding one. Stored as a
/// JSON string per key. Every method is best-effort and never throws — and is
/// a no-op when the box isn't open, which is the case under `flutter test`
/// unless a test opens it.
class PendingUploadStore {
  static const boxName = 'pending-uploads';

  static Box? get _box => Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  /// Persists [uploads] for connection [key].
  static Future<void> save(String key, Iterable<PendingUpload> uploads) async {
    final box = _box;
    if (box == null) return;
    try {
      if (uploads.isEmpty) {
        await box.delete(key);
      } else {
        await box.put(key, jsonEncode([for (final u in uploads) u.toJson()]));
      }
    } catch (e) {
      debugPrint('Failed to persist pending uploads for $key: $e');
    }
  }

  /// The stored uploads for connection [key], or empty if none are known.
  static List<PendingUpload> load(String key) {
    final box = _box;
    if (box == null) return const [];
    try {
      final raw = box.get(key);
      if (raw is! String) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final u in decoded)
          if (u is Map) PendingUpload.fromJson(Map<String, dynamic>.from(u)),
      ];
    } catch (e) {
      debugPrint('Failed to read pending uploads for $key: $e');
      return const [];
    }
  }

  /// Drops the stored uploads for connection [key] (account removed).
  static Future<void> remove(String key) async {
    final box = _box;
    if (box == null) return;
    try {
      await box.delete(key);
    } catch (e) {
      debugPrint('Failed to evict pending uploads for $key: $e');
    }
  }

  /// Drops every connection's stored uploads (full sign-out).
  static Future<void> clear() async {
    final box = _box;
    if (box == null) return;
    try {
      await box.clear();
    } catch (e) {
      debugPrint('Failed to clear pending uploads: $e');
    }
  }
}
