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
  /// message (the gateway echo is then deduped by `addMessage`). Returns true
  /// on success.
  Future<bool> send(AccordClient client, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    final result =
        await client.messages.create(channelId, {'content': trimmed});
    if (!result.ok) {
      debugPrint('Failed to send message to $channelId: ${result.error}');
      return false;
    }
    final message = result.data;
    if (message is AccordMessage) addMessage(message);
    return true;
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
    List<Map<String, dynamic>> files,
  ) async {
    if (files.isEmpty) return send(client, content);
    final data = <String, dynamic>{};
    final trimmed = content.trim();
    if (trimmed.isNotEmpty) data['content'] = trimmed;

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
  Future<void> toggleReaction(
      AccordClient client, String messageId, String emojiName) async {
    final message = state?.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return;
    final existing = message.reactions
        ?.firstWhereOrNull((r) => _emojiName(r) == emojiName);
    final adding = !(existing?.includesMe ?? false);

    applyReaction(messageId, emojiName, added: adding, isOwn: true);

    final result = adding
        ? await client.reactions.add(channelId, messageId, emojiName)
        : await client.reactions.removeOwn(channelId, messageId, emojiName);
    if (!result.ok) {
      debugPrint('Failed to toggle reaction on $messageId: ${result.error}');
      // Revert the optimistic change.
      applyReaction(messageId, emojiName, added: !adding, isOwn: true);
    }
  }

  /// Applies a reaction add/remove to [messageId]'s aggregate counts. Used both
  /// for optimistic local toggles ([isOwn] true) and for gateway echoes of
  /// other users' reactions ([isOwn] reflects whether the actor is us).
  void applyReaction(String messageId, String emojiName,
      {required bool added, required bool isOwn}) {
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
          emoji: {'id': null, 'name': emojiName},
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
