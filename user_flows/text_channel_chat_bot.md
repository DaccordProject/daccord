# Text Channel Chat Bot

## Overview

Text channel chat bots are server-side applications that send and receive messages in text channels via the accordserver API. daccord supports bot messages at the data model and gateway layers — bot users have a `bot: bool` flag, messages can carry a `webhook_id`, and the interaction system (slash commands) is wired through the gateway — but the client UI does not yet distinguish bot messages visually or expose any bot-specific interaction features.

## User Steps

1. A bot (running server-side) sends a message to a text channel via the REST API.
2. The accordserver broadcasts a `message.create` gateway event to all connected clients.
3. daccord receives the event, fetches the bot user if not cached, and converts the message to a dictionary.
4. The message appears in the channel's message list, rendered identically to a human message.
5. The user can reply to, react to, or (if they have permission) delete the bot's message using the same controls as any other message.
6. If the bot triggers an `interaction.create` gateway event (e.g., a slash command response), the event is received but silently dropped (no UI).

## Signal Flow

```
Gateway (AccordClient)
│
│  message_create signal (AccordMessage)
│
├──► ClientGateway.on_message_create()
│      │  Fetches bot user if not in _user_cache
│      │  Converts via ClientModels.message_to_dict()
│      │  Appends to _message_cache[channel_id]
│      │
│      └──► AppState.messages_updated.emit(channel_id)
│              │
│              ├──► message_view._on_messages_updated()
│              │      │  Diff or full re-render
│              │      │  Bot message rendered as CozyMessage or CollapsedMessage
│              │      │  No bot badge or special styling applied
│              │      │
│              │      └──► Auto-scroll if at bottom
│              │
│              └──► (other listeners: unread tracking, notification sounds)
│
│  interaction_create signal (AccordInteraction)
│
└──► ClientGateway.on_interaction_create()
       └──► pass  (no-op — no interaction UI)
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/models/user.gd` | `AccordUser` model with `bot: bool` field (line 13) |
| `addons/accordkit/models/message.gd` | `AccordMessage` model with `webhook_id`, `components` fields (lines 24, 26) |
| `addons/accordkit/models/interaction.gd` | `AccordInteraction` model for slash command events |
| `addons/accordkit/models/application.gd` | `AccordApplication` model with `bot_public` flag (line 10) |
| `addons/accordkit/models/permission.gd` | `MANAGE_WEBHOOKS` (line 34) and `USE_COMMANDS` (line 38) permissions |
| `addons/accordkit/rest/endpoints/messages_api.gd` | REST message CRUD including bot-sent messages |
| `addons/accordkit/rest/endpoints/interactions_api.gd` | Interaction response and application command REST endpoints |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway signal definitions: `interaction_create` (line 65) |
| `addons/accordkit/core/accord_client.gd` | Forwards `interaction_create` from gateway to client signal (line 237) |
| `scripts/autoload/client_models.gd` | `user_to_dict()` includes `"bot"` key in output (line 225); `message_to_dict()` builds author dict with bot field |
| `scripts/autoload/client_gateway.gd` | `on_message_create()` (line 169): caches bot messages same as human; `on_interaction_create()` (line 455): no-op |
| `scripts/autoload/client_gateway_events.gd` | `on_interaction_create()` (line 82): no-op handler |
| `scenes/messages/cozy_message.gd` | Renders bot messages identically to human messages (no bot indicator) |
| `scenes/messages/message_content.gd` | Renders embeds from bot messages (lines 95-110) |
| `scenes/messages/message_view.gd` | Message list rendering — no bot-specific logic |

## Implementation Details

### Data Model — Bot Users

`AccordUser` (line 13) carries `var bot: bool = false`, parsed from server JSON at line 30. The `to_dict()` method includes it at line 43.

`ClientModels.user_to_dict()` (line 225) passes `"bot": user.bot` through to the UI dictionary. This means every message author dict in the cache has a `"bot"` key available for display — it's just not consumed by any UI component.

### Data Model — Bot Messages

`AccordMessage` has fields relevant to bot-originated messages:
- `webhook_id` (line 26): Set when a message was sent via a webhook (bot integration). Parsed at lines 112-115, serialized at lines 180-181.
- `components` (line 24): Interactive message components (buttons, select menus). Parsed at line 100, serialized at line 176-177. Never rendered in the UI.
- `type` (line 11): Defaults to `"default"`. System messages (e.g., bot join announcements) use other types and render as italic gray text in `message_content.gd` (line 35-36).

`ClientModels.message_to_dict()` (lines 298-435) does not include `webhook_id` in its output dictionary. The `components` field is also omitted.

### Data Model — Interactions

`AccordInteraction` (line 1-91) models slash command and component interactions. Fields include `type` (default `"command"`), `application_id`, `data` (command payload), `channel_id`, `member_id`/`user_id`, and an optional `message` (for component interactions on existing messages).

The `InteractionsApi` provides full REST support:
- `list_global_commands()` / `create_global_command()` / `update_global_command()` / `delete_global_command()` — manage global slash commands
- `list_space_commands()` / `create_space_command()` — manage per-space commands
- `respond()` — send initial interaction response
- `edit_original()` / `delete_original()` — modify the response
- `followup()` — send follow-up messages

### Data Model — Applications

`AccordApplication` (lines 1-45) models a bot application with `id`, `name`, `icon`, `description`, `bot_public`, `owner_id`, and `flags`.

### Gateway Handling

Bot messages arrive as standard `message.create` events and flow through the same path as human messages. `on_message_create()` (line 169) fetches the author from the user cache (or from the server if missing), converts via `ClientModels.message_to_dict()`, and appends to the channel's message cache. The `bot` field on the cached user dict is preserved but never inspected.

The `interaction.create` event is wired in `connect_signals()` (line 74-75) but the handler is a no-op (line 455-456): `pass # No interaction UI; wired to prevent silent drop`.

### Message Rendering

Bot messages are rendered through the same pipeline as human messages:
1. `message_view._load_messages()` or `_diff_messages()` instantiates `CozyMessageScene` or `CollapsedMessageScene`
2. `cozy_message.setup()` (line 37-92) reads `data.author` and sets display name, color, and avatar — no check for `author.get("bot", false)`
3. `message_content.setup()` (line 31-115) renders text via `markdown_to_bbcode()`, embeds, attachments, and reactions — all of which work for bot-sent content
4. Rich embeds from bots render correctly through the embed component (lines 95-110)

### Permissions

`AccordPermission` defines bot-relevant permission strings:
- `MANAGE_WEBHOOKS` (line 34): Required to create/manage webhook integrations
- `USE_COMMANDS` (line 38): Required to use application commands (slash commands)

These are checked server-side by accordserver but daccord does not gate any UI on them (since there is no interaction UI).

### Typing Indicator

Bots that call `POST /channels/{channel_id}/typing` trigger the same typing indicator as human users. The gateway handler `on_typing_start()` (line 392-413) resolves the display name from the user cache and emits `AppState.typing_started` — no bot filtering is applied.

## Implementation Status

- [x] Bot flag (`bot: bool`) on AccordUser model
- [x] Bot flag passed through user_to_dict → message author dict pipeline
- [x] Webhook ID support on AccordMessage model
- [x] Interactive components field on AccordMessage model (parsed but not rendered)
- [x] AccordInteraction model with full from_dict/to_dict
- [x] InteractionsApi REST endpoints (global/space commands, responses, follow-ups)
- [x] Gateway `interaction_create` event wired (handler is no-op)
- [x] AccordApplication model with bot_public flag
- [x] Bot messages render in message list (text, embeds, attachments, reactions)
- [x] Context menu (Reply, Edit, Delete) works on bot messages
- [x] Typing indicator works for bot users
- [x] Unread/mention tracking applies to bot messages
- [x] Notification sounds play for bot messages
- [ ] Bot badge/indicator next to author name
- [ ] "BOT" tag styling (Discord-style colored pill)
- [ ] Verified Bot badge for public bots (USER_FLAGS bit 65536, defined in `ClientModels.USER_FLAGS` line 23)
- [ ] Slash command input UI (e.g., "/" prefix autocomplete in composer)
- [ ] Component rendering (buttons, select menus, action rows) in messages
- [ ] Interaction response display (ephemeral messages, deferred loading states)
- [ ] Webhook ID display or attribution in message UI
- [ ] Webhook management UI (create/edit/delete webhooks for a channel)
- [ ] Application command registration UI (admin panel)
- [ ] Bot-specific context menu entries (e.g., "View Bot Info")

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No bot badge in message author display | Medium | `cozy_message.gd` line 40 sets author label text but does not check `user.get("bot", false)` to append a badge or tag |
| No visual distinction for bot messages | Medium | Bot messages are indistinguishable from human messages; no colored pill, icon, or styling |
| `webhook_id` not included in message dict | Low | `ClientModels.message_to_dict()` (lines 414-435) omits `webhook_id` — UI cannot tell if a message came from a webhook vs. direct bot post |
| `components` field never rendered | High | `AccordMessage.components` (line 24) is parsed from server JSON but `message_to_dict()` does not pass it through and no UI renders buttons, select menus, or action rows |
| Interaction events are silently dropped | High | `on_interaction_create()` (line 455) is a no-op; slash command responses and component interactions have no client-side handling |
| No slash command input | High | Composer (`composer.gd`) has no "/" prefix detection, no command autocomplete, and no way to invoke application commands |
| No ephemeral message support | Medium | Interaction responses can be ephemeral (only visible to invoking user) but the client has no concept of ephemeral messages |
| Verified Bot flag unused | Low | `USER_FLAGS[65536] = "Verified Bot"` is defined in `ClientModels` (line 23) but `get_user_badges()` output is not displayed in message headers |
| No application command management | Low | `InteractionsApi` supports command CRUD but no admin UI exposes it |
