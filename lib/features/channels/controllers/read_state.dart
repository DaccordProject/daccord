import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'read_state.g.dart';

/// A snapshot of which channels are unread and how many mentions each carries.
/// Distinct from a notification — a channel can be "unread" without raising a
/// system notification (e.g. when the user opted into `mentions only` and the
/// new message wasn't a mention).
class ReadStateSnapshot {
  const ReadStateSnapshot({
    this.unread = const <String>{},
    this.mentions = const <String, int>{},
  });

  /// Channel IDs with at least one unseen message.
  final Set<String> unread;

  /// Pending mention count per channel; absent entries mean zero.
  final Map<String, int> mentions;

  /// True when [channelId] has at least one unseen message.
  bool isUnread(String channelId) => unread.contains(channelId);

  /// Pending mention count for [channelId] (0 when not set).
  int mentionCount(String channelId) => mentions[channelId] ?? 0;

  /// Aggregate mention count across [channelIds] — used by the space rail to
  /// roll up a server-level mention badge.
  int mentionsAcross(Iterable<String> channelIds) {
    var total = 0;
    for (final id in channelIds) {
      total += mentions[id] ?? 0;
    }
    return total;
  }

  /// True when any of [channelIds] is unread.
  bool anyUnread(Iterable<String> channelIds) =>
      channelIds.any(unread.contains);
}

/// Client-side read/unread tracker. Mirrors the reference client's
/// `client_unread.gd`: the gateway handler marks channels unread on incoming
/// messages (skipping the visible channel and own messages), and the home
/// screen marks the visible channel read when it's selected — which also acks
/// the latest message ID to the server. State is in-memory only; on cold start
/// the user just sees no unread badges until the gateway reports new traffic,
/// matching the reference's behavior.
@Riverpod(keepAlive: true)
class ReadStateController extends _$ReadStateController {
  @override
  ReadStateSnapshot build() => const ReadStateSnapshot();

  /// Records a new unseen message in [channelId]. When [isMention] is true the
  /// channel's mention count is bumped (rendered as a numeric badge).
  void markUnread(String channelId, {bool isMention = false}) {
    if (channelId.isEmpty) return;
    final current = state;
    final alreadyUnread = current.unread.contains(channelId);
    if (alreadyUnread && !isMention) return;
    final unread = {...current.unread, channelId};
    final mentions = Map<String, int>.from(current.mentions);
    if (isMention) {
      mentions[channelId] = (mentions[channelId] ?? 0) + 1;
    }
    state = ReadStateSnapshot(unread: unread, mentions: mentions);
  }

  /// Clears [channelId]'s unread + mention state. Called when the user opens
  /// the channel; the caller separately POSTs `channels.ack` to update server
  /// read state.
  void markRead(String channelId) {
    final current = state;
    if (!current.unread.contains(channelId) &&
        !current.mentions.containsKey(channelId)) {
      return;
    }
    final unread = {...current.unread}..remove(channelId);
    final mentions = Map<String, int>.from(current.mentions)
      ..remove(channelId);
    state = ReadStateSnapshot(unread: unread, mentions: mentions);
  }

  /// Drops every entry — used when switching accounts so a freshly-connected
  /// session doesn't inherit the previous one's badges.
  void clear() {
    if (state.unread.isEmpty && state.mentions.isEmpty) return;
    state = const ReadStateSnapshot();
  }
}
