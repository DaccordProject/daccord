import '../utils/json_utils.dart';
import '../utils/qualified_id.dart';
import 'attachment.dart';
import 'embed.dart';
import 'reaction.dart';

/// A message in a channel, thread, or DM.
class AccordMessage {
  String id;
  String channelId;
  String? spaceId;
  String authorId;
  String content;
  String type;
  String timestamp;
  Object? editedAt;
  bool tts;
  bool pinned;
  bool mentionEveryone;
  List<String> mentions;
  List<String> mentionRoles;
  List<AccordAttachment> attachments;
  List<AccordEmbed> embeds;
  List<AccordReaction>? reactions;
  String? replyTo;
  int flags;
  Object? components;
  List<String>? stickerIds;
  String? webhookId;
  String? threadId;
  int replyCount;
  Object? lastReplyAt;
  List<String> threadParticipants;
  Object? title;

  /// Home domain for a remote-homed (federated) message, or `null` when the
  /// message is homed on the connected server. Falls back to the domain of a
  /// qualified [authorId]. See [isRemote].
  String? origin;

  AccordMessage({
    this.id = '',
    this.channelId = '',
    this.spaceId,
    this.authorId = '',
    this.content = '',
    this.type = 'default',
    this.timestamp = '',
    this.editedAt,
    this.tts = false,
    this.pinned = false,
    this.mentionEveryone = false,
    List<String>? mentions,
    List<String>? mentionRoles,
    List<AccordAttachment>? attachments,
    List<AccordEmbed>? embeds,
    this.reactions,
    this.replyTo,
    this.flags = 0,
    this.components,
    this.stickerIds,
    this.webhookId,
    this.threadId,
    this.replyCount = 0,
    this.lastReplyAt,
    List<String>? threadParticipants,
    this.title,
    this.origin,
  })  : mentions = mentions ?? [],
        mentionRoles = mentionRoles ?? [],
        attachments = attachments ?? [],
        embeds = embeds ?? [],
        threadParticipants = threadParticipants ?? [];

  factory AccordMessage.fromJson(Map<String, dynamic> d) {
    final m = AccordMessage(
      id: asString(d['id']),
      channelId: asString(d['channel_id']),
      spaceId: asStringOrNull(d['space_id'] ?? d['guild_id']),
      content: asString(d['content']),
      type: asString(d['type'], 'default'),
      timestamp: asString(d['timestamp']),
      editedAt: d['edited_at'] ?? d['edited_timestamp'],
      tts: asBool(d['tts']),
      pinned: asBool(d['pinned']),
      mentionEveryone: asBool(d['mention_everyone']),
      flags: asInt(d['flags']),
      components: d['components'],
      webhookId: asStringOrNull(d['webhook_id']),
      threadId: asStringOrNull(d['thread_id']),
      replyCount: asInt(d['reply_count']),
      lastReplyAt: d['last_reply_at'],
      title: d['title'],
    );

    final rawAuthor = asMap(d['author']);
    m.authorId = rawAuthor != null
        ? asString(rawAuthor['id'])
        : asString(d['author_id']);

    // A remote-homed message carries `origin`; otherwise infer it from a
    // qualified author id or the author's own origin so the UI can flag it.
    m.origin = asStringOrNull(d['origin']) ??
        asStringOrNull(rawAuthor?['origin']) ??
        domainOf(m.authorId);

    for (final u in asList(d['mentions']) ?? const []) {
      final um = asMap(u);
      if (um != null) {
        m.mentions.add(asString(um['id']));
      } else if (u is String) {
        m.mentions.add(u);
      }
    }

    for (final r in asList(d['mention_roles']) ?? const []) {
      m.mentionRoles.add(asString(r));
    }

    for (final a in asList(d['attachments']) ?? const []) {
      final am = asMap(a);
      if (am != null) m.attachments.add(AccordAttachment.fromJson(am));
    }

    for (final e in asList(d['embeds']) ?? const []) {
      final em = asMap(e);
      if (em != null) m.embeds.add(AccordEmbed.fromJson(em));
    }

    final rawReactions = asList(d['reactions']);
    if (rawReactions != null) {
      m.reactions = [
        for (final r in rawReactions)
          if (asMap(r) != null) AccordReaction.fromJson(asMap(r)!),
      ];
    }

    final rawRef = d['reply_to'] ?? d['message_reference'];
    final refMap = asMap(rawRef);
    if (refMap != null) {
      m.replyTo = asStringOrNull(refMap['message_id']);
    } else if (rawRef is String) {
      m.replyTo = rawRef;
    }

    final rawStickers = asList(d['sticker_ids'] ?? d['sticker_items']);
    if (rawStickers != null) {
      m.stickerIds = [
        for (final s in rawStickers)
          asMap(s) != null ? asString(asMap(s)!['id']) : asString(s),
      ];
    }

    for (final p in asList(d['thread_participants']) ?? const []) {
      m.threadParticipants.add(asString(p));
    }

    return m;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'channel_id': channelId,
      'author_id': authorId,
      'content': content,
      'type': type,
      'timestamp': timestamp,
      'tts': tts,
      'pinned': pinned,
      'mention_everyone': mentionEveryone,
      'mentions': mentions,
      'mention_roles': mentionRoles,
      'flags': flags,
      'attachments': toJsonList(attachments),
      'embeds': toJsonList(embeds),
    };
    if (spaceId != null) d['space_id'] = spaceId;
    if (editedAt != null) d['edited_at'] = editedAt;
    if (reactions != null) d['reactions'] = toJsonList(reactions!);
    if (replyTo != null) d['reply_to'] = replyTo;
    if (components != null) d['components'] = components;
    if (stickerIds != null) d['sticker_ids'] = stickerIds;
    if (webhookId != null) d['webhook_id'] = webhookId;
    if (threadId != null) d['thread_id'] = threadId;
    if (replyCount > 0) d['reply_count'] = replyCount;
    if (lastReplyAt != null) d['last_reply_at'] = lastReplyAt;
    if (threadParticipants.isNotEmpty) {
      d['thread_participants'] = threadParticipants;
    }
    if (title != null) d['title'] = title;
    if (origin != null) d['origin'] = origin;
    return d;
  }

  /// Whether this message is homed on a remote (federated) server.
  bool get isRemote => origin != null || isRemoteId(authorId);
}
