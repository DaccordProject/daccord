import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'muted_channels.g.dart';

/// Server-backed channel mutes for one connected account.
///
/// Both the channel header and context menu use this cache so opening either
/// surface does not refetch the full mute list or leave the other one stale.
@Riverpod(keepAlive: true)
class MutedChannelsController extends _$MutedChannelsController {
  final Set<String> _updating = {};

  @override
  Future<Set<String>> build(String serverKey) async {
    final client = ref
        .read(accordAuthProvider.notifier)
        .clientForKey(serverKey);
    if (client == null) return const {};
    final result = await client.users.listMutes();
    return _parseMutedChannelIds(result.data);
  }

  /// Optimistically updates [channelId], rolling back when the server rejects
  /// the change. Repeated taps while the same channel is in flight are ignored.
  Future<bool> setMuted(String channelId, bool muted) async {
    if (!_updating.add(channelId)) return false;
    final previous = state.value ?? const <String>{};
    final wasMuted = previous.contains(channelId);
    final next = {...previous};
    muted ? next.add(channelId) : next.remove(channelId);
    state = AsyncData(next);

    try {
      final client = ref
          .read(accordAuthProvider.notifier)
          .clientForKey(serverKey);
      if (client == null) {
        _rollback(channelId, wasMuted);
        return false;
      }
      final result = muted
          ? await client.channels.mute(channelId)
          : await client.channels.unmute(channelId);
      if (!result.ok) _rollback(channelId, wasMuted);
      return result.ok;
    } catch (_) {
      _rollback(channelId, wasMuted);
      return false;
    } finally {
      _updating.remove(channelId);
    }
  }

  void _rollback(String channelId, bool wasMuted) {
    final restored = {...?state.value};
    wasMuted ? restored.add(channelId) : restored.remove(channelId);
    state = AsyncData(restored);
  }
}

Set<String> _parseMutedChannelIds(Object? data) => data is List
    ? data
          .map(
            (entry) => entry is Map
                ? entry['channel_id']?.toString()
                : entry?.toString(),
          )
          .whereType<String>()
          .toSet()
    : const {};
