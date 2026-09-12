import 'dart:async';

import 'package:bonfire/features/channels/utils/message_position.dart';
import 'package:bonfire/features/notifications/services/notification.dart';
export 'package:bonfire/features/channels/utils/message_position.dart';

import 'package:accordkit/accordkit.dart';
import 'package:flutter/foundation.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'read_state.g.dart';

/// Pure policy deciding whether truthful unread state may light a *visible*
/// indicator, given the user's mute settings. The notification analogue is
/// [MessageNotificationGate]; the two must agree, so a space you muted never
/// lights its rail icon either.
///
/// Deliberately applied on the *read* side ([ReadStateSnapshot]'s mute-aware
/// getters) rather than in [ReadStateController.markUnread] / the READY
/// hydrate: the stored state stays truthful, so unmuting immediately reveals
/// unread that arrived while muted without waiting for a reconnect.
class UnreadIndicatorGate {
  const UnreadIndicatorGate._();

  /// Whether an unread channel contributes to its space's rail dot / mention
  /// badge. [spaceMuted] mirrors `AccordSettings.isSpaceMuted` and silences the
  /// whole roll-up; [channelLevel] mirrors
  /// `AccordSettings.channelNotificationLevel` — `'nothing'` never contributes,
  /// `'mentions'` (the default, also `null`) and `'all'` do.
  static bool countsTowardSpace({
    required bool spaceMuted,
    String? channelLevel,
  }) {
    if (spaceMuted) return false;
    return channelLevel != AccordSettings.channelNotifNothing;
  }

  /// Whether an unread channel shows its pip in the channel list. Only the
  /// per-channel level applies: a muted *space* still shows unread state
  /// *inside* the space (muting greys the rail roll-up, it doesn't hide which
  /// channels moved on), matching Discord.
  static bool showsChannelPip({String? channelLevel}) =>
      channelLevel != AccordSettings.channelNotifNothing;
}

/// One unread channel: which space it belongs to (so the rail can roll a
/// server-level badge up from per-channel state) and how many pending mentions
/// it carries. [spaceId] is null for DMs, which never appear in the space rail.
class ReadEntry {
  const ReadEntry({
    required this.channelId,
    this.spaceId,
    this.mentions = 0,
    this.lastMessageId,
    this.lastReadMessageId,
  });

  final String channelId;
  final String? spaceId;
  final int mentions;
  final String? lastMessageId;
  final String? lastReadMessageId;

  ReadEntry copyWith({String? spaceId, int? mentions}) => ReadEntry(
    channelId: channelId,
    spaceId: spaceId ?? this.spaceId,
    mentions: mentions ?? this.mentions,
    lastMessageId: lastMessageId,
    lastReadMessageId: lastReadMessageId,
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

  // --- Mute-aware variants (what the UI actually renders) -------------------
  //
  // [channelLevels] mirrors `AccordSettings.channelNotifications` (channel ID →
  // `'all' | 'mentions' | 'nothing'`, missing = the mention default) and
  // [spaceMuted] mirrors `AccordSettings.isSpaceMuted(spaceId)`. Callers watch
  // those two slices of settings rather than the whole object, so a draft
  // keystroke doesn't rebuild the rail.

  /// [isUnread], minus channels the user silenced — the channel-list pip.
  bool isUnreadVisible(
    String channelId, {
    Map<String, String> channelLevels = const <String, String>{},
  }) =>
      isUnread(channelId) &&
      UnreadIndicatorGate.showsChannelPip(
        channelLevel: channelLevels[channelId],
      );

  /// [mentionCount], zeroed for channels the user silenced.
  int visibleMentionCount(
    String channelId, {
    Map<String, String> channelLevels = const <String, String>{},
  }) =>
      UnreadIndicatorGate.showsChannelPip(
        channelLevel: channelLevels[channelId],
      )
      ? mentionCount(channelId)
      : 0;

  /// Whether the rail should show an unread dot, excluding muted spaces and
  /// silenced channels.
  bool spaceShowsUnread(
    String spaceId, {
    required bool spaceMuted,
    Map<String, String> channelLevels = const <String, String>{},
  }) {
    if (spaceMuted) return false;
    return entries.values.any(
      (e) =>
          e.spaceId == spaceId &&
          UnreadIndicatorGate.countsTowardSpace(
            spaceMuted: spaceMuted,
            channelLevel: channelLevels[e.channelId],
          ),
    );
  }

  /// Mention count for the rail badge, excluding muted spaces and silenced
  /// channels.
  int visibleMentionsInSpace(
    String spaceId, {
    required bool spaceMuted,
    Map<String, String> channelLevels = const <String, String>{},
  }) {
    if (spaceMuted) return 0;
    var total = 0;
    for (final e in entries.values) {
      if (e.spaceId != spaceId) continue;
      if (!UnreadIndicatorGate.countsTowardSpace(
        spaceMuted: spaceMuted,
        channelLevel: channelLevels[e.channelId],
      )) {
        continue;
      }
      total += e.mentions;
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
///  * visible panes and explicit read actions call [acknowledge], which clears
///    local state and queues the server read position;
///  * [applyRemoteRead] consumes acknowledgements from other devices.
@Riverpod(keepAlive: true)
class ReadStateController extends _$ReadStateController {
  final _latest = <String, String>{};
  final _received = <String, String>{};
  final _readThrough = <String, String>{};
  final _syncedThrough = <String, String>{};
  final _pending = <String, String>{};
  final _sending = <String>{};
  final _retries = <String, Timer>{};
  final _mentionIds = <String, Set<String>>{};

  @override
  ReadStateSnapshot build(String serverKey) {
    ref.onDispose(() {
      for (final timer in _retries.values) {
        timer.cancel();
      }
    });
    return const ReadStateSnapshot();
  }

  String? latestMessageId(String channelId) => _latest[channelId];

  /// Records delivery before notifications/sounds are considered. A replay or
  /// a message already read on another device must not alert a second time.
  bool receiveMessage(String channelId, String messageId) {
    final previous = _received[channelId];
    _advance(_latest, channelId, messageId);
    if (_atOrBefore(messageId, previous)) return false;
    _advance(_received, channelId, messageId);
    return !_atOrBefore(messageId, _readThrough[channelId]);
  }

  void markUnread(
    String channelId, {
    String? spaceId,
    bool isMention = false,
    String? messageId,
  }) {
    if (channelId.isEmpty) return;
    if (messageId != null) {
      _advance(_latest, channelId, messageId);
      if (_atOrBefore(messageId, _readThrough[channelId])) return;
      if (isMention &&
          !(_mentionIds[channelId] ??= <String>{}).add(messageId)) {
        return;
      }
    }
    final existing = state.entries[channelId];
    final entries = Map<String, ReadEntry>.from(state.entries);
    entries[channelId] = ReadEntry(
      channelId: channelId,
      spaceId: spaceId ?? existing?.spaceId,
      mentions: (existing?.mentions ?? 0) + (isMention ? 1 : 0),
      lastMessageId: _latest[channelId],
    );
    state = ReadStateSnapshot(entries: entries);
  }

  /// Clears only messages up to the acknowledged position. Old acknowledgements
  /// from another device cannot hide messages that arrived after that position.
  void markRead(String channelId, {String? messageId}) {
    final position = messageId ?? _latest[channelId];
    if (position != null) _advance(_readThrough, channelId, position);
    unawaited(
      dismissReadNotifications(
        serverKey: serverKey,
        channelId: channelId,
        messageId: position,
      ),
    );
    final existing = state.entries[channelId];
    if (existing == null) return;
    final entries = Map<String, ReadEntry>.from(state.entries);
    final latest = existing.lastMessageId ?? _latest[channelId];
    if (position != null &&
        latest != null &&
        compareMessageIds(latest, position) > 0) {
      final mentions = _mentionIds[channelId];
      var cleared = 0;
      mentions?.removeWhere((id) {
        if (!_atOrBefore(id, position)) return false;
        cleared++;
        return true;
      });
      entries[channelId] = existing.copyWith(
        mentions: (existing.mentions - cleared).clamp(0, existing.mentions),
      );
    } else {
      entries.remove(channelId);
      _mentionIds.remove(channelId);
    }
    state = ReadStateSnapshot(entries: entries);
  }

  void applyRemoteRead(String channelId, String messageId) {
    _advance(_syncedThrough, channelId, messageId);
    markRead(channelId, messageId: messageId);
  }

  /// Optimistic local read plus a serialized, coalesced server acknowledgement.
  /// Failed requests remain queued and are retried; they are never considered
  /// synced just because the local badge disappeared.
  void acknowledge(AccordClient? client, String channelId, String? messageId) {
    markRead(channelId, messageId: messageId);
    if (messageId == null || messageId.isEmpty) return;
    if (_atOrBefore(messageId, _syncedThrough[channelId])) return;
    _advance(_pending, channelId, messageId);
    if (client != null) unawaited(_flush(client, channelId));
  }

  void retryPending(AccordClient client) {
    for (final channelId in _pending.keys.toList()) {
      unawaited(_flush(client, channelId));
    }
  }

  Future<void> _flush(AccordClient client, String channelId) async {
    if (!_sending.add(channelId)) return;
    _retries.remove(channelId)?.cancel();
    try {
      while (ref.mounted) {
        final position = _pending[channelId];
        if (position == null) break;
        if (_atOrBefore(position, _syncedThrough[channelId])) {
          _pending.remove(channelId);
          break;
        }
        final result = await client.channels.ack(channelId, position);
        if (!ref.mounted) return;
        if (!result.ok || result.statusCode < 200 || result.statusCode >= 300) {
          debugPrint(
            'Failed to acknowledge channel $channelId: ${result.error}',
          );
          break;
        }
        _advance(_syncedThrough, channelId, position);
        if (_pending[channelId] == position) _pending.remove(channelId);
      }
    } catch (error) {
      debugPrint('Failed to acknowledge channel $channelId: $error');
    } finally {
      _sending.remove(channelId);
      if (ref.mounted && _pending.containsKey(channelId)) {
        _retries[channelId] = Timer(const Duration(seconds: 5), () {
          if (ref.mounted) unawaited(_flush(client, channelId));
        });
      }
    }
  }

  /// READY is authoritative, except for local reads still awaiting delivery.
  void hydrate(Iterable<ReadEntry> unread) {
    _mentionIds.clear();
    final entries = <String, ReadEntry>{};
    for (final entry in unread) {
      final id = entry.channelId;
      if (id.isEmpty) continue;
      final last = entry.lastMessageId;
      final read = entry.lastReadMessageId;
      if (last != null) {
        _advance(_latest, id, last);
        _advance(_received, id, last);
      }
      if (read != null) {
        _advance(_readThrough, id, read);
        _advance(_syncedThrough, id, read);
        unawaited(
          dismissReadNotifications(
            serverKey: serverKey,
            channelId: id,
            messageId: read,
          ),
        );
      }
      if (last != null && _atOrBefore(last, _readThrough[id])) continue;
      entries[id] = entry;
    }
    // A fresh READY can replace missed remote read events after disconnection.
    for (final id in state.entries.keys) {
      if (entries.containsKey(id)) continue;
      final last = _latest[id];
      if (last != null) _advance(_readThrough, id, last);
      unawaited(dismissReadNotifications(serverKey: serverKey, channelId: id));
    }
    state = ReadStateSnapshot(entries: entries);
  }

  void clear() {
    for (final timer in _retries.values) {
      timer.cancel();
    }
    _retries.clear();
    _pending.clear();
    _sending.clear();
    _latest.clear();
    _received.clear();
    _readThrough.clear();
    _syncedThrough.clear();
    _mentionIds.clear();
    state = const ReadStateSnapshot();
  }
}

bool _atOrBefore(String id, String? position) =>
    position != null && compareMessageIds(id, position) <= 0;

void _advance(Map<String, String> positions, String channelId, String id) {
  if (id.isEmpty || _atOrBefore(id, positions[channelId])) return;
  positions[channelId] = id;
}
