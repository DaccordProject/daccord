# Imposter Mode

Priority: 71
Depends on: Role-Based Permissions

## Overview
Imposter mode lets a space admin temporarily preview the client as if they had a different set of permissions — for example, viewing the space as a regular member, a moderator, or a user with a specific role. The admin's actual permissions are swapped out for the impersonated role's permissions, so the entire UI (context menus, channel visibility, admin panels, composer restrictions) reflects what that role would experience. No data is modified; the mode is purely a client-side preview.

## User Steps
1. Admin right-clicks a space icon or opens the channel banner dropdown.
2. Admin selects **"View As…"** from the context menu.
3. A role picker dialog appears listing all roles in the space (sorted by position, descending).
4. Admin selects a role (e.g. "@everyone", "Moderator") or picks **"Custom…"** to hand-pick individual permissions.
5. The client enters imposter mode:
   - A persistent banner appears at the top of the message view: **"Previewing as [Role Name] — Exit"**.
   - All `Client.has_permission()` and `Client.has_channel_permission()` calls return results based on the impersonated role instead of the admin's real permissions.
   - The UI re-evaluates: hidden channels disappear (or show as locked), admin menu items vanish, composer becomes read-only, member context menu actions are removed.
   - All mutations (send, edit, delete, react) are blocked client-side.
6. Admin interacts with the client normally, seeing exactly what a user with that role would see.
7. Admin clicks **"Exit"** on the banner (or presses Escape) to leave imposter mode and restore their real permissions.

## Signal Flow
```
Admin clicks "View As…"
  └─► guild_icon / banner opens ImposterPickerDialog
        └─► admin selects role
              └─► ImposterPickerDialog calls AppState.enter_imposter_mode(role_data)
                    └─► AppState.imposter_mode_changed.emit(true)
                          ├─► client_permissions.has_permission()
                          │     └─► returns imposter_permissions for the imposter space
                          ├─► client_permissions.has_channel_permission()
                          │     └─► resolves channel overwrites against imposter role
                          ├─► guild_icon context menu
                          │     └─► hides "View As…" while imposter is active
                          ├─► banner admin dropdown
                          │     └─► hides "View As…" while imposter is active
                          ├─► channel_list._on_imposter_mode_changed()
                          │     └─► reloads space: hides/locks channels without view_channel
                          ├─► channel_item
                          │     └─► shows lock icon + reduced opacity for locked channels
                          ├─► voice_channel_item
                          │     └─► blocks join if CONNECT not in imposter permissions
                          ├─► message_view imposter_banner
                          │     └─► shows "Previewing as [Role Name]" + Exit button
                          ├─► composer.update_enabled_state()
                          │     └─► disables input; shows placeholder if send_messages revoked
                          ├─► client_mutations._blocked_by_imposter()
                          │     └─► blocks send/edit/delete/react mutations
                          └─► member_item context menu
                                └─► auto-gates via has_permission() — no kick/ban/roles

Admin clicks "Exit" (or presses Escape)
  └─► AppState.exit_imposter_mode()
        └─► AppState.imposter_mode_changed.emit(false)
              └─► all components restore real permissions

Admin switches space / enters DM mode
  └─► AppState.select_space() / AppState.enter_dm_mode()
        └─► auto-calls exit_imposter_mode() if imposter_space_id differs
```

## Key Files
| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | Signal `imposter_mode_changed` (line 109), state vars `is_imposter_mode`, `imposter_permissions`, `imposter_role_name`, `imposter_space_id`, `imposter_role_id` (lines 240-244), `enter_imposter_mode()` / `exit_imposter_mode()` (lines 436-451), auto-exit on space switch (line 246) and DM mode (line 271) |
| `scripts/autoload/client_permissions.gd` | `has_permission()` imposter branch (line 11), `has_channel_permission()` imposter branch delegating to `_has_channel_perm_imposter()` (line 38), channel overwrite resolution for imposter role (lines 163-206) |
| `scripts/autoload/client_mutations.gd` | `_blocked_by_imposter()` guard (lines 24-30), applied to `send_message_to_channel` (line 83), `update_message_content` (line 170), `remove_message` (line 208), `add_reaction` (line 240) |
| `scenes/admin/imposter_picker_dialog.gd` | Role picker: fetches and sorts roles (lines 32-81), custom permission checkboxes (lines 83-93), builds `role_data` with `id` and calls `AppState.enter_imposter_mode()` (lines 114-137) |
| `scenes/admin/imposter_picker_dialog.tscn` | Scene for the role picker dialog |
| `scenes/admin/imposter_banner.gd` | Persistent banner: "Previewing as [Role]" label, Exit button, visibility tied to `imposter_mode_changed` (lines 1-17) |
| `scenes/admin/imposter_banner.tscn` | Banner scene with amber background (`Color(0.945, 0.769, 0.059, 0.15)`), HBox layout |
| `scenes/sidebar/guild_bar/guild_icon.gd` | "View As…" admin submenu item gated by `MANAGE_ROLES` and hidden during imposter mode (line 207), preloads `ImposterPickerScene` (line 16) |
| `scenes/sidebar/channels/banner.gd` | "View As…" in admin dropdown (line 102), preloads picker (line 12), rebuilds on mode change (line 158) |
| `scenes/sidebar/channels/channel_list.gd` | Filters channels by `VIEW_CHANNEL` via `has_channel_permission()`, shows locked channels with lock icon in imposter mode (lines 97-112), auto-reloads on mode change (line 304) |
| `scenes/sidebar/channels/channel_item.gd` | Renders locked channels with lock icon and reduced opacity (line 86) |
| `scenes/sidebar/channels/voice_channel_item.gd` | Blocks voice join when `CONNECT` not in imposter permissions (line 85) |
| `scenes/messages/message_view.gd` | Hosts `ImposterBanner` in scene tree, Escape key exits imposter mode (lines 155-159) |
| `scenes/messages/message_view.tscn` | Includes imposter_banner.tscn as ext_resource |
| `scenes/messages/composer/composer.gd` | Listens to `imposter_mode_changed` to call `update_enabled_state()` (line 42), disables editing and shows placeholder in imposter mode (lines 459-474), blocks file drops (line 245) |
| `scenes/members/member_item.gd` | Context menu gates on `has_permission()` — works automatically with imposter override |
| `scenes/main/main_window.gd` | Auto-exits imposter mode on server disconnect (line 299) |
| `addons/accordkit/models/permission.gd` | `has()` (line 93) checks for ADMINISTRATOR bypass, `all()` (line 48) returns all 40 permission strings |
| `tests/unit/test_client_permissions.gd` | 24 tests including imposter mode permission checks: space-level (line 144), channel-level basic (line 179), channel overwrites with @everyone deny (line 379), role overwrite allow (line 398), ADMINISTRATOR bypass (line 413) |

## Implementation Details

### AppState: Imposter mode signals and state
`app_state.gd` declares:
- `signal imposter_mode_changed(active: bool)` (line 109) — emitted when entering/exiting imposter mode
- `var is_imposter_mode: bool = false` (line 240) — whether imposter mode is active
- `var imposter_permissions: Array = []` (line 241) — the effective permission list for the impersonated view
- `var imposter_role_name: String = ""` (line 242) — display name for the banner
- `var imposter_space_id: String = ""` (line 243) — scoped to one space
- `var imposter_role_id: String = ""` (line 244) — role ID for channel overwrite resolution (empty for custom permissions)

Methods:
- `enter_imposter_mode(role_data: Dictionary)` (line 436) — sets all imposter state from the role data dict and emits signal
- `exit_imposter_mode()` (line 443) — resets all imposter state and emits signal; no-op if not active
- Auto-exit: `select_space()` (line 246) exits imposter mode when switching to a different space; DM mode entry (line 271) also exits

### Client: Permission override
`client_permissions.gd` has two permission methods, both with imposter mode branches:

**`has_permission()`** (line 10): For space-level checks, if `is_imposter_mode` and the space matches `imposter_space_id`, returns `AccordPermission.has(imposter_permissions, perm)` directly (line 11-12). This single check propagates through the entire UI because every component calls `Client.has_permission()`.

**`has_channel_permission()`** (line 34): Delegates to `_has_channel_perm_imposter()` (line 38-42) which resolves channel overwrites against the imposter role:
1. Starts with `imposter_permissions` as base (line 168)
2. If ADMINISTRATOR is present, bypasses all overwrites (line 169)
3. Applies @everyone channel overwrite deny/allow (lines 182-191)
4. If `imposter_role_id` is set (not custom), applies role-specific channel overwrite (lines 195-204)
5. Returns whether the permission is in the effective set (line 206)

### Write protection
`client_mutations.gd` has a `_blocked_by_imposter(space_id)` guard method (line 24) that checks whether imposter mode is active for the given space. This guard is called at the top of:
- `send_message_to_channel()` (line 83)
- `update_message_content()` (line 170)
- `remove_message()` (line 208)
- `add_reaction()` (line 240)

When blocked, the mutation returns early with a warning log. This prevents accidental writes during preview mode, even if the UI fails to disable an action.

### ImposterPickerDialog: Role selection
`imposter_picker_dialog.gd` is a modal dialog:
- `setup(space_id)` (line 26) fetches roles via `Client.get_roles_for_space()` and builds the UI
- Roles sorted by position descending (line 38), displayed with color dot and name (lines 42-68)
- "Custom…" option (line 74) toggles a permission checklist panel using all 40 permissions from `AccordPermission.all()` (lines 83-93)
- Preview button (line 114) builds `role_data` dict with `name`, `permissions`, `space_id`, and `id`, then calls `AppState.enter_imposter_mode(role_data)`
- Gated: "View As…" only appears if `Client.has_permission(space_id, MANAGE_ROLES)` is true

### ImposterBanner: Visual indicator
`imposter_banner.gd` is a PanelContainer with amber background:
- Displays "Previewing as [Role Name]" via `role_label` (line 11)
- Exit button calls `AppState.exit_imposter_mode()` (line 7)
- Visibility auto-toggles on `imposter_mode_changed` signal (line 8)
- Escape key also exits via `message_view.gd:_unhandled_input()` (line 155)

### Channel visibility filtering
`channel_list.gd` (lines 97-112) filters channels when loading a space:
- Each non-category channel is checked via `Client.has_channel_permission(space_id, ch_id, VIEW_CHANNEL)`
- Channels with permission are shown normally
- In imposter mode, channels without permission are shown with `locked = true` flag instead of hidden
- `channel_item.gd` (line 86) renders locked channels with a lock icon and 0.4 opacity, making them non-interactive
- Voice channels check `CONNECT` permission before allowing join in imposter mode

### Composer restrictions
`composer.gd` listens to `imposter_mode_changed` (line 42) and calls `update_enabled_state()`:
- If imposter mode is active for the current space, disables text input and send button (line 459-464)
- Shows contextual placeholder: "Cannot send — previewing as [Role]" if `SEND_MESSAGES` not in imposter permissions (lines 466-474)
- Blocks file drops in imposter mode (line 245)

## Implementation Status
- [x] Permission model with 40 granular permissions (`permission.gd`)
- [x] `Client.has_permission()` centralized check with admin/owner bypass and imposter branch
- [x] `Client.has_channel_permission()` with full overwrite cascade and imposter branch
- [x] All UI components gate features through `Client.has_permission()` — guild_icon, member_item, banner dropdown, member_list
- [x] Role management dialog with permission checkboxes (`role_management_dialog.gd`)
- [x] Channel permission overwrites with allow/inherit/deny model (`channel_permissions_dialog.gd`)
- [x] Gateway events for role create/update/delete keeping caches current
- [x] AppState imposter mode signal and state variables (including `imposter_role_id`)
- [x] `Client.has_permission()` imposter mode branch
- [x] `Client.has_channel_permission()` imposter mode branch with channel overwrite resolution
- [x] ImposterPickerDialog (role selection + custom permissions)
- [x] ImposterBanner (visual indicator + exit control)
- [x] Channel visibility filtering based on impersonated permissions (with lock icon for hidden channels)
- [x] Write-protection guard (blocks send/edit/delete/react mutations during imposter mode)
- [x] Escape key shortcut to exit imposter mode
- [x] "View As…" menu item in space icon context menu
- [x] "View As…" menu item in banner admin dropdown
- [x] Auto-exit on space switch and DM mode transition
- [x] Auto-exit on server disconnect
- [x] Voice channel CONNECT permission check in imposter mode
- [x] Composer file drop blocked in imposter mode
- [x] Unit tests for imposter permission resolution (space-level, channel-level, overwrites)
- [ ] Multiple role combination preview (IMPOSTER-5)
- [ ] Notification suppression for hidden channels (IMPOSTER-7)

## Tasks

### IMPOSTER-5: Multiple role combination
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** permissions
- **Notes:** Real users can have multiple roles whose permissions merge. The role picker only previews one role at a time. A "multi-role" picker (select several roles to merge) would be more accurate but adds complexity. The current single-role preview is sufficient for most use cases.

### IMPOSTER-7: Notification suppression
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** permissions, ui
- **Notes:** In imposter mode, the admin may receive mention highlights or unread badges that a regular user in that role wouldn't see (e.g., admin-only channel mentions). Consider suppressing notifications for channels hidden by imposter mode's channel filtering.
