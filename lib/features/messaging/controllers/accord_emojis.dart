import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_emojis.g.dart';

/// A space's custom emoji, keyed by space ID. Self-loads via `emojis.list` the
/// first time it's watched (once logged in). `null` means "not loaded yet";
/// an empty list means the space has no custom emoji.
@Riverpod(keepAlive: true)
class AccordEmojisController extends _$AccordEmojisController {
  @override
  List<AccordEmoji>? build(String spaceId) {
    final client = ref.watch(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.client : null),
    );
    if (client != null) {
      _load(client, spaceId);
    }
    return null;
  }

  Future<void> _load(AccordClient client, String spaceId) async {
    final result = await client.emojis.list(spaceId);
    if (!result.ok) {
      debugPrint('Failed to load emojis for $spaceId: ${result.error}');
      return;
    }
    final data = result.data;
    if (data is List) {
      state = data.whereType<AccordEmoji>().toList();
    }
  }

  /// Inserts [emoji] (when the id is new) or replaces an existing one in
  /// place. Used by the emoji-management dialog to mirror create/rename
  /// results into the cache without a full reload.
  void upsert(AccordEmoji emoji) {
    final current = [...(state ?? const <AccordEmoji>[])];
    final index = current.indexWhere((e) => e.id == emoji.id);
    if (index >= 0) {
      current[index] = emoji;
    } else {
      current.add(emoji);
    }
    state = current;
  }

  /// Drops [emojiId] from the cache after a successful delete.
  void remove(String emojiId) {
    final current = state;
    if (current == null) return;
    state = current.where((e) => e.id != emojiId).toList();
  }
}
