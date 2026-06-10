import '../utils/json_utils.dart';
import 'permission_overwrite.dart';
import 'user.dart';

/// A channel within a space or a DM/group channel.
class AccordChannel {
  String id;
  String type;
  String? spaceId;
  String? name;
  String? topic;
  Object? position;
  String? parentId;
  bool nsfw;
  Object? rateLimit;
  Object? bitrate;
  Object? userLimit;
  List<AccordUser>? recipients;
  String? ownerId;
  String? lastMessageId;
  List<AccordPermissionOverwrite> permissionOverwrites;
  bool allowAnonymousRead;
  Object? archived;
  Object? autoArchiveAfter;
  String createdAt;

  AccordChannel({
    this.id = '',
    this.type = 'text',
    this.spaceId,
    this.name,
    this.topic,
    this.position,
    this.parentId,
    this.nsfw = false,
    this.rateLimit,
    this.bitrate,
    this.userLimit,
    this.recipients,
    this.ownerId,
    this.lastMessageId,
    List<AccordPermissionOverwrite>? permissionOverwrites,
    this.allowAnonymousRead = false,
    this.archived,
    this.autoArchiveAfter,
    this.createdAt = '',
  }) : permissionOverwrites = permissionOverwrites ?? [];

  factory AccordChannel.fromJson(Map<String, dynamic> d) {
    final c = AccordChannel(
      id: asString(d['id']),
      type: asString(d['type'], 'text'),
      spaceId: asStringOrNull(d['space_id'] ?? d['guild_id']),
      name: d['name'] as String?,
      topic: d['topic'] as String?,
      position: d['position'],
      parentId: asStringOrNull(d['parent_id']),
      nsfw: asBool(d['nsfw']),
      rateLimit: d['rate_limit'] ?? d['rate_limit_per_user'],
      bitrate: d['bitrate'],
      userLimit: d['user_limit'],
      ownerId: asStringOrNull(d['owner_id']),
      lastMessageId: asStringOrNull(d['last_message_id']),
      allowAnonymousRead: asBool(d['allow_anonymous_read']),
      archived: d['archived'],
      autoArchiveAfter: d['auto_archive_after'] ?? d['auto_archive_duration'],
      createdAt: asString(d['created_at']),
    );

    final rawRecipients = asList(d['recipients']);
    if (rawRecipients != null) {
      c.recipients = [
        for (final r in rawRecipients)
          if (asMap(r) != null) AccordUser.fromJson(asMap(r)!),
      ];
    }

    final rawOverwrites = asList(d['permission_overwrites']) ?? const [];
    for (final o in rawOverwrites) {
      final m = asMap(o);
      if (m != null) {
        c.permissionOverwrites.add(AccordPermissionOverwrite.fromJson(m));
      }
    }
    return c;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'type': type,
      'nsfw': nsfw,
      'created_at': createdAt,
      'permission_overwrites': toJsonList(permissionOverwrites),
    };
    if (spaceId != null) d['space_id'] = spaceId;
    if (name != null) d['name'] = name;
    if (topic != null) d['topic'] = topic;
    if (position != null) d['position'] = position;
    if (parentId != null) d['parent_id'] = parentId;
    if (rateLimit != null) d['rate_limit'] = rateLimit;
    if (bitrate != null) d['bitrate'] = bitrate;
    if (userLimit != null) d['user_limit'] = userLimit;
    if (recipients != null) d['recipients'] = toJsonList(recipients!);
    if (ownerId != null) d['owner_id'] = ownerId;
    if (lastMessageId != null) d['last_message_id'] = lastMessageId;
    if (allowAnonymousRead) d['allow_anonymous_read'] = true;
    if (archived != null) d['archived'] = archived;
    if (autoArchiveAfter != null) d['auto_archive_after'] = autoArchiveAfter;
    return d;
  }
}
