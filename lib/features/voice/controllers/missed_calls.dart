import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'missed_calls.g.dart';

/// One unanswered incoming DM call: a `call.ring` that reached us but was never
/// accepted before the caller cancelled/ended it or our ring timer expired.
@immutable
class MissedCall {
  const MissedCall({
    required this.channelId,
    required this.callerId,
    this.count = 1,
    this.video = false,
  });

  /// The DM/group-DM channel the call rang on.
  final String channelId;

  /// Who rang us (empty when the ring carried no caller id).
  final String callerId;

  /// How many consecutive missed calls on this channel, collapsed into one
  /// entry (mirrors how a phone shows "Missed call (3)").
  final int count;

  /// Whether the last missed ring was a video call.
  final bool video;

  /// Label for the DM list row.
  String get label => count > 1 ? 'Missed call ($count)' : 'Missed call';
}

/// Unanswered incoming DM calls, keyed by channel id.
///
/// Recorded by [CallController] when a ring ends without a local accept
/// (`call.cancel`/`call.end` while still ringing, or our client-side ring
/// timeout — accordserver implements no ring timer of its own). An **explicitly
/// declined** call is deliberately *not* recorded: the user already saw and
/// answered the prompt, so re-surfacing it as an unread badge would be noise.
///
/// **Session-only.** The entries live in memory and are gone after a restart:
/// the record is an attention cue rather than a call log, and Accord has no
/// call-history API to reconcile against.
///
/// Keyed by channel id alone; ids are per-server snowflakes, so two servers
/// minting the same DM channel id could (unlikely) collide.
@Riverpod(keepAlive: true)
class MissedCallsController extends _$MissedCallsController {
  @override
  Map<String, MissedCall> build() => const {};

  /// Records an unanswered ring on [channelId], collapsing repeats into a
  /// single entry with a bumped [MissedCall.count].
  void record({
    required String channelId,
    required String callerId,
    bool video = false,
  }) {
    if (channelId.isEmpty) return;
    final existing = state[channelId];
    state = {
      ...state,
      channelId: MissedCall(
        channelId: channelId,
        // A repeat ring with no caller id keeps the earlier caller.
        callerId: callerId.isEmpty && existing != null
            ? existing.callerId
            : callerId,
        count: (existing?.count ?? 0) + 1,
        video: video,
      ),
    };
  }

  /// Clears the indicator for [channelId] — called when the user opens the
  /// conversation (or answers a later call on it).
  void clear(String channelId) {
    if (!state.containsKey(channelId)) return;
    state = {...state}..remove(channelId);
  }

  /// Clears every missed-call indicator (e.g. on sign-out / profile switch).
  void clearAll() {
    if (state.isEmpty) return;
    state = const {};
  }
}
