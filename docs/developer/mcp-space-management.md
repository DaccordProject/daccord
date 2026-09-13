# Space setup through the local MCP server

Enable Developer Mode and the Client MCP server, then opt into **Space
management** under **Exposed tool groups**. The `space_management` group is off
by default. Enabling it permits space setup and channel deletion for the signed-in
user; the server still enforces that user's permissions.

These tools use the **active server and account**. Select the intended connection
before calling them. IDs must belong to that server. Tool schemas are available
through MCP `tools/list`.

| Tool | Required arguments | Behavior |
| --- | --- | --- |
| `create_space` | `name` | Creates a space; optional `description` and `icon`. Returns `space`. |
| `update_space` | `space_id` and at least one setting | Requires `manage_space`. Returns `space`. |
| `create_channel` | `space_id`, `name`, `type` | Requires `manage_channels`. Returns `channel`. |
| `update_channel` | `space_id`, `channel_id` and at least one field | Requires `manage_channels`. Returns `channel`. |
| `delete_channel` | `space_id`, `channel_id`, `confirm: true` | Requires `manage_channels`; permanent. Returns `deleted_channel_id`. |
| `reorder_channels` | `space_id`, `channels` | Requires `manage_channels`. Entries contain `id`, `position`, and optional `parent_id`. Returns refreshed `channels`. |

`update_space` supports `name`, `description`, `icon`, `banner`,
`verification_level` (`none`, `low`, `medium`, `high`), `default_notifications`
(`all`, `mentions`), `nsfw_level` (`default`, `moderate`, `explicit`),
`explicit_content_filter` (`disabled`, `no_role`, `everyone`), `public`,
`allow_guest_access`, `rules_channel_id`, and `system_channel_id`.

Image values are base64 `data:image/...;base64,...` strings using PNG, JPEG, GIF,
or WebP. Use `null` to clear an image, description, or rules/system channel.
Setting a banner after creation uses `update_space`. Image cache revisions are
updated immediately so existing widgets display the changed media.

Channel fields are `name`, `type`, `parent_id`, `topic`, `position`, `nsfw`, and
`rate_limit` (slowmode seconds, 0–21600). Creation supports `category`, `text`,
`announcement`, `forum`, and `voice`. Existing types may change only between
`text` and `announcement`, matching the management UI. Use `parent_id: null` to
move a channel to the root, or `topic: null` to clear its topic. Parent IDs must
refer to categories in the same space; categories cannot be nested.

For example, after `create_space` returns a space ID:

```json
{"name":"create_channel","arguments":{"space_id":"SPACE_ID","name":"Gaming","type":"category"}}
```

Use its returned category ID in a subsequent call:

```json
{"name":"create_channel","arguments":{"space_id":"SPACE_ID","name":"general","type":"text","parent_id":"CATEGORY_ID","topic":"Find your next game","rate_limit":5}}
```

Then configure the returned text channel as the system channel:

```json
{"name":"update_space","arguments":{"space_id":"SPACE_ID","system_channel_id":"CHANNEL_ID","default_notifications":"mentions"}}
```

Only supplied fields change. Unknown fields, invalid enum values, malformed
images, duplicate reorder IDs, and missing deletion confirmation produce
`validation_error` with a field where applicable. Permission errors name the
required permission. REST failures preserve the server's error code and HTTP
status (`_status`). A successful mutation updates local caches; if a subsequent
channel refresh fails, the response includes `ok: true` and a `warning` so clients
do not repeat a successful write. If a successful server response lacks its
entity, inspect `list_spaces`, `get_space`, or `list_channels` before retrying.
Space deletion is deliberately not exposed.
