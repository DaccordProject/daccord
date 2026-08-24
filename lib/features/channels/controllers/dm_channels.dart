import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/list_ext.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dm_channels.g.dart';

/// Builds the `createDm` request body for a 1:1 DM with [recipientId].
///
/// A **qualified** id (`<snowflake>@<domain>`) uses the single `recipient_id`
/// field so the server takes its cross-server DM path (deterministic home +
/// replica mirror). A bare id uses the `recipients` list, an unchanged
/// same-server DM. The server accepts either field, so this only steers which
/// path it picks.
Map<String, dynamic> dmCreateBody(String recipientId) => isRemoteId(recipientId)
    ? <String, dynamic>{'recipient_id': recipientId}
    : <String, dynamic>{
        'recipients': [recipientId],
      };

/// Whether [value] is a usable remote DM handle: a qualified id with a non-empty
/// local part and a home domain (`<id>@<domain>`). Bare (local) ids are rejected
/// — the remote-DM flow is specifically for users on another server.
bool isValidRemoteHandle(String value) {
  final v = value.trim();
  return isRemoteId(v) && domainOf(v) != null && localPart(v).isNotEmpty;
}

/// Per-server cache of the current user's direct-message and group-DM channels
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
  List<AccordChannel>? build(String serverKey) => null;

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
    state = current.removeById(channelId, (c) => c.id);
  }
}
