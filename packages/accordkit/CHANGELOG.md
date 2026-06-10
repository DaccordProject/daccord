# Changelog

## 2.0.0

- Initial Dart release. Port of the GDScript AccordKit addon.
- REST client with all endpoint groups (users, spaces, channels, messages,
  members, roles, bans, reports, invites, emojis, soundboard, reactions,
  interactions, plugins, applications, auth, voice, audit logs, admin,
  directory).
- Gateway WebSocket client with IDENTIFY/RESUME handshake, heartbeating,
  automatic reconnect with backoff, and typed event streams.
- Data models with `fromJson`/`toJson`.
- Voice manager, CDN/snowflake/permission/intent helpers, multipart uploads,
  and cursor pagination.
