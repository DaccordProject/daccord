import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/list_ext.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'thread_replies.g.dart';

/// The identity of an open thread: the channel it lives in plus its root
/// message. Used by the gateway handler's active-thread registry.
typedef ThreadKey = ({String serverKey, String channelId, String rootId});

/// Threads that currently have a live replies controller. The gateway handler
/// consults this so it only routes thread-scoped message events into threads
/// the UI has actually opened, rather than instantiating (and history-loading)
/// a controller for every thread that receives a reply. Mirrors
/// `activeMessageChannels`.
final Set<ThreadKey> activeThreadReplies = <ThreadKey>{};

/// A thread's replies (excluding the root message), keyed by
/// (channelId, rootId), ordered oldest→newest as the server returns them.
/// Self-loads via `messages.listThread` the first time it's watched (once
/// logged in) and is kept in sync by thread-scoped message
/// create/update/delete gateway events. `null` means "not loaded yet".
@Riverpod(keepAlive: false)
class ThreadRepliesController extends _$ThreadRepliesController {
  @override
  List<AccordMessage>? build(
    String serverKey,
    String channelId,
    String rootId,
  ) {
    final ThreadKey key = (
      serverKey: serverKey,
      channelId: channelId,
      rootId: rootId,
    );
    activeThreadReplies.add(key);
    ref.onDispose(() => activeThreadReplies.remove(key));

    final client = ref.watchAccordClientFor(serverKey);
    if (client != null) {
      _load(client);
    }
    return null;
  }

  Future<void> _load(AccordClient client) async {
    final result = await client.messages.listThread(channelId, rootId);
    if (!ref.mounted || !ref.isCurrentAccordClient(serverKey, client)) return;
    final replies = result.listOrLog<AccordMessage>('thread $rootId');
    if (replies == null) {
      // Settle on empty rather than spin forever (matches the previous view
      // behavior); a re-identify [reload] retries.
      state = const [];
      return;
    }
    state = replies.where((m) => m.id != rootId).toList();
  }

  /// Re-fetches the reply list, replacing the cache in place (no flash back to
  /// the loading state). Used after a gateway re-identify: a fresh session gets
  /// no event replay, so anything that happened while disconnected is missing.
  Future<void> reload(AccordClient client) => _load(client);

  /// Sends [content] as a reply into this thread (`thread_id` = root).
  /// Optimistically appends the created message (the gateway echo is then
  /// deduped by [addReply]). Returns true on success.
  Future<bool> send(AccordClient client, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    final result = await client.messages.create(channelId, {
      'content': trimmed,
      'thread_id': rootId,
    });
    if (!ref.mounted) return false;
    final message = result.data;
    if (!result.ok || message is! AccordMessage) {
      debugPrint('Failed to reply in thread $rootId: ${result.error}');
      return false;
    }
    addReply(message);
    return true;
  }

  /// Deletes reply [messageId] via `messages.delete`, removing it from the
  /// list on success. Returns true on success.
  Future<bool> delete(AccordClient client, String messageId) async {
    final result = await client.messages.delete(channelId, messageId);
    if (!ref.mounted) return false;
    if (!result.ok) {
      debugPrint('Failed to delete reply $messageId: ${result.error}');
      return false;
    }
    removeReply(messageId);
    return true;
  }

  /// Appends a newly-received reply, ignoring the root itself and duplicates
  /// (e.g. the gateway echo of a reply we just sent).
  void addReply(AccordMessage message) {
    if (message.id == rootId) return;
    final current = state ?? const <AccordMessage>[];
    if (current.any((m) => m.id == message.id)) return;
    state = [...current, message];
  }

  /// Replaces an existing reply (edit result / gateway echo); unknown ids are
  /// ignored.
  void updateReply(AccordMessage message) {
    final next = state?.replaceById(message, (m) => m.id);
    if (next != null) state = next;
  }

  /// Removes a deleted reply; a no-op when [messageId] isn't in this thread
  /// (the gateway delete payload carries no `thread_id`, so deletes fan out to
  /// every open thread on the channel).
  void removeReply(String messageId) {
    final current = state;
    if (current == null || !current.any((m) => m.id == messageId)) return;
    state = current.removeById(messageId, (m) => m.id);
  }
}
