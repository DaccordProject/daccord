import 'package:accordkit/accordkit.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'voice_states.g.dart';

/// Per-server cache of who is in which voice channel, keyed `channel_id →
/// {user_id → state}`. User moves scan channels and copy only affected buckets.
///
/// Seeded from the gateway READY payload's voice states and from
/// `channels.fetchVoiceStates`, then kept in sync by `voice.state_update`
/// events (all wired in `accord_event_handler.dart`). A `voice.state_update`
/// with a null `channelId` means the user left voice entirely.
@Riverpod(keepAlive: true)
class VoiceStatesController extends _$VoiceStatesController {
  @override
  Map<String, Map<String, AccordVoiceState>> build(String serverKey) =>
      const {};

  /// Applies a single voice state: removes the user from any previous channel
  /// and, when [vs.channelId] is non-null, inserts them into that channel.
  void upsert(AccordVoiceState vs) {
    if (vs.userId.isEmpty) return;
    final channelId = vs.channelId;
    final next = <String, Map<String, AccordVoiceState>>{};
    for (final entry in state.entries) {
      var bucket = entry.value;
      final isDestination = entry.key == channelId && entry.key.isNotEmpty;
      if (bucket.containsKey(vs.userId) || isDestination) {
        bucket = {...bucket}..remove(vs.userId);
        if (isDestination) bucket[vs.userId] = vs;
      }
      if (bucket.isNotEmpty) next[entry.key] = bucket;
    }
    if (channelId != null &&
        channelId.isNotEmpty &&
        !next.containsKey(channelId)) {
      next[channelId] = {vs.userId: vs};
    }
    state = next;
  }

  /// Replaces the full set of states for [channelId] (used to seed a channel
  /// from `channels.fetchVoiceStates`).
  void seedChannel(String channelId, Iterable<AccordVoiceState> states) {
    final bucket = {
      for (final s in states)
        if (s.userId.isNotEmpty) s.userId: s,
    };
    final next = {...state};
    if (bucket.isEmpty) {
      next.remove(channelId);
    } else {
      next[channelId] = bucket;
    }
    state = next;
  }

  /// Removes [userId] from [channelId] (fallback for a peer-left signal).
  void removeUser(String channelId, String userId) {
    final bucket = state[channelId];
    if (bucket == null || !bucket.containsKey(userId)) return;
    final updated = {...bucket}..remove(userId);
    final next = {...state};
    if (updated.isEmpty) {
      next.remove(channelId);
    } else {
      next[channelId] = updated;
    }
    state = next;
  }

  /// Clears the whole cache (on logout / gateway teardown).
  void clear() => state = const {};
}

/// The voice states present in [channelId], in arbitrary order.
List<AccordVoiceState> voiceStatesFor(
  Map<String, Map<String, AccordVoiceState>> cache,
  String channelId,
) => cache[channelId]?.values.toList() ?? const [];

/// How many users are currently in [channelId]'s voice.
int voiceUserCount(
  Map<String, Map<String, AccordVoiceState>> cache,
  String channelId,
) => cache[channelId]?.length ?? 0;
