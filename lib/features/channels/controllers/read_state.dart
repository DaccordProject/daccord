import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'read_state.g.dart';

/// One unread channel: which space it belongs to (so the rail can roll a
/// server-level badge up from per-channel state) and how many pending mentions
/// it carries. [spaceId] is null for DMs, which never appear in the space rail.
class ReadEntry {
  const ReadEntry({
    required this.channelId,
    this.spaceId,
    this.mentions = 0,
  });

  final String channelId;
  final String? spaceId;
  final int mentions;

  ReadEntry copyWith({String? spaceId, int? mentions}) => ReadEntry(
        channelId: channelId,
        spaceId: spaceId ?? this.spaceId,
        mentions: mentions ?? this.mentions,
      );
}

/// A snapshot of which channels are unread (and their mention counts) for a
/// single server. Distinct from a notification — a channel can be "unread"
/// without raising a system notification (e.g. when the user opted into
/// `mentions only` and the new message wasn't a mention).
class ReadStateSnapshot {
  const ReadStateSnapshot({this.entries = const <String, ReadEntry>{}});

  /// Unread channels keyed by channel ID.
  final Map<String, ReadEntry> entries;

  /// True when [channelId] has at least one unseen message.
  bool isUnread(String channelId) => entries.containsKey(channelId);

  /// Pending mention count for [channelId] (0 when read).
  int mentionCount(String channelId) => entries[channelId]?.mentions ?? 0;

  /// True when any channel in [spaceId] is unread — drives the rail dot.
  bool anyUnreadInSpace(String spaceId) =>
      entries.values.any((e) => e.spaceId == spaceId);

  /// Aggregate mention count across [spaceId]'s channels — drives the rail's
  /// server-level mention badge.
  int mentionsInSpace(String spaceId) {
    var total = 0;
    for (final e in entries.values) {
      if (e.spaceId == spaceId) total += e.mentions;
    }
    return total;
  }
}

/// Client-side read/unread tracker, one instance per connected server (keyed by
/// `serverKey`, i.e. `userId@baseUrl`) so snowflake IDs that collide across
/// servers don't clobber each other.
///
/// Three things feed it:
///  * the gateway READY handler [hydrate]s the server's authoritative unread
///    list on every (re)connect — this is what survives a cold start and what
///    lights up *background* servers;
///  * the gateway message handler [markUnread]s on incoming traffic for live
///    updates (every connection, not just the active one);
///  * the home screen / context menu / voice panel [markRead]s the channel the
///    user opens, which separately POSTs `channels.ack` to the server.
@Riverpod(keepAlive: true)
class ReadStateController extends _$ReadStateController {
  @override
  ReadStateSnapshot build(String serverKey) => const ReadStateSnapshot();

  /// Records a new unseen message in [channelId]. When [isMention] is true the
  /// channel's mention count is bumped (rendered as a numeric badge). [spaceId]
  /// lets the rail roll the unread up to the owning server.
  void markUnread(String channelId, {String? spaceId, bool isMention = false}) {
    if (channelId.isEmpty) return;
    final existing = state.entries[channelId];
    // Already unread and this isn't a mention: nothing to bump, but backfill a
    // previously-unknown spaceId so the rail rollup stays correct.
    if (existing != null && !isMention) {
      if (existing.spaceId == null && spaceId != null) {
        final entries = Map<String, ReadEntry>.from(state.entries);
        entries[channelId] = existing.copyWith(spaceId: spaceId);
        state = ReadStateSnapshot(entries: entries);
      }
      return;
    }
    final entries = Map<String, ReadEntry>.from(state.entries);
    entries[channelId] = ReadEntry(
      channelId: channelId,
      spaceId: spaceId ?? existing?.spaceId,
      mentions: (existing?.mentions ?? 0) + (isMention ? 1 : 0),
    );
    state = ReadStateSnapshot(entries: entries);
  }

  /// Clears [channelId]'s unread + mention state. Called when the user opens
  /// the channel; the caller separately POSTs `channels.ack` to update server
  /// read state.
  void markRead(String channelId) {
    if (!state.entries.containsKey(channelId)) return;
    final entries = Map<String, ReadEntry>.from(state.entries)
      ..remove(channelId);
    state = ReadStateSnapshot(entries: entries);
  }

  /// Replaces the whole snapshot from the server's authoritative unread list
  /// (the READY payload's `unread` array, or `GET /users/@me/read-states`).
  /// This is what gives persistence across restarts.
  void hydrate(Iterable<ReadEntry> unread) {
    state = ReadStateSnapshot(entries: {
      for (final e in unread)
        if (e.channelId.isNotEmpty) e.channelId: e,
    });
  }

  /// Drops every entry — used when a server disconnects / the account is
  /// removed so a stale snapshot doesn't linger.
  void clear() {
    if (state.entries.isEmpty) return;
    state = const ReadStateSnapshot();
  }
}
