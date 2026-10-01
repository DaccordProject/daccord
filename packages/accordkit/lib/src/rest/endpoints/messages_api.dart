import 'dart:typed_data';

import '../../models/message.dart';
import '../../e2ee/private_chat_encryption.dart';
import '../accord_error.dart';
import '../../models/message_upload.dart';
import '../endpoint_base.dart';
import '../multipart_form.dart';
import '../rest_result.dart';

/// Message operations within a channel: list, create, edit, delete, pin,
/// threads/forum posts, search, and the typing indicator.
class MessagesApi extends EndpointBase {
  final PrivateChatEncryption? encryption;
  final Set<String> _privateChannels = {};

  /// Sticky policy from private-chat UI/API context; the server cannot downgrade it.
  void requireEncryptionFor(String channelId) =>
      _privateChannels.add(channelId);
  MessagesApi(super.rest, {this.encryption});

  Future<bool> _private(String channelId) async {
    if (encryption == null) return false;
    if (_privateChannels.contains(channelId) ||
        encryption!.knowsPrivateChat(channelId)) return true;
    final result = await rest.makeRequest('GET', '/channels/$channelId');
    if (!result.ok || result.data is! Map) {
      throw EncryptionException(result.error?.message ??
          'Cannot determine chat encryption requirements.');
    }
    final private =
        const ['dm', 'group_dm'].contains((result.data as Map)['type']);
    if (private) requireEncryptionFor(channelId);
    return private;
  }

  RestResult _failure(Object e) => RestResult.failure(
      0,
      AccordError(
          code: 'encryption_failed',
          message: e is EncryptionException
              ? e.message
              : 'Unable to encrypt this private message.'));
  Future<RestResult> _decode(RestResult result, {bool array = false}) async {
    if (array) {
      result.deserializeArray(AccordMessage.fromJson);
    } else {
      result.deserialize(AccordMessage.fromJson);
    }
    if (encryption != null && result.ok) {
      if (result.data is AccordMessage) {
        result.data = await encryption!.decrypt(result.data as AccordMessage);
      } else if (result.data is List) {
        final items = (result.data as List).cast<AccordMessage>();
        final keys = <String, Map<String, Map<String, dynamic>>>{};
        final discoveryErrors = <String, Object>{};
        for (final channel in items
            .where((m) => m.isEncrypted)
            .map((m) => m.channelId)
            .toSet()) {
          try {
            keys[channel] =
                await encryption!.participants(channel, requireReady: false);
          } catch (e) {
            discoveryErrors[channel] = e;
          }
        }
        result.data = await Future.wait(items.map((m) => encryption!.decrypt(m,
            participantKeys: keys[m.channelId],
            discoveryError: discoveryErrors[m.channelId])));
      }
    }
    return result;
  }

  /// Lists messages in a channel. Supports `before`/`after`/`around`/`limit`.
  Future<RestResult> list(String channelId,
      {Map<String, dynamic> query = const {}}) async {
    final result = await rest
        .makeRequest('GET', '/channels/$channelId/messages', query: query);
    return _decode(result, array: true);
  }

  /// Fetches a single message by snowflake ID.
  Future<RestResult> fetch(String channelId, String messageId) async {
    final result = await rest.makeRequest(
        'GET', '/channels/$channelId/messages/$messageId');
    return _decode(result);
  }

  /// Creates a message. [data] needs at least `content` or `embeds`; a
  /// `thread_id` makes it a thread reply.
  ///
  /// Not retried on 429: the server enforces channel slowmode (`rate_limit`)
  /// on this route, so a rate limit is a cooldown to show the user, returned
  /// as a failure whose [AccordError.retryAfter] says how long. Exactly one
  /// request is made per call.
  Future<RestResult> create(String channelId, Map<String, dynamic> data) async {
    try {
      if (await _private(channelId)) {
        data = (await encryption!.encrypt(channelId, data)).data;
      }
    } catch (e) {
      return _failure(e);
    }
    final result = await rest.makeRequest(
      'POST',
      '/channels/$channelId/messages',
      body: data,
      retryOnRateLimit: false,
    );
    return _decode(result);
  }

  /// Creates a message with file attachments via multipart/form-data.
  ///
  /// Each entry in [files] is a map with `filename` (String),
  /// `content` (`List<int>`/`Uint8List`), and `content_type` (String).
  ///
  /// On success [RestResult.data] is an [AccordMessageUpload]: the created
  /// message plus the upload IDs an AutoMod-enabled server is still holding
  /// (a `202 Accepted` with `pending_attachments`). A server that published
  /// everything immediately — or predates AutoMod — yields an empty list.
  /// Either way exactly one message was created; callers must not re-send
  /// because the returned attachment list is shorter than what they uploaded.
  ///
  /// A deterministic AutoMod rejection (blocked hash, `reject` rule) is an
  /// ordinary failure (HTTP 400) whose [RestResult.error] carries the
  /// server's reason.
  Future<RestResult> createWithAttachments(
    String channelId,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> files,
  ) async {
    try {
      if (await _private(channelId)) {
        final encrypted =
            await encryption!.encrypt(channelId, data, files: files);
        data = encrypted.data;
        files = encrypted.files;
      }
    } catch (e) {
      return _failure(e);
    }
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
        'POST', '/channels/$channelId/messages/upload', form,
        retryOnRateLimit: false);
    await _decode(result);
    if (result.data is AccordMessage) {
      result.data = AccordMessageUpload(
          message: result.data as AccordMessage,
          pendingAttachmentIds: result.pendingAttachments,
          statusCode: result.statusCode);
    }
    return result;
  }

  /// Edits an existing message.
  Future<RestResult> edit(
      String channelId, String messageId, Map<String, dynamic> data) async {
    try {
      if (await _private(channelId)) {
        final original = await fetch(channelId, messageId);
        if (!original.ok || original.data is! AccordMessage) return original;
        final message = original.data as AccordMessage;
        if (!message.isEncrypted && message.attachments.isNotEmpty) {
          throw const EncryptionException(
              'Re-upload legacy attachments to encrypt them before editing this message.');
        }
        if (message.encryptionError != null) {
          throw EncryptionException(message.encryptionError!);
        }
        data = (await encryption!.encrypt(
                channelId, {...data, 'reply_to': message.replyTo},
                editId: messageId, previousPayload: message.privatePayload))
            .data;
        data.remove('reply_to');
      }
    } catch (e) {
      return _failure(e);
    }
    final result = await rest.makeRequest(
        'PATCH', '/channels/$channelId/messages/$messageId',
        body: data);
    return _decode(result);
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
    return _decode(result, array: true);
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
    return _decode(result, array: true);
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
    return _decode(result, array: true);
  }

  /// Lists top-level posts in a forum channel.
  Future<RestResult> listPosts(String channelId,
      {Map<String, dynamic> query = const {}}) {
    final q = Map<String, dynamic>.from(query)..['top_level'] = 'true';
    return list(channelId, query: q);
  }

  /// Triggers the typing indicator (lasts ~10s). Fire-and-forget, so a
  /// rate-limited call is dropped rather than retried.
  Future<RestResult> typing(String channelId, {String threadId = ''}) {
    final data = <String, dynamic>{};
    if (threadId.isNotEmpty) data['thread_id'] = threadId;
    return rest.makeRequest(
      'POST',
      '/channels/$channelId/typing',
      body: data,
      retryOnRateLimit: false,
    );
  }
}
