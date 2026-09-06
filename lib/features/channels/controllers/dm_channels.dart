import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/shared/utils/list_ext.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dm_channels.g.dart';

/// Builds the `createDm` request body for a 1:1 DM with [recipientId].
///
/// A **qualified** id (`<snowflake>@<domain>`) uses the single `recipient_id`
/// field so the server takes its cross-server DM path (deterministic home +
/// replica mirror). A bare id uses the `recipients` list, an unchanged
/// same-server DM. The server accepts either field, so this only steers which
/// path it picks.
Map<String, dynamic> dmCreateBody(String recipientId) => isRemoteId(recipientId)
    ? <String, dynamic>{'recipient_id': recipientId}
    : <String, dynamic>{
        'recipients': [recipientId],
      };

/// Whether [value] is a usable remote DM handle: a qualified id with a non-empty
/// local part and a home domain (`<id>@<domain>`). Bare (local) ids are rejected
/// — the remote-DM flow is specifically for users on another server.
bool isValidRemoteHandle(String value) {
  final v = value.trim();
  return isRemoteId(v) && domainOf(v) != null && localPart(v).isNotEmpty;
}

/// Title for a DM/group channel: its custom name, else the other participants'
/// names (everyone but [selfId]) joined with commas, else [fallback]. When
/// [users] (the on-demand user cache) is given, a cached entry is preferred
/// over the recipient object embedded in the channel.
String dmChannelTitle(
  AccordChannel channel,
  String? selfId, {
  required String fallback,
  Map<String, AccordUser>? users,
}) {
  final name = channel.name;
  if (name != null && name.isNotEmpty) return name;
  final others = (channel.recipients ?? const <AccordUser>[]).where(
    (u) => u.id != selfId,
  );
  if (others.isEmpty) return fallback;
  return others
      .map((u) {
        final cached = users?[u.id] ?? u;
        // Fall back to the raw id, not "Unknown", so an unhydrated recipient is
        // still distinguishable from any other unhydrated one.
        return accordUserName(cached, fallback: cached.id);
      })
      .join(', ');
}

/// Per-server cache of the current user's direct-message and group-DM channels
/// (the ones with no `spaceId`). The direct-messages dialog populates it from a
/// one-shot `users.listChannels` fetch and then watches it, while
/// `accord_event_handler.dart` keeps it in sync from the gateway: group DMs
/// created remotely appear, renames / recipient changes (which arrive as
/// `channel.update`) update in place, and leaves / deletions remove the entry.
///
/// A `null` state means "not loaded yet" — the dialog's fetch is the only thing
/// that transitions it out of null, so gateway upserts that arrive before the
/// dialog has ever opened are intentionally dropped (the next open refetches).
@Riverpod(keepAlive: true)
class DmChannelsController extends _$DmChannelsController {
  final Map<String, String> _previews = {};

  @override
  List<AccordChannel>? build(String serverKey) => null;

  /// Replaces the cache with a freshly-fetched list.
  void setChannels(List<AccordChannel> channels) {
    final ids = channels.map((channel) => channel.id).toSet();
    _previews.removeWhere((id, _) => !ids.contains(id));
    state = List.unmodifiable(channels);
  }

  /// Last-message text shown under a DM conversation. Attachment-only messages
  /// use a human-readable fallback rather than leaving a blank row.
  String? previewFor(String channelId) => _previews[channelId];

  /// Seeds a preview loaded alongside the conversation list without changing
  /// its server-provided order.
  void setPreview(String channelId, AccordMessage message) {
    _previews[channelId] = _messagePreview(message);
    final current = state;
    if (current != null) state = [...current];
  }

  /// Applies live DM activity: update the preview, last-message id, and move the
  /// conversation to the front. The gateway calls this even when the DM dialog
  /// is closed, provided its list cache has been initialized once.
  void applyMessage(AccordMessage message) {
    final current = state;
    if (current == null) return;
    final index = current.indexWhere(
      (channel) => channel.id == message.channelId,
    );
    if (index < 0) return;
    final channel = current[index]..lastMessageId = message.id;
    _previews[channel.id] = _messagePreview(message);
    state = [channel, ...current.where((item) => item.id != channel.id)];
  }

  void updateMessagePreview(AccordMessage message) {
    final current = state;
    if (current == null) return;
    final channel = _findChannel(current, message.channelId);
    if (channel?.lastMessageId != message.id) return;
    _previews[message.channelId] = _messagePreview(message);
    state = [...current];
  }

  void removeMessagePreview(String channelId, String messageId) {
    final current = state;
    if (current == null) return;
    final channel = _findChannel(current, channelId);
    if (channel?.lastMessageId != messageId) return;
    channel?.lastMessageId = null;
    _previews.remove(channelId);
    state = [...current];
  }

  bool contains(String channelId) =>
      state?.any((channel) => channel.id == channelId) ?? false;

  /// Inserts or replaces [channel] (matched by id). Brand-new channels go to the
  /// front so a just-created group DM surfaces at the top of the list.
  void upsert(AccordChannel channel) {
    final current = state;
    if (current == null) return;
    final index = current.indexWhere((c) => c.id == channel.id);
    if (index == -1) {
      state = [channel, ...current];
    } else {
      final next = [...current];
      next[index] = channel;
      state = next;
    }
  }

  /// Removes the channel with [channelId] from the cache, if present.
  void remove(String channelId) {
    final current = state;
    if (current == null) return;
    _previews.remove(channelId);
    state = current.removeById(channelId, (c) => c.id);
  }
}

String _messagePreview(AccordMessage message) {
  final content = message.content.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (content.isNotEmpty) return content;
  final count = message.attachments.length;
  if (count == 1) return 'Attachment';
  if (count > 1) return '$count attachments';
  return 'Message';
}

AccordChannel? _findChannel(List<AccordChannel> channels, String channelId) {
  for (final channel in channels) {
    if (channel.id == channelId) return channel;
  }
  return null;
}
