import 'package:accordkit/accordkit.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'voice_states.g.dart';

/// Per-server cache of who is in which voice channel, keyed `channel_id →
/// {user_id → state}`. Updates copy only the affected buckets, so widgets
/// `select` `cache[channelId]` to rebuild only when their channel changes.
///
/// Seeded from the gateway READY payload (`accord_ready_sync.dart`) and from
/// `voice.getStatus` after a join, then kept in sync by `voice.state_update`
/// events. A `voice.state_update` with a null `channelId` means the user left
/// voice entirely.
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

  /// Replaces the full set of states for [channelId].
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
