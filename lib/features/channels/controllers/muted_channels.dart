import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'muted_channels.g.dart';

/// Outcome of [MutedChannelsController.setMuted].
///
/// A plain `bool` could not tell "the server rejected it" apart from "another
/// tap for this channel is still in flight", so every caller had to treat the
/// in-flight case as a failure — or, as they did, say nothing at all (#306).
enum MuteResult {
  /// The server accepted the change; the optimistic state stands.
  ok,

  /// The server rejected it (or there was no client); the state rolled back and
  /// the caller must tell the user.
  failed,

  /// Ignored because the same channel is already being updated. Not a failure —
  /// the in-flight request still owns the outcome.
  busy,
}

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
  ///
  /// Returns [MuteResult.failed] when the rollback happened, so the caller can
  /// say why the toggle sprang back instead of leaving it unexplained.
  Future<MuteResult> setMuted(String channelId, bool muted) async {
    if (!_updating.add(channelId)) return MuteResult.busy;
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
        return MuteResult.failed;
      }
      final result = muted
          ? await client.channels.mute(channelId)
          : await client.channels.unmute(channelId);
      if (!result.ok) _rollback(channelId, wasMuted);
      return result.ok ? MuteResult.ok : MuteResult.failed;
    } catch (_) {
      _rollback(channelId, wasMuted);
      return MuteResult.failed;
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
