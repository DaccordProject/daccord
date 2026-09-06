part of '../mcp_tools.dart';

extension _McpToolSerializers on McpTools {
  // ── lookups ─────────────────────────────────────────────────────────────

  /// The connection key owning [spaceId], scanning every connected server's
  /// cached space list (falling back to the active key when the shared spaces
  /// controller has it but the rail cache hasn't caught up).
  String? _serverKeyForSpace(String spaceId) {
    final connections = ref.read(connectionsControllerProvider);
    for (final c in connections.connections) {
      if (c.spaces.any((s) => s.id == spaceId)) return c.key;
    }
    final spaces = ref.read(spacesControllerProvider);
    if (spaces != null && spaces.any((s) => s.id == spaceId)) {
      return connections.activeKey;
    }
    return null;
  }

  /// The space owning [channelId], scanning loaded channel lists.
  String? _spaceForChannel(String channelId) {
    final spaces = ref.read(spacesControllerProvider) ?? const [];
    for (final s in spaces) {
      final channels = ref.read(
        accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', s.id),
      );
      if (channels != null && channels.any((c) => c.id == channelId)) {
        return s.id;
      }
    }
    return null;
  }

  /// The channel of a loaded message [messageId] (only channels the UI has
  /// opened are searchable — mirrors the reference's in-memory message cache).
  String? _channelForMessage(String messageId) {
    for (final key in activeMessageChannels) {
      final messages = ref.read(
        accordMessagesControllerProvider(key.serverKey, key.channelId),
      );
      if (messages != null && messages.any((m) => m.id == messageId)) {
        return key.channelId;
      }
    }
    return null;
  }

  // ── serializers (curated, snake_case — mirror the reference shapes) ────────

  Map<String, dynamic> _spaceBrief(AccordSpace s) => {
    'id': s.id,
    'name': s.name,
    'owner_id': s.ownerId,
    'member_count': s.memberCount ?? 0,
  };

  Map<String, dynamic> _spaceFull(AccordSpace s) => {
    'id': s.id,
    'name': s.name,
    'slug': s.slug,
    'description': s.description ?? '',
    'owner_id': s.ownerId,
    'member_count': s.memberCount ?? 0,
    'public': s.public,
    'role_count': s.roles.length,
    'rules_channel_id': s.rulesChannelId ?? '',
  };

  Map<String, dynamic> _channelBrief(AccordChannel c) => {
    'id': c.id,
    'name': c.name ?? '',
    'type': c.type,
    'parent_id': c.parentId ?? '',
    'topic': c.topic ?? '',
    'position': c.position ?? 0,
    'nsfw': c.nsfw,
  };

  Map<String, dynamic> _memberBrief(AccordMember m) => {
    'id': m.userId,
    'username': m.user?.username ?? '',
    'display_name': accordMemberName(m, fallback: ''),
    'roles': m.roles,
  };

  Map<String, dynamic> _roleFull(AccordRole r) => {
    'id': r.id,
    'name': r.name,
    'color': r.color,
    'hoist': r.hoist,
    'position': r.position,
    'permissions': [for (final p in r.permissions) p.toString()],
    'managed': r.managed,
    'mentionable': r.mentionable,
  };

  Map<String, dynamic> _overwriteBrief(Object? o) {
    final m = o is Map ? o : const {};
    return {
      'id': (m['id'] ?? '').toString(),
      'type': (m['type'] ?? 'role').toString(),
      'allow': [
        for (final p in (m['allow'] as List? ?? const [])) p.toString(),
      ],
      'deny': [for (final p in (m['deny'] as List? ?? const [])) p.toString()],
    };
  }

  Map<String, dynamic> _messageBrief(AccordMessage m) => {
    'id': m.id,
    'content': m.content,
    'author_id': m.authorId,
    'channel_id': m.channelId,
    'timestamp': m.timestamp,
    'edited': m.editedAt != null,
    'reply_to': m.replyTo ?? '',
    'pinned': m.pinned,
  };

  Map<String, dynamic> _userBrief(AccordUser u) => {
    'id': u.id,
    'username': u.username,
    'display_name': u.displayName ?? '',
    'avatar': u.avatar ?? '',
    'is_admin': u.isAdmin,
    'bot': u.bot,
  };

  /// Unlike accordkit's `asBool`, also accepts the string `"true"` — MCP
  /// hosts routinely pass flags as strings.
  bool _asBool(Object? v) {
    if (v is bool) return v;
    return '$v'.toLowerCase() == 'true';
  }

  /// Coerces an arg into a list of permission id strings, or null when the
  /// caller didn't supply a list (so the field is left untouched on update).
  List<String>? _permList(Object? v) {
    if (v is List) return [for (final e in v) e.toString()];
    return null;
  }
}
