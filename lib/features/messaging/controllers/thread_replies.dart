import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/history_request.dart';
import 'package:bonfire/features/messaging/utils/send_cooldown.dart';
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
    _history.reset();
    ref.onDispose(_history.reset);
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

  final _history = HistoryRequests();

  bool _owns(HistoryRequest request, AccordClient client) =>
      ref.mounted &&
      _history.owns(request) &&
      ref.isCurrentAccordClient(serverKey, client);

  Future<void> _load(AccordClient client) async {
    if (!ref.mounted || !ref.isCurrentAccordClient(serverKey, client)) return;
    final request = _history.begin();
    try {
      final result = await client.messages.listThread(channelId, rootId);
      if (!_owns(request, client)) return;
      final replies = result.listOrLog<AccordMessage>(
        'replies for $channelId thread $rootId',
      );
      if (replies == null) {
        // Settle an initial failure without discarding live rows or the cache
        // the user is reading during a failed reconnect refresh.
        state ??= const [];
        return;
      }
      state = _history.reconcile(
        replies.where((m) => m.id != rootId),
        state ?? const [],
        prependLive: false,
      );
    } finally {
      if (_owns(request, client)) _history.finish(request);
    }
  }

  /// Re-fetches the reply list, replacing the cache in place (no flash back to
  /// the loading state). Used after a gateway re-identify: a fresh session gets
  /// no event replay, so anything that happened while disconnected is missing.
  Future<void> reload(AccordClient client) => _load(client);

  /// Sends [content] as a reply into this thread (`thread_id` = root).
  /// Optimistically appends the created message (the gateway echo is then
  /// deduped by [addReply]). Returns true on success.
  Future<bool> send(AccordClient client, String content) async {
    return await sendDetailed(client, content) == null;
  }

  Future<SendFailure?> sendDetailed(AccordClient client, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const SendFailure('Reply is empty.');
    final result = await client.messages.create(channelId, {
      'content': trimmed,
      'thread_id': rootId,
    });
    if (!ref.mounted) return const SendFailure('Thread was closed.');
    final message = result.data;
    if (!result.ok || message is! AccordMessage) {
      debugPrint('Failed to reply in thread $rootId: ${result.error}');
      return SendFailure.fromResult(result, 'Failed to send reply');
    }
    addReply(message);
    return null;
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
    _history.add(message);
    state = [...current, message];
  }

  /// Replaces an existing reply (edit result / gateway echo); unknown ids are
  /// ignored.
  void updateReply(AccordMessage message) {
    _history.update(message);
    final next = state?.replaceById(message, (m) => m.id);
    if (next != null) state = next;
  }

  /// Removes a deleted reply; a no-op when [messageId] isn't in this thread
  /// (the gateway delete payload carries no `thread_id`, so deletes fan out to
  /// every open thread on the channel).
  void removeReply(String messageId) {
    _history.remove(messageId);
    final current = state;
    if (current == null || !current.any((m) => m.id == messageId)) return;
    state = current.removeById(messageId, (m) => m.id);
  }
}
