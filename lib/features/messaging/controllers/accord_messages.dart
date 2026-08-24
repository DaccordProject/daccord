import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
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

    final client = ref.watchAccordClient();
    if (client != null) {
      _load(client, channelId);
    }
    return null;
  }

  /// How many messages to request per page. Used by both the initial load and
  /// the older-page cursor fetch; if a page comes back smaller than this we've
  /// reached the start of history.
  static const _pageSize = 50;

  /// True while [loadOlder] has an in-flight REST call. UI uses this to show a
  /// "loading older messages" indicator and to suppress duplicate fetches when
  /// the user keeps scrolling.
  bool isLoadingOlder = false;

  /// False once a page returned fewer than [_pageSize] messages — there's no
  /// older history to fetch. UI hides its "load older" affordance when set.
  bool hasMoreOlder = true;

  Future<void> _load(AccordClient client, String channelId) async {
    final result = await client.messages.list(
      channelId,
      query: {'limit': _pageSize},
    );
    if (!result.ok) {
      debugPrint('Failed to load messages for $channelId: ${result.error}');
      return;
    }
    final data = result.data;
    if (data is List) {
      final list = data.whereType<AccordMessage>().toList();
      // The REST list returns newest-first; store oldest-first for display.
      state = list.reversed.toList();
      if (list.length < _pageSize) hasMoreOlder = false;
    }
  }

  /// Re-fetches the newest page, replacing the cache in place (no flash to the
  /// loading state). Used after a gateway re-identify: a fresh session gets no
  /// event replay, so anything that happened while disconnected is missing
  /// from the cache until refetched.
  Future<void> reload(AccordClient client) {
    // Reset the pagination guard so that if loadOlder was in flight its
    // eventual state-write is superseded by the reload result.
    isLoadingOlder = false;
    hasMoreOlder = true;
    return _load(client, channelId);
  }

  /// Loads the previous page of messages (older than the currently-oldest one
  /// in cache) and prepends them to [state]. Idempotent under concurrent calls
  /// and a no-op once [hasMoreOlder] is false. Returns the number of new
  /// messages loaded (0 means "no more"). Mirrors the reference client's
  /// scroll-up pagination via the `before` cursor.
  Future<int> loadOlder(AccordClient client) async {
    if (isLoadingOlder || !hasMoreOlder) return 0;
    final current = state;
    if (current == null || current.isEmpty) return 0;
    isLoadingOlder = true;
    // Bump state so widgets watching the list rebuild and can show a spinner.
    state = [...current];
    try {
      final oldestId = current.first.id;
      final result = await client.messages.list(
        channelId,
        query: {'limit': _pageSize, 'before': oldestId},
      );
      if (!result.ok) {
        debugPrint(
          'Failed to load older messages for $channelId: ${result.error}',
        );
        return 0;
      }
      final data = result.data;
      if (data is! List) return 0;
      final page = data.whereType<AccordMessage>().toList();
      if (page.length < _pageSize) hasMoreOlder = false;
      if (page.isEmpty) return 0;
      // REST returns newest-first within the page; prepend oldest-first.
      final older = page.reversed.toList();
      final newest = state ?? current;
      // Dedupe in case an overlapping message snuck in (e.g. live insert).
      final knownIds = newest.map((m) => m.id).toSet();
      final fresh = older.where((m) => !knownIds.contains(m.id)).toList();
      state = [...fresh, ...newest];
      return fresh.length;
    } finally {
      isLoadingOlder = false;
      // Bump state again so the spinner-watching widget rebuilds.
      final s = state;
      if (s != null) state = [...s];
    }
  }

  /// Sends [content] to this channel. Optimistically appends the created
  /// message (the gateway echo is then deduped by `addMessage`). Pass [replyTo]
  /// to send the message as a reply to that message ID. Returns true on success.
  Future<bool> send(
    AccordClient client,
    String content, {
    String? replyTo,
  }) async => await _createMessage(client, content, replyTo: replyTo) == null;

  /// Sends [content] via `messages.create`. Returns null on success, or the
  /// server's own failure message — shared by [send] and the no-attachments
  /// path of [sendWithAttachments] so both surface the same reason instead of
  /// [send]'s bool swallowing it.
  Future<String?> _createMessage(
    AccordClient client,
    String content, {
    String? replyTo,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return 'Message is empty.';
    final data = <String, dynamic>{'content': trimmed};
    if (replyTo != null) data['reply_to'] = replyTo;
    final result = await client.messages.create(channelId, data);
    if (!result.ok) {
      debugPrint('Failed to send message to $channelId: ${result.error}');
      return result.errorMessageOr('Failed to send message.');
    }
    final message = result.data;
    if (message is AccordMessage) addMessage(message);
    return null;
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
    AccordClient client,
    String messageId,
    String content,
  ) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    final result = await client.messages.edit(channelId, messageId, {
      'content': trimmed,
    });
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

  /// Bulk-deletes [messageIds] via `messages.bulkDelete`, optimistically
  /// removing them. The endpoint requires 2–100 ids; a single id falls back to
  /// [delete]. Returns true on success.
  Future<bool> bulkDelete(AccordClient client, List<String> messageIds) async {
    if (messageIds.isEmpty) return false;
    if (messageIds.length == 1) return delete(client, messageIds.first);
    final result = await client.messages.bulkDelete(channelId, messageIds);
    if (!result.ok) {
      debugPrint('Failed to bulk-delete in $channelId: ${result.error}');
      return false;
    }
    final current = state;
    if (current != null) {
      final ids = messageIds.toSet();
      state = current.where((m) => !ids.contains(m.id)).toList();
    }
    return true;
  }

  /// Sends [content] plus file [files] to this channel via
  /// `messages.createWithAttachments`. Each file is a map with `filename`,
  /// `content` (bytes) and optional `content_type`. Falls back to
  /// `messages.create` (the same call [send] makes) when there are no files.
  ///
  /// Returns null on success, or the failure message to show the user. The
  /// server's own reason is passed through — a rejected upload (too large, no
  /// `attach_files` permission, unsupported type) is otherwise indistinguishable
  /// from a dead Send button.
  Future<String?> sendWithAttachments(
    AccordClient client,
    String content,
    List<Map<String, dynamic>> files, {
    String? replyTo,
  }) async {
    if (files.isEmpty) {
      return _createMessage(client, content, replyTo: replyTo);
    }
    final data = <String, dynamic>{'content': content.trim()};
    if (replyTo != null) data['reply_to'] = replyTo;

    final result = await client.messages.createWithAttachments(
      channelId,
      data,
      files,
    );
    if (!result.ok) {
      debugPrint('Failed to send attachments to $channelId: ${result.error}');
      return result.errorMessageOr('Failed to send attachments.');
    }
    final message = result.data;
    if (message is AccordMessage) addMessage(message);
    return null;
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
    AccordClient client,
    String messageId,
    String emojiName, {
    String? emojiId,
  }) async {
    final message = state?.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return;
    final existing = message.reactions?.firstWhereOrNull(
      (r) => _emojiName(r) == _emojiKey(emojiName, emojiId),
    );
    final adding = !(existing?.includesMe ?? false);
    final token = emojiId == null
        ? resolveEmojiGlyph(emojiName)
        : '$emojiName:$emojiId';

    applyReaction(
      messageId,
      emojiName,
      added: adding,
      isOwn: true,
      emojiId: emojiId,
    );

    final result = adding
        ? await client.reactions.add(channelId, messageId, token)
        : await client.reactions.removeOwn(channelId, messageId, token);
    if (!result.ok) {
      debugPrint('Failed to toggle reaction on $messageId: ${result.error}');
      // Revert the optimistic change.
      applyReaction(
        messageId,
        emojiName,
        added: !adding,
        isOwn: true,
        emojiId: emojiId,
      );
    }
  }

  /// Lists the users who reacted to [messageId] with [emojiName] (custom emoji
  /// pass [emojiId]). Lazy — called when the reactor popup opens. Returns an
  /// empty list on failure.
  Future<List<AccordUser>> reactionUsers(
    AccordClient client,
    String messageId,
    String emojiName, {
    String? emojiId,
    int limit = 100,
  }) async {
    final token = emojiId == null
        ? resolveEmojiGlyph(emojiName)
        : '$emojiName:$emojiId';
    final result = await client.reactions.listUsers(
      channelId,
      messageId,
      token,
      query: {'limit': limit},
    );
    if (!result.ok) {
      debugPrint('Failed to list reactors for $messageId: ${result.error}');
      return const [];
    }
    final data = result.data;
    if (data is! List) return const [];
    // The endpoint returns bare user-id strings, not user objects — resolve each
    // to an AccordUser, falling back to an id-only stub if the fetch fails so the
    // reactor still appears (and the list matches the badge count).
    final users = ref.read(accordUsersControllerProvider.notifier);
    final resolved = <Future<AccordUser>>[];
    for (final item in data) {
      if (item is AccordUser) {
        if (item.id.isEmpty) continue;
        users.upsert(item);
        resolved.add(Future.value(item));
        continue;
      }
      final id = item.toString();
      if (id.isEmpty) continue;
      resolved.add(
        users
            .resolve(id, client: client)
            .then((user) => user ?? AccordUser(id: id)),
      );
    }
    return Future.wait(resolved);
  }

  /// Applies a reaction add/remove to [messageId]'s aggregate counts. Used both
  /// for optimistic local toggles ([isOwn] true) and for gateway echoes of
  /// other users' reactions ([isOwn] reflects whether the actor is us).
  void applyReaction(
    String messageId,
    String emojiName, {
    required bool added,
    required bool isOwn,
    String? emojiId,
  }) {
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return;

    final key = _emojiKey(emojiName, emojiId);
    final reactions = [...(message.reactions ?? const <AccordReaction>[])];
    final index = reactions.indexWhere((r) => _emojiName(r) == key);

    if (added) {
      if (index >= 0) {
        final r = reactions[index];
        if (isOwn && r.includesMe) return; // already counted
        r.count += 1;
        if (isOwn) r.includesMe = true;
      } else {
        reactions.add(
          AccordReaction(
            // Store the canonical key (glyph for unicode) so an optimistic pill
            // and its later gateway echo dedup to one — see [_emojiKey].
            emoji: {'id': emojiId, 'name': key},
            count: 1,
            includesMe: isOwn,
          ),
        );
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
    message!.reactions = message.reactions!
        .where((r) => _emojiName(r) != _emojiKey(emojiName, null))
        .toList();
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

  // Dedup/match key for a reaction.
  String _emojiName(AccordReaction r) =>
      _emojiKey(r.emoji['name']?.toString() ?? '', r.emoji['id']?.toString());

  // Canonical dedup key for an emoji reference. Custom emoji key on their name
  // (the id is carried separately, and may arrive baked into the name as
  // `name:id` when the source didn't split it — strip it). Unicode emoji key on
  // their glyph: the picker hands us a shortcode (`hamburger`) while the gateway
  // echoes the glyph (`🍔`), so without resolving both to the glyph an optimistic
  // pill and its echo wouldn't match, leaving two pills for one reaction.
  String _emojiKey(String name, String? id) {
    if (id != null && id.isNotEmpty) return name;
    return resolveEmojiGlyph(parseEmojiToken(name).name);
  }
}
