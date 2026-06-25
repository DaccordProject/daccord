import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/list_ext.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_emojis.g.dart';

/// A space's custom emoji, keyed by space ID. Self-loads via `emojis.list` the
/// first time it's watched (once logged in). `null` means "not loaded yet";
/// an empty list means the space has no custom emoji.
@Riverpod(keepAlive: true)
class AccordEmojisController extends _$AccordEmojisController {
  @override
  List<AccordEmoji>? build(String spaceId) {
    final client = ref.watchAccordClient();
    if (client != null) {
      _load(client, spaceId);
    }
    return null;
  }

  Future<void> _load(AccordClient client, String spaceId) async {
    final emojis = (await client.emojis.list(spaceId))
        .listOrLog<AccordEmoji>('emojis for $spaceId');
    if (emojis != null) state = emojis;
  }

  /// Inserts [emoji] (when the id is new) or replaces an existing one in
  /// place. Used by the emoji-management dialog to mirror create/rename
  /// results into the cache without a full reload.
  void upsert(AccordEmoji emoji) {
    state = (state ?? const <AccordEmoji>[]).upsertById(emoji, (e) => e.id);
  }

  /// Drops [emojiId] from the cache after a successful delete.
  void remove(String emojiId) {
    final current = state;
    if (current == null) return;
    state = current.removeById(emojiId, (e) => e.id);
  }
}
