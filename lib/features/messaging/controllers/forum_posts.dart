import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'forum_posts.g.dart';

/// Forum channels that currently have a live posts controller (an open forum
/// board). The gateway handler consults this so it can route top-level message
/// events into open boards — and only into channels that really are forums,
/// since only forum channels ever build this controller. Mirrors
/// `activeMessageChannels`.
final Set<String> activeForumChannels = <String>{};

/// A forum channel's top-level posts (thread roots), keyed by channel ID, in
/// server order (the board sorts for display). Self-loads via
/// `messages.listPosts` the first time it's watched (once logged in) and is
/// kept in sync by top-level message create/update/delete gateway events.
/// `null` means "not loaded yet".
@Riverpod(keepAlive: true)
class ForumPostsController extends _$ForumPostsController {
  @override
  List<AccordMessage>? build(String channelId) {
    activeForumChannels.add(channelId);
    ref.onDispose(() => activeForumChannels.remove(channelId));

    final client = ref.watchAccordClient();
    if (client != null) {
      _load(client);
    }
    return null;
  }

  Future<void> _load(AccordClient client) async {
    final result = await client.messages.listPosts(channelId);
    final data = result.data;
    if (!result.ok || data is! List) {
      debugPrint('Failed to load forum posts for $channelId: ${result.error}');
      // Settle on empty rather than spin forever (matches the previous view
      // behavior); pull-to-refresh or a re-identify [reload] retries.
      state = const [];
      return;
    }
    state = data.whereType<AccordMessage>().toList();
  }

  /// Re-fetches the post list, replacing the cache in place (no flash back to
  /// the loading state). Used by pull-to-refresh and after a gateway
  /// re-identify, when missed events make the cache stale.
  Future<void> reload(AccordClient client) => _load(client);

  /// Deletes post [postId] via `messages.delete`, removing it from the board
  /// on success. Returns true on success.
  Future<bool> delete(AccordClient client, String postId) async {
    final result = await client.messages.delete(channelId, postId);
    if (!result.ok) {
      debugPrint('Failed to delete post $postId: ${result.error}');
      return false;
    }
    removePost(postId);
    return true;
  }

  /// Pins or unpins [post] (based on its current flag), flipping the cached
  /// flag once the request succeeds (matching the previous board behavior —
  /// not optimistic). Returns true on success.
  Future<bool> togglePin(AccordClient client, AccordMessage post) async {
    final pinned = post.pinned;
    final result = pinned
        ? await client.messages.unpin(channelId, post.id)
        : await client.messages.pin(channelId, post.id);
    if (!result.ok) {
      debugPrint(
          'Failed to ${pinned ? 'unpin' : 'pin'} post ${post.id}: ${result.error}');
      return false;
    }
    _setPinned(post.id, !pinned);
    return true;
  }

  void _setPinned(String postId, bool pinned) {
    final current = state;
    if (current == null) return;
    final post = current.firstWhereOrNull((m) => m.id == postId);
    if (post == null || post.pinned == pinned) return;
    post.pinned = pinned;
    state = [...current];
  }

  /// Adds a newly-created root post (composer result or gateway echo — deduped
  /// by id). Replies (`thread_id` set) never belong on the board.
  void addPost(AccordMessage post) {
    if (post.threadId != null) return;
    final current = [...(state ?? const <AccordMessage>[])];
    if (current.any((m) => m.id == post.id)) return;
    current.insert(0, post);
    state = current;
  }

  /// Replaces an existing post (edit result / thread-root edit / gateway
  /// echo); unknown ids are ignored.
  void updatePost(AccordMessage post) {
    final current = state;
    if (current == null) return;
    final index = current.indexWhere((m) => m.id == post.id);
    if (index < 0) return;
    final copy = [...current];
    copy[index] = post;
    state = copy;
  }

  /// Removes a deleted post; a no-op when [postId] isn't a root post here
  /// (message deletes in a forum channel may be thread replies).
  void removePost(String postId) {
    final current = state;
    if (current == null || !current.any((m) => m.id == postId)) return;
    state = current.where((m) => m.id != postId).toList();
  }
}
