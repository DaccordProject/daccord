import 'package:accordkit/accordkit.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dm_channels.g.dart';

/// Global cache of the current user's direct-message and group-DM channels
/// (the ones with no `spaceId`). The direct-messages dialog populates it from a
/// one-shot `users.listChannels` fetch and then watches it, while
/// `accord_event_handler.dart` keeps it in sync from the gateway: group DMs
/// created remotely appear, renames / recipient changes (which arrive as
/// `channel.update`) update in place, and leaves / deletions remove the entry.
///
/// A `null` state means "not loaded yet" — the dialog's fetch is the only thing
/// that transitions it out of null, so gateway upserts that arrive before the
/// dialog has ever opened are intentionally dropped (the next open refetches).
@Riverpod(keepAlive: true)
class DmChannelsController extends _$DmChannelsController {
  @override
  List<AccordChannel>? build() => null;

  /// Replaces the cache with a freshly-fetched list.
  void setChannels(List<AccordChannel> channels) {
    state = List.unmodifiable(channels);
  }

  /// Inserts or replaces [channel] (matched by id). Brand-new channels go to the
  /// front so a just-created group DM surfaces at the top of the list.
  void upsert(AccordChannel channel) {
    final current = state;
    if (current == null) return;
    final index = current.indexWhere((c) => c.id == channel.id);
    if (index == -1) {
      state = [channel, ...current];
    } else {
      final next = [...current];
      next[index] = channel;
      state = next;
    }
  }

  /// Removes the channel with [channelId] from the cache, if present.
  void remove(String channelId) {
    final current = state;
    if (current == null) return;
    state = current.where((c) => c.id != channelId).toList();
  }
}
