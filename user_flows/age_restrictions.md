# Age Restrictions

Priority: 54
Depends on: Moderation

## Overview

Age restrictions gate access to NSFW content behind a consent interstitial. When a user attempts to view a channel marked as NSFW or enters a space with an elevated `nsfw_level`, the client should show a confirmation screen before revealing content. Currently, the data model supports NSFW flags on both channels (`nsfw: bool`) and spaces (`nsfw_level: String`), and the client renders a visual NSFW indicator on channel items, but there is no access gate or consent interstitial — NSFW content is freely accessible to all authenticated users.

## User Steps

### Viewing an NSFW channel (proposed flow)
1. User clicks an NSFW channel in the sidebar (shown with a red-tinted icon).
2. If the user has not previously acknowledged NSFW content on this server, a **consent interstitial** appears: "This channel is marked as NSFW. You must be 18 or older to view this content."
3. User clicks "I understand" to proceed or "Go back" to return to the previous channel.
4. The acknowledgement is cached per server in `Config` so the prompt does not reappear.
5. On subsequent visits, the NSFW channel loads messages normally.

### Entering an NSFW space (proposed flow)
1. User selects a space whose `nsfw_level` is `"explicit"` or `"age_restricted"`.
2. The same consent interstitial appears (if not already acknowledged for this server).
3. After acknowledgement, the space loads normally. Without acknowledgement, the space content is hidden behind a placeholder.

### Admin: toggling NSFW on a channel (implemented)
1. Admin right-clicks a channel in the sidebar and selects "Edit Channel" (requires `manage_channels` permission, `channel_item.gd` line 95).
2. The Channel Edit dialog opens (`channel_edit_dialog.gd`).
3. Admin toggles the "NSFW" checkbox (`_nsfw_check`, line 13).
4. Admin clicks "Save" — sends `PATCH /channels/{id}` with `{"nsfw": true/false}` (line 44).
5. On success, the channel item re-renders with or without the red icon tint.

### Admin: setting space nsfw_level (not implemented)
1. Admin opens Space Settings (via space icon context menu or banner dropdown).
2. No `nsfw_level` dropdown exists in the Space Settings dialog (`space_settings_dialog.gd`).
3. The `nsfw_level` field is stored in the `AccordSpace` model (line 30) but never exposed in any admin UI.

## Signal Flow

```
Current (NSFW visual indicator only):
  Client.connect_server()
    --> AccordClient fetches channels
    --> AccordChannel.from_dict() parses nsfw field    (channel.gd:41)
    --> ClientModels.channel_to_dict() includes nsfw   (client_models.gd:286-287)
    --> channel_item.setup() reads data["nsfw"]        (channel_item.gd:74)
    --> type_icon.modulate = error color (red tint)    (channel_item.gd:75)

Implemented (NSFW consent gate):
  User clicks NSFW channel
    --> channel_item.channel_pressed signal
    --> channel_list._on_channel_pressed(channel_id)      (channel_list.gd:194)
    --> Check: ch_data.get("nsfw", false)
    --> Check: Client.is_nsfw_acked(_current_space_id)
        |
        +--> Yes: proceed normally (_set_active_channel + channel_selected.emit)
        |
        +--> No: _show_nsfw_gate(channel_id)
              --> NsfwGateDialog instantiated
              --> User clicks "I understand"
              --> Config.set_nsfw_ack(base_url) stores per-server ack
              --> Re-enters _on_channel_pressed (ack check passes)

  User selects NSFW space (nsfw_level "age_restricted" or "explicit")
    --> guild_bar.space_selected signal
    --> sidebar._on_space_selected(space_id)               (sidebar.gd:68)
    --> Check: space_data.nsfw_level in ["age_restricted", "explicit"]
    --> Check: Client.is_nsfw_acked(space_id)
        |
        +--> Yes: proceed normally (load_space + select_space)
        |
        +--> No: _show_nsfw_gate_for_space(space_id)
              --> NsfwGateDialog instantiated
              --> User clicks "I understand"
              --> Config.set_nsfw_ack(base_url)
              --> Re-enters _on_space_selected (ack check passes)

Admin NSFW toggle:
  channel_item._on_edit_channel()
    --> ChannelEditDialog.setup(channel_data)
    --> _nsfw_check.button_pressed = channel["nsfw"]   (channel_edit_dialog.gd:33)
    --> User toggles checkbox, clicks Save
    --> Client.admin.update_channel(id, {"nsfw": true}) (channel_edit_dialog.gd:44-47)
    --> Gateway: channel_update event
    --> channel_item re-renders with new nsfw state
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/models/channel.gd` | `nsfw: bool` field (line 13), parsed from server in `from_dict()` (line 41) |
| `addons/accordkit/models/space.gd` | `nsfw_level: String` field (line 30), `explicit_content_filter: String` (line 18) |
| `scripts/autoload/client_models.gd` | `channel_to_dict()` passes `nsfw` flag to UI (lines 286-287) |
| `scenes/sidebar/channels/channel_item.gd` | NSFW red tint on channel icon (lines 73-77), preserves tint across hover/active/mute states (lines 123-146) |
| `scenes/admin/channel_edit_dialog.gd` | NSFW checkbox in channel edit UI (line 13), sent in save payload (line 44) |
| `scenes/admin/channel_edit_dialog.tscn` | Scene with NsfwRow/NsfwCheck nodes |
| `scenes/admin/nsfw_gate_dialog.gd` | NSFW consent interstitial dialog — emits `acknowledged` signal |
| `scenes/admin/nsfw_gate_dialog.tscn` | Scene for the NSFW gate dialog |
| `scenes/sidebar/channels/channel_list.gd` | NSFW gate check in `_on_channel_pressed()`, prefers non-NSFW in auto-select |
| `scenes/sidebar/sidebar.gd` | Space-level NSFW gate in `_on_space_selected()` |
| `scenes/admin/space_settings_dialog.gd` | Space settings — no `nsfw_level` dropdown (entire file) |
| `scripts/autoload/config.gd` | Per-server NSFW acknowledgement: `has_nsfw_ack()`, `set_nsfw_ack()` |
| `scripts/autoload/client.gd` | `is_nsfw_acked(space_id)` convenience method |

## Implementation Details

### Channel NSFW Flag (Implemented)

The `AccordChannel` model has `var nsfw: bool = false` (line 13 of `channel.gd`). This is parsed from the server response in `from_dict()` (line 41) and included in `to_dict()` (line 79).

`ClientModels.channel_to_dict()` conditionally includes `"nsfw": true` in the UI dictionary shape when the channel's `nsfw` flag is set (lines 286-287). Non-NSFW channels omit the key entirely.

### NSFW Visual Indicator (Implemented)

`channel_item.gd` renders a red tint on the channel type icon when `data["nsfw"]` is true (line 74-75). The error color comes from `ThemeManager.get_color("error")`. This tint is preserved across multiple state changes:

- **Mute dimming** (line 123): only reduces alpha if not NSFW (NSFW keeps its red tint).
- **Un-mute restore** (line 127): only restores alpha if not NSFW and not active.
- **Icon color apply** (line 136): early-returns if NSFW, preventing default/active colors from overriding the red tint.
- **Hover** (line 146): only applies hover color if not NSFW.

### Channel Edit NSFW Toggle (Implemented)

The `channel_edit_dialog.gd` exposes a checkbox (`_nsfw_check`, line 13) that is pre-filled from the channel data (line 33). On save, the `nsfw` value is included in the PATCH payload (line 44). The checkbox toggling marks the form as dirty (line 27).

### Space nsfw_level (Model Only)

`AccordSpace` has `var nsfw_level: String = "default"` (line 30 of `space.gd`). Possible values from the server include `"default"`, `"safe"`, `"age_restricted"`, and `"explicit"`. The field is parsed in `from_dict()` (line 82) and included in `to_dict()` (line 102). However, no UI reads or displays this value — the Space Settings dialog (`space_settings_dialog.gd`) does not include an `nsfw_level` dropdown.

### Space explicit_content_filter (Model Only)

`AccordSpace` also has `var explicit_content_filter: String = "disabled"` (line 18 of `space.gd`). Like `nsfw_level`, this is parsed and serialized but never surfaced in any UI.

### No Access Gating

Currently, clicking an NSFW channel loads messages identically to a non-NSFW channel. There is no check in the message view, sidebar, or `AppState.select_channel()` flow that gates access based on NSFW status. The red icon tint is purely cosmetic.

## Implementation Status

- [x] `AccordChannel.nsfw` field in data model
- [x] `AccordSpace.nsfw_level` field in data model
- [x] `AccordSpace.explicit_content_filter` field in data model
- [x] NSFW red tint on channel icon in sidebar
- [x] NSFW tint preserved across hover/active/mute states
- [x] Admin NSFW toggle in Channel Edit dialog
- [x] NSFW flag included in channel update PATCH payload
- [x] Unit test for NSFW red tint (`test_channel_item.gd:72`)
- [x] Unit test for non-NSFW default tint (`test_channel_item.gd:78`)
- [x] Unit test for NSFW in ClientModels (`test_client_models.gd:286`)
- [x] NSFW consent interstitial before loading channel content
- [x] Access gate before loading NSFW channel messages
- [x] Access gate before loading NSFW space content
- [x] Per-server NSFW acknowledgement caching in Config
- [ ] `nsfw_level` dropdown in Space Settings dialog
- [ ] `explicit_content_filter` dropdown in Space Settings dialog
- [ ] NSFW badge/label on channel name (beyond icon tint)
- [ ] NSFW warning banner in message view header

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| ~~No NSFW consent interstitial~~ | ~~High~~ | Implemented. `nsfw_gate_dialog` shows "Age-Restricted Content" interstitial before loading NSFW channel/space content. |
| ~~No access gate for NSFW channels~~ | ~~High~~ | Implemented. `channel_list.gd:_on_channel_pressed()` checks `Client.is_nsfw_acked()` before proceeding. |
| No `nsfw_level` in Space Settings UI | Medium | `AccordSpace.nsfw_level` (line 30 of `space.gd`) is parsed from the server but `space_settings_dialog.gd` has no dropdown for it. Admins cannot configure the space's NSFW level from the client. |
| No `explicit_content_filter` in Space Settings UI | Medium | `AccordSpace.explicit_content_filter` (line 18 of `space.gd`) is parsed but never exposed. This could control auto-scanning of media in NSFW channels. |
| ~~No per-server NSFW acknowledgement cache~~ | ~~Low~~ | Implemented. `Config.has_nsfw_ack()` / `set_nsfw_ack()` stores per-server acknowledgement in the `[nsfw_ack]` config section. |
| No NSFW indicator in message view header | Low | When viewing an NSFW channel, there's no banner or label in the message view indicating the channel is age-restricted. The red icon tint in the sidebar is the only visual cue. |
| NSFW channels visible in sidebar without restriction | Medium | NSFW channels appear in the channel list for all users. Even if messages are gated, channel names and topics are visible. Consider hiding NSFW channels entirely for users who haven't acknowledged. |
| No NSFW filter for Discovery panel | Low | The server discovery panel (`discovery_panel.gd`) lists spaces but has no NSFW filter. Spaces with `nsfw_level: "explicit"` appear alongside safe spaces with no distinction. |
