# Direct Messages

Priority: 8
Depends on: Messaging
Status: Complete

Users access direct messages by clicking the DM button in the space bar, switching the sidebar to the DM list with search, avatars, last message previews, and unread indicators.

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/direct/dm_list.gd` | DM list container, search filtering, dm_selected signal |
| `scenes/sidebar/direct/dm_channel_item.gd` | Individual DM: avatar, username, last message, unread dot |
| `scenes/sidebar/sidebar.gd` | Toggles between channel_list and dm_list |
| `scenes/sidebar/guild_bar/guild_bar.gd` | DM button emits dm_selected signal (space bar) |
| `scripts/autoload/client.gd` | `fetch_dm_channels()`, `dm_channels` property |
| `scripts/autoload/client_models.gd` | `dm_channel_to_dict()` conversion |
| `scripts/autoload/app_state.gd` | `enter_dm_mode()`, `dm_mode_entered` signal |
