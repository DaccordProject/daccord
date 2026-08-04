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
    required this.at,
    this.serverKey,
    this.count = 1,
    this.video = false,
  });

  /// The DM/group-DM channel the call rang on.
  final String channelId;

  /// Who rang us (empty when the ring carried no caller id).
  final String callerId;

  /// When the most recent miss happened.
  final DateTime at;

  /// The connection (`userId@baseUrl`) the ring arrived on, kept for context.
  final String? serverKey;

  /// How many consecutive missed calls on this channel, collapsed into one
  /// entry (mirrors how a phone shows "Missed call (3)").
  final int count;

  /// Whether the last missed ring was a video call.
  final bool video;

  /// Label for the DM list row.
  String get label => count > 1 ? 'Missed call ($count)' : 'Missed call';

  /// Folds another miss on the same channel into this entry.
  MissedCall bump({
    required String callerId,
    required DateTime at,
    required bool video,
    String? serverKey,
  }) =>
      MissedCall(
        channelId: channelId,
        callerId: callerId.isEmpty ? this.callerId : callerId,
        at: at,
        serverKey: serverKey ?? this.serverKey,
        count: count + 1,
        video: video,
      );
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
/// the record is an attention cue rather than a call log, Accord has no
/// call-history API to reconcile against, and persisting would mean adding a new
/// Hive box in `setupHive()`.
///
/// Keyed by channel id alone; ids are per-server snowflakes, so the (unlikely)
/// case of two servers minting the same DM channel id could collide. [MissedCall
/// .serverKey] carries the origin connection for callers that care.
@Riverpod(keepAlive: true)
class MissedCallsController extends _$MissedCallsController {
  @override
  Map<String, MissedCall> build() => const {};

  /// Records an unanswered ring on [channelId], collapsing repeats into a
  /// single entry with a bumped [MissedCall.count].
  void record({
    required String channelId,
    required String callerId,
    String? serverKey,
    bool video = false,
    DateTime? at,
  }) {
    if (channelId.isEmpty) return;
    final when = at ?? DateTime.now();
    final existing = state[channelId];
    state = {
      ...state,
      channelId: existing == null
          ? MissedCall(
              channelId: channelId,
              callerId: callerId,
              at: when,
              serverKey: serverKey,
              video: video,
            )
          : existing.bump(
              callerId: callerId,
              at: when,
              video: video,
              serverKey: serverKey,
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
