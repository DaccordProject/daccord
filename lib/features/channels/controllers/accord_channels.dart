import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/utils/channel_sort.dart';
import 'package:bonfire/shared/controllers/load_failed.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/list_ext.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_channels.g.dart';

/// Whether a space's channel-list fetch failed, so the channel pane can offer a
/// retry instead of spinning forever. The [LoadFailed] flag for this cache —
/// see there for the shared pattern.
LoadFailedProvider channelsLoadFailedProvider(
  String serverKey,
  String spaceId,
) => loadFailedProvider('channels', serverKey, spaceId);

/// A space's channel list, keyed by space ID. The Accord analogue of Bonfire's
/// firebridge-backed channel list. Self-loads via `spaces.listChannels` the
/// first time it's watched (once logged in) and is kept in sync by
/// channel create/update/delete gateway events. `null` means "not loaded yet".
@Riverpod(keepAlive: true)
class AccordChannelsController extends _$AccordChannelsController {
  @override
  List<AccordChannel>? build(String serverKey, String spaceId) {
    final client = ref.watchAccordClientFor(serverKey);
    if (client != null) {
      _load(client, spaceId);
    }
    return null;
  }

  Future<void> _load(AccordClient client, String spaceId) async {
    final channels = (await client.spaces.listChannels(
      spaceId,
    )).listOrLog<AccordChannel>('channels for $spaceId');
    // The load-failed writes below all happen after the `await` above: `build`
    // calls `_load` synchronously, and Riverpod forbids a provider mutating
    // another during initialization.
    if (!ref.mounted) return;
    if (!ref.isCurrentAccordClient(serverKey, client)) return;
    // `null` here is a failed request or a malformed payload — the pane has no
    // other way to tell that apart from "still loading".
    if (channels == null) {
      ref.read(channelsLoadFailedProvider(serverKey, spaceId).notifier).set(true);
      return;
    }
    state = _sorted(channels);
    ref.read(channelsLoadFailedProvider(serverKey, spaceId).notifier).set(false);
  }

  void setChannels(List<AccordChannel> channels) => state = _sorted(channels);

  /// Inserts [channel], or replaces it in place if already present.
  void upsertChannel(AccordChannel channel) {
    state = _sorted(
      (state ?? const <AccordChannel>[]).upsertById(channel, (c) => c.id),
    );
  }

  void removeChannel(String channelId) {
    final current = state;
    if (current == null) return;
    state = current.removeById(channelId, (c) => c.id);
  }

  /// Creates a channel in this space. Returns the created channel on success,
  /// optimistically inserting it (the gateway create event is deduped by id).
  Future<AccordChannel?> createChannel(
    AccordClient client,
    Map<String, dynamic> data,
  ) async {
    final channel = (await client.spaces.createChannel(
      spaceId,
      data,
    )).dataOrLog<AccordChannel>('create channel in $spaceId');
    if (channel != null) upsertChannel(channel);
    return channel;
  }

  /// Patches a channel's settings, replacing it in place on success.
  Future<bool> updateChannel(
    AccordClient client,
    String channelId,
    Map<String, dynamic> data,
  ) async {
    final result = await client.channels.update(channelId, data);
    if (!result.ok) {
      debugPrint('Failed to update channel $channelId: ${result.error}');
      return false;
    }
    final channel = result.data;
    if (channel is AccordChannel) upsertChannel(channel);
    return true;
  }

  /// Deletes a channel, removing it from the list on success.
  Future<bool> deleteChannel(AccordClient client, String channelId) async {
    final result = await client.channels.delete(channelId);
    if (!result.ok) {
      debugPrint('Failed to delete channel $channelId: ${result.error}');
      return false;
    }
    removeChannel(channelId);
    return true;
  }

  /// Orders channels by `position` (categories carry their children via
  /// `parentId`, which the UI groups separately), falling back to ID.
  List<AccordChannel> _sorted(List<AccordChannel> channels) {
    final copy = [...channels];
    copy.sort((a, b) {
      final pa = parseChannelPosition(a);
      final pb = parseChannelPosition(b);
      if (pa != pb) return pa.compareTo(pb);
      return a.id.compareTo(b.id);
    });
    return copy;
  }
}
