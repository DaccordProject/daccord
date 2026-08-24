import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'typing.g.dart';

/// How long a typing indicator stays visible after the last `typing.start`
/// event for a user (the server emits one roughly every ~8–10s while typing).
const _typingTimeout = Duration(seconds: 10);

/// The set of users currently typing in a channel, keyed by channel ID. Each
/// user is held for [_typingTimeout] after their last event, then expires.
/// Returns user IDs in arrival order; the UI resolves them to names via the
/// member cache.
@Riverpod(keepAlive: true)
class TypingController extends _$TypingController {
  final Map<String, Timer> _timers = {};

  @override
  List<String> build(String serverKey, String channelId) {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const [];
  }

  /// Marks [userId] as typing (or refreshes their timeout).
  void userTyping(String userId) {
    _timers[userId]?.cancel();
    _timers[userId] = Timer(_typingTimeout, () => _expire(userId));
    if (!state.contains(userId)) {
      state = [...state, userId];
    }
  }

  /// Immediately clears [userId] (e.g. once they send a message).
  void clear(String userId) {
    _timers.remove(userId)?.cancel();
    if (state.contains(userId)) {
      state = state.where((id) => id != userId).toList();
    }
  }

  void _expire(String userId) {
    _timers.remove(userId);
    if (state.contains(userId)) {
      state = state.where((id) => id != userId).toList();
    }
  }
}
