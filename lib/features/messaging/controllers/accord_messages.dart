import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_messages.g.dart';

/// Channels that currently have a live message controller. The gateway handler
/// consults this so it only mutates caches the UI has actually opened, rather
/// than instantiating (and history-loading) a controller for every channel
/// that happens to receive a message.
final Set<String> activeMessageChannels = <String>{};

/// The channel the user is currently viewing, if any. The notification layer
/// consults this to avoid raising a notification for a message in the channel
/// that's already on screen. Set by the home screen as the selection changes.
String? accordVisibleChannelId;

/// A channel's recent message history, keyed by channel ID, ordered
/// oldest→newest for display. Self-loads via `messages.list` the first time
/// it's watched (once logged in) and is kept in sync by message
/// create/update/delete gateway events. `null` means "not loaded yet".
@Riverpod(keepAlive: true)
class AccordMessagesController extends _$AccordMessagesController {
  @override
  List<AccordMessage>? build(String channelId) {
    activeMessageChannels.add(channelId);
    ref.onDispose(() => activeMessageChannels.remove(channelId));

    final client = ref.watch(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.client : null),
    );
    if (client != null) {
      _load(client, channelId);
    }
    return null;
  }

  Future<void> _load(AccordClient client, String channelId) async {
    final result = await client.messages.list(channelId, query: {'limit': 50});
    if (!result.ok) {
      debugPrint('Failed to load messages for $channelId: ${result.error}');
      return;
    }
    final data = result.data;
    if (data is List) {
      // The REST list returns newest-first; store oldest-first for display.
      state = data.whereType<AccordMessage>().toList().reversed.toList();
    }
  }

  /// Sends [content] to this channel. Optimistically appends the created
  /// message (the gateway echo is then deduped by `addMessage`). Pass [replyTo]
  /// to send the message as a reply to that message ID. Returns true on success.
  Future<bool> send(AccordClient client, String content,
      {String? replyTo}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    final data = <String, dynamic>{'content': trimmed};
    if (replyTo != null) data['reply_to'] = replyTo;
    final result = await client.messages.create(channelId, data);
    if (!result.ok) {
      debugPrint('Failed to send message to $channelId: ${result.error}');
      return false;
    }
    final message = result.data;
    if (message is AccordMessage) addMessage(message);
    return true;
  }

  /// Pins [messageId] in this channel, optimistically flipping its `pinned`
  /// flag (reverted on failure). Returns true on success.
  Future<bool> pin(AccordClient client, String messageId) async {
    _setPinned(messageId, true);
    final result = await client.messages.pin(channelId, messageId);
    if (!result.ok) {
      debugPrint('Failed to pin $messageId: ${result.error}');
      _setPinned(messageId, false);
      return false;
    }
    return true;
  }

  /// Unpins [messageId] in this channel, optimistically clearing its `pinned`
  /// flag (reverted on failure). Returns true on success.
  Future<bool> unpin(AccordClient client, String messageId) async {
    _setPinned(messageId, false);
    final result = await client.messages.unpin(channelId, messageId);
    if (!result.ok) {
      debugPrint('Failed to unpin $messageId: ${result.error}');
      _setPinned(messageId, true);
      return false;
    }
    return true;
  }

  void _setPinned(String messageId, bool pinned) {
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message == null || message.pinned == pinned) return;
    message.pinned = pinned;
    state = [...current];
  }

  /// Edits [messageId] to [content] via `messages.edit`, optimistically
  /// applying the result (the gateway echo is then a no-op). Returns true on
  /// success.
  Future<bool> edit(
      AccordClient client, String messageId, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    final result =
        await client.messages.edit(channelId, messageId, {'content': trimmed});
    if (!result.ok) {
      debugPrint('Failed to edit message $messageId: ${result.error}');
      return false;
    }
    final message = result.data;
    if (message is AccordMessage) updateMessage(message);
    return true;
  }

  /// Deletes [messageId] via `messages.delete`, optimistically removing it.
  /// Returns true on success.
  Future<bool> delete(AccordClient client, String messageId) async {
    final result = await client.messages.delete(channelId, messageId);
    if (!result.ok) {
      debugPrint('Failed to delete message $messageId: ${result.error}');
      return false;
    }
    removeMessage(messageId);
    return true;
  }

  /// Sends [content] plus file [files] to this channel via
  /// `messages.createWithAttachments`. Each file is a map with `filename`,
  /// `content` (bytes) and optional `content_type`. Falls back to a plain
  /// [send] when there are no files. Returns true on success.
  Future<bool> sendWithAttachments(
    AccordClient client,
    String content,
    List<Map<String, dynamic>> files, {
    String? replyTo,
  }) async {
    if (files.isEmpty) return send(client, content, replyTo: replyTo);
    final data = <String, dynamic>{};
    final trimmed = content.trim();
    if (trimmed.isNotEmpty) data['content'] = trimmed;
    if (replyTo != null) data['reply_to'] = replyTo;

    final result =
        await client.messages.createWithAttachments(channelId, data, files);
    if (!result.ok) {
      debugPrint(
          'Failed to send attachments to $channelId: ${result.error}');
      return false;
    }
    final message = result.data;
    if (message is AccordMessage) addMessage(message);
    return true;
  }

  /// Appends a newly-received message, ignoring duplicates (e.g. the gateway
  /// echo of a message we just sent).
  void addMessage(AccordMessage message) {
    final current = [...(state ?? const <AccordMessage>[])];
    if (current.any((m) => m.id == message.id)) return;
    current.add(message);
    state = current;
  }

  void updateMessage(AccordMessage message) {
    final current = state;
    if (current == null) return;
    final index = current.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    final copy = [...current];
    copy[index] = message;
    state = copy;
  }

  void removeMessage(String messageId) {
    final current = state;
    if (current == null) return;
    state = current.where((m) => m.id != messageId).toList();
  }

  // ── Reactions ──────────────────────────────────────────────────────────────

  /// Adds or removes the current user's [emojiName] reaction on [messageId],
  /// flipping based on whether it currently includes us. Optimistically updates
  /// the cache, then reverts if the REST call fails (the gateway echo is then a
  /// no-op).
  ///
  /// [emojiName] is the bare name (unicode char, or the custom emoji's name);
  /// [emojiId] is set for custom emoji. The REST API expects the token
  /// `name:id` for custom emoji, but aggregates are matched/stored by name
  /// (the form the gateway echoes back).
  Future<void> toggleReaction(
      AccordClient client, String messageId, String emojiName,
      {String? emojiId}) async {
    final message = state?.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return;
    final existing = message.reactions
        ?.firstWhereOrNull((r) => _emojiName(r) == emojiName);
    final adding = !(existing?.includesMe ?? false);
    final token = emojiId == null ? emojiName : '$emojiName:$emojiId';

    applyReaction(messageId, emojiName,
        added: adding, isOwn: true, emojiId: emojiId);

    final result = adding
        ? await client.reactions.add(channelId, messageId, token)
        : await client.reactions.removeOwn(channelId, messageId, token);
    if (!result.ok) {
      debugPrint('Failed to toggle reaction on $messageId: ${result.error}');
      // Revert the optimistic change.
      applyReaction(messageId, emojiName,
          added: !adding, isOwn: true, emojiId: emojiId);
    }
  }

  /// Applies a reaction add/remove to [messageId]'s aggregate counts. Used both
  /// for optimistic local toggles ([isOwn] true) and for gateway echoes of
  /// other users' reactions ([isOwn] reflects whether the actor is us).
  void applyReaction(String messageId, String emojiName,
      {required bool added, required bool isOwn, String? emojiId}) {
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return;

    final reactions = [...(message.reactions ?? const <AccordReaction>[])];
    final index = reactions.indexWhere((r) => _emojiName(r) == emojiName);

    if (added) {
      if (index >= 0) {
        final r = reactions[index];
        if (isOwn && r.includesMe) return; // already counted
        r.count += 1;
        if (isOwn) r.includesMe = true;
      } else {
        reactions.add(AccordReaction(
          emoji: {'id': emojiId, 'name': emojiName},
          count: 1,
          includesMe: isOwn,
        ));
      }
    } else {
      if (index < 0) return;
      final r = reactions[index];
      if (isOwn && !r.includesMe) return; // nothing of ours to remove
      r.count = r.count > 0 ? r.count - 1 : 0;
      if (isOwn) r.includesMe = false;
      if (r.count <= 0) reactions.removeAt(index);
    }

    message.reactions = reactions;
    state = [...current];
  }

  /// Removes a single emoji's reactions from [messageId] (gateway
  /// `reaction.clear_emoji`).
  void clearReactionEmoji(String messageId, String emojiName) {
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message?.reactions == null) return;
    message!.reactions =
        message.reactions!.where((r) => _emojiName(r) != emojiName).toList();
    state = [...current];
  }

  /// Removes all reactions from [messageId] (gateway `reaction.clear`).
  void clearReactions(String messageId) {
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return;
    message.reactions = <AccordReaction>[];
    state = [...current];
  }

  String _emojiName(AccordReaction r) => r.emoji['name']?.toString() ?? '';
}
