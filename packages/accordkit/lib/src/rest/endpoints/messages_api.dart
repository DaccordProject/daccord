import 'dart:typed_data';

import '../../models/message.dart';
import '../endpoint_base.dart';
import '../multipart_form.dart';
import '../rest_result.dart';

/// Message operations within a channel: list, create, edit, delete, pin,
/// threads/forum posts, search, and the typing indicator.
class MessagesApi extends EndpointBase {
  MessagesApi(super.rest);

  /// Lists messages in a channel. Supports `before`/`after`/`around`/`limit`.
  Future<RestResult> list(String channelId,
      {Map<String, dynamic> query = const {}}) async {
    final result = await rest
        .makeRequest('GET', '/channels/$channelId/messages', query: query);
    return result.deserializeArray(AccordMessage.fromJson);
  }

  /// Fetches a single message by snowflake ID.
  Future<RestResult> fetch(String channelId, String messageId) async {
    final result = await rest.makeRequest(
        'GET', '/channels/$channelId/messages/$messageId');
    return result.deserialize(AccordMessage.fromJson);
  }

  /// Creates a message. [data] needs at least `content` or `embeds`.
  Future<RestResult> create(String channelId, Map<String, dynamic> data) async {
    final result = await rest
        .makeRequest('POST', '/channels/$channelId/messages', body: data);
    return result.deserialize(AccordMessage.fromJson);
  }

  /// Creates a message with file attachments via multipart/form-data.
  ///
  /// Each entry in [files] is a map with `filename` (String),
  /// `content` (`List<int>`/`Uint8List`), and `content_type` (String).
  Future<RestResult> createWithAttachments(
    String channelId,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> files,
  ) async {
    final form = MultipartForm();
    form.addJson('payload_json', data);
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final name = 'files[$i]';
      final filename = (file['filename'] ?? 'attachment').toString();
      final content = (file['content'] ?? Uint8List(0)) as List<int>;
      final ct =
          (file['content_type'] ?? 'application/octet-stream').toString();
      form.addFile(name, filename, content, contentType: ct);
    }
    final result = await rest.makeMultipartRequest(
        'POST', '/channels/$channelId/messages/upload', form);
    return result.deserialize(AccordMessage.fromJson);
  }

  /// Edits an existing message.
  Future<RestResult> edit(
      String channelId, String messageId, Map<String, dynamic> data) async {
    final result = await rest.makeRequest(
        'PATCH', '/channels/$channelId/messages/$messageId',
        body: data);
    return result.deserialize(AccordMessage.fromJson);
  }

  /// Deletes a single message.
  Future<RestResult> delete(String channelId, String messageId) {
    return rest.makeRequest(
        'DELETE', '/channels/$channelId/messages/$messageId');
  }

  /// Bulk-deletes 2–100 messages. Messages older than 14 days are rejected.
  Future<RestResult> bulkDelete(String channelId, List<String> messageIds) {
    return rest.makeRequest(
      'POST',
      '/channels/$channelId/messages/bulk-delete',
      body: {'messages': messageIds},
    );
  }

  /// Lists all pinned messages in a channel.
  Future<RestResult> listPins(String channelId) async {
    final result = await rest.makeRequest('GET', '/channels/$channelId/pins');
    return result.deserializeArray(AccordMessage.fromJson);
  }

  /// Pins a message (max 50 per channel).
  Future<RestResult> pin(String channelId, String messageId) {
    return rest.makeRequest('PUT', '/channels/$channelId/pins/$messageId');
  }

  /// Unpins a message.
  Future<RestResult> unpin(String channelId, String messageId) {
    return rest.makeRequest('DELETE', '/channels/$channelId/pins/$messageId');
  }

  /// Searches messages within a space.
  Future<RestResult> search(String spaceId, String queryStr,
      {Map<String, dynamic> query = const {}}) async {
    final q = Map<String, dynamic>.from(query)..['query'] = queryStr;
    final result = await rest
        .makeRequest('GET', '/spaces/$spaceId/messages/search', query: q);
    return result.deserializeArray(AccordMessage.fromJson);
  }

  /// Lists thread replies for a parent message.
  Future<RestResult> listThread(String channelId, String parentMessageId,
      {Map<String, dynamic> query = const {}}) {
    final q = Map<String, dynamic>.from(query)..['thread_id'] = parentMessageId;
    return list(channelId, query: q);
  }

  /// Fetches thread metadata for a parent message.
  Future<RestResult> getThreadInfo(String channelId, String messageId) {
    return rest.makeRequest(
        'GET', '/channels/$channelId/messages/$messageId/threads');
  }

  /// Lists all active threads in a channel.
  Future<RestResult> listActiveThreads(String channelId) async {
    final result =
        await rest.makeRequest('GET', '/channels/$channelId/threads');
    return result.deserializeArray(AccordMessage.fromJson);
  }

  /// Lists top-level posts in a forum channel.
  Future<RestResult> listPosts(String channelId,
      {Map<String, dynamic> query = const {}}) {
    final q = Map<String, dynamic>.from(query)..['top_level'] = 'true';
    return list(channelId, query: q);
  }

  /// Triggers the typing indicator (lasts ~10s).
  Future<RestResult> typing(String channelId, {String threadId = ''}) {
    final data = <String, dynamic>{};
    if (threadId.isNotEmpty) data['thread_id'] = threadId;
    return rest.makeRequest('POST', '/channels/$channelId/typing', body: data);
  }
}
