# Group DMs

Priority: 49
Depends on: Direct Messages
Status: Complete

Group DM channels with multiple recipients, featuring create/rename/add-member/leave operations, stacked avatar grid, participant sidebar, and owner indicators.

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/client_models.gd` | `dm_channel_to_dict()` — detects group via `recipients.size() > 1`, builds comma-separated name, includes `owner_id` and `name` |
| `scripts/autoload/client_gateway.gd` | Handles `channel_create/update/delete` for `type == "group_dm"` |
| `scripts/autoload/client_fetch.gd` | `fetch_dm_channels()` — fetches all DM channels (1:1 and group) from all servers |
| `scripts/autoload/client_mutations.gd` | `create_dm()`, `create_group_dm()`, `add_dm_member()`, `remove_dm_member()`, `rename_group_dm()` |
| `scripts/autoload/client.gd` | `_dm_channel_cache`, `_dm_to_conn` routing, `dm_channels` property, delegate methods for group DM mutations |
| `scripts/autoload/app_state.gd` | `dm_mode_entered`, `dm_channels_updated` signals, `is_dm_mode` state |
| `scenes/sidebar/direct/dm_list.gd` | Populates DM list, "+" button for new group DM, improved search filtering, dm_selected signal |
| `scenes/sidebar/direct/dm_list.tscn` | DM list scene with HeaderRow containing HeaderLabel and NewGroupBtn |
| `scenes/sidebar/direct/dm_channel_item.gd` | Renders each DM item — stacked group avatar, custom name, member count badge, context menu (add member/rename/leave) |
| `scenes/sidebar/direct/create_group_dm_dialog.gd` | Multi-select user picker dialog for creating group DMs |
| `scenes/sidebar/direct/create_group_dm_dialog.tscn` | Dialog scene — ColorRect overlay, centered Panel, search, checklist, create button |
| `scenes/sidebar/direct/add_member_dialog.gd` | Single-select user picker dialog for adding a member to an existing group DM |
| `scenes/sidebar/direct/add_member_dialog.tscn` | Add member dialog scene — ColorRect overlay, centered Panel, search, user list, add button |
| `scenes/common/group_avatar.gd` | 2x2 grid of mini-avatars for group DM items, `setup_recipients(recipients)` |
| `scenes/common/group_avatar.tscn` | GroupAvatar scene — ColorRect with GridContainer and circle shader clipping |
| `scenes/main/main_window.gd` | Window title and tab name from dm.user.display_name; member list visibility for group DMs |
| `scenes/members/member_list.gd` | `_build_dm_participants()` — shows group DM participants with owner indicator |
| `scenes/members/member_item.gd` | Displays "(Owner)" suffix for group DM owner |
| `scenes/messages/message_view.gd` | Composer placeholder, typing indicator with username |
| `scenes/messages/typing_indicator.gd` | `show_typing(username)` — shows "username is typing..." |
| `addons/accordkit/models/channel.gd` | `AccordChannel` model with `recipients`, `owner_id`, `type` fields |
| `addons/accordkit/rest/endpoints/channels_api.gd` | `add_recipient()`, `remove_recipient()` for managing group DM members |
| `addons/accordkit/rest/endpoints/users_api.gd` | `create_dm()` — POST /users/@me/channels |
| `tests/unit/test_client_models.gd` | `test_dm_channel_group()` — verifies `is_group` flag and comma-separated names |
