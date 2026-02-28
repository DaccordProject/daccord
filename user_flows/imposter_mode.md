# Imposter Mode

## Overview
Imposter mode lets a space admin temporarily preview the client as if they had a different set of permissions — for example, viewing the space as a regular member, a moderator, or a user with a specific role. The admin's actual permissions are swapped out for the impersonated role's permissions, so the entire UI (context menus, channel visibility, admin panels, composer restrictions) reflects what that role would experience. No data is modified; the mode is purely a client-side preview.

## User Steps
1. Admin right-clicks a space icon or opens the channel banner dropdown.
2. Admin selects **"View As…"** from the context menu.
3. A role picker dialog appears listing all roles in the space (sorted by position, descending).
4. Admin selects a role (e.g. "@everyone", "Moderator") or picks **"Custom…"** to hand-pick individual permissions.
5. The client enters imposter mode:
   - A persistent banner appears at the top of the message view: **"Viewing as [Role Name] — Exit"**.
   - All `Client.has_permission()` calls return results based on the impersonated role instead of the admin's real permissions.
   - The UI re-evaluates: hidden channels disappear, admin menu items vanish, composer may become read-only, member context menu actions are removed.
6. Admin interacts with the client normally, seeing exactly what a user with that role would see.
7. Admin clicks **"Exit"** on the banner (or presses Escape) to leave imposter mode and restore their real permissions.

## Signal Flow
```
Admin clicks "View As…"
  └─► guild_icon / banner opens (space icon) ImposterPickerDialog
        └─► admin selects role
              └─► ImposterPickerDialog calls AppState.enter_imposter_mode(role_data)
                    └─► AppState.imposter_mode_changed.emit(true)
                          ├─► Client._on_imposter_mode_changed()
                          │     └─► swaps permission source to impersonated role
                          ├─► guild_icon._on_imposter_mode_changed() (space icon)
                          │     └─► rebuilds context menu with reduced items
                          ├─► banner._on_imposter_mode_changed()
                          │     └─► rebuilds admin dropdown with reduced items
                          ├─► channel_list._on_imposter_mode_changed()
                          │     └─► hides channels without view_channel
                          ├─► message_view._on_imposter_mode_changed()
                          │     └─► shows imposter banner, disables restricted actions
                          ├─► member_item._on_imposter_mode_changed()
                          │     └─► rebuilds context menu (no kick/ban/roles)
                          └─► composer._on_imposter_mode_changed()
                                └─► disables input if send_messages revoked

Admin clicks "Exit"
  └─► AppState.exit_imposter_mode()
        └─► AppState.imposter_mode_changed.emit(false)
              └─► all components restore real permissions
```

## Key Files

### Existing files that need modification
| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | New signal `imposter_mode_changed`, state variables `is_imposter_mode`, `imposter_role_data` |
| `scripts/autoload/client.gd` | `has_permission()` (line 438) checks `AppState.is_imposter_mode` and resolves against impersonated role instead of real roles |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Adds "View As…" menu item (after line 159), listens to `imposter_mode_changed` to rebuild menu |
| `scenes/sidebar/channels/banner.gd` | Adds "View As…" to admin dropdown, rebuilds on mode change |
| `scenes/sidebar/channels/channel_list.gd` | Filters channels by `view_channel` permission when in imposter mode |
| `scenes/messages/message_view.gd` | Shows/hides imposter banner bar |
| `scenes/messages/composer/composer.gd` | Disables input when impersonated role lacks `send_messages` |
| `scenes/members/member_item.gd` | `_show_context_menu()` (line 47) already gates on `has_permission()` — works automatically |
| `addons/accordkit/models/permission.gd` | No changes needed; `has()` (line 91) and `all()` (line 47) already support the permission model |

### New files
| File | Role |
|------|------|
| `scenes/admin/imposter_picker_dialog.gd` | Role picker dialog with role list + custom permission editor |
| `scenes/admin/imposter_picker_dialog.tscn` | Scene for the role picker |
| `scenes/admin/imposter_banner.gd` | Persistent banner shown during imposter mode |
| `scenes/admin/imposter_banner.tscn` | Scene for the banner (HBoxContainer with label + exit button) |

## Implementation Details

### AppState: Imposter mode signals and state
Add to `app_state.gd`:
- `signal imposter_mode_changed(active: bool)` — emitted when entering/exiting imposter mode
- `var is_imposter_mode: bool = false` — whether imposter mode is active
- `var imposter_permissions: Array = []` — the effective permission list for the impersonated view
- `var imposter_role_name: String = ""` — display name for the banner

Methods:
- `enter_imposter_mode(role_data: Dictionary)` — sets `is_imposter_mode = true`, extracts `role_data.permissions` into `imposter_permissions`, sets `imposter_role_name`, emits signal
- `exit_imposter_mode()` — resets all imposter state, emits signal

### Client: Permission override in has_permission()
`client.gd:has_permission()` (line 438) currently resolves permissions from the real user's roles. In imposter mode, it should short-circuit:

```
func has_permission(gid: String, perm: String) -> bool:
    if AppState.is_imposter_mode:
        return AccordPermission.has(AppState.imposter_permissions, perm)
    # ... existing logic unchanged ...
```

This single change propagates through the entire UI because every component already calls `Client.has_permission()`. Components that gate features (guild_icon context menu at line 140, member_item context menu at line 64, member_list invite button, banner admin dropdown) will automatically reflect the impersonated role's permissions.

**Write protection:** Even though the UI will hide actions the impersonated role can't perform, the admin should not accidentally perform write operations while in imposter mode. `Client.admin.*` methods and `Client.mutations.*` methods should check `AppState.is_imposter_mode` and block calls — or alternatively, the UI should disable all interactive actions (send, edit, delete, kick, ban, role toggle) regardless of the impersonated permissions, since imposter mode is strictly a preview.

### ImposterPickerDialog: Role selection
A modal dialog similar in structure to `role_management_dialog.gd`:
- Fetches roles via `Client.get_roles_for_space(space_id)`, sorted by position descending
- Each role is a selectable row (radio-button style) showing the role name with its color
- A **"Custom…"** option at the bottom opens a permission checklist (reusing the 37-checkbox pattern from `role_management_dialog.gd` line 59)
- **"Preview"** button calls `AppState.enter_imposter_mode()` with the selected role data
- Gated: only shown if `Client.has_permission(space_id, AccordPermission.MANAGE_ROLES)` — only users who can manage roles should preview other roles

### ImposterBanner: Visual indicator
A thin bar at the top of `message_view` (inserted above the scroll container):
- Background: amber/warning color (`Color(0.945, 0.769, 0.059, 0.15)`) to clearly distinguish from normal mode
- Text: `"Previewing as [Role Name]"` — left-aligned
- **"Exit"** button — right-aligned, calls `AppState.exit_imposter_mode()`
- Escape key also exits (via `_unhandled_input`)
- The banner should be visually prominent so the admin never forgets they're in imposter mode

### Channel visibility filtering
`channel_list.gd` currently shows all channels for the selected space. In imposter mode, channels where the impersonated role lacks `view_channel` (accounting for channel permission overwrites) should be hidden.

This requires extending the permission check to consider channel-level overwrites:
1. For each channel, check `permission_overwrites` for the impersonated role
2. If the overwrite denies `view_channel`, hide the channel
3. If the overwrite allows `view_channel`, show it
4. Otherwise, fall back to the role's base `view_channel` permission

The existing `channel_permissions_dialog.gd` already reads `permission_overwrites` (line 42), so the data shape is established. A new utility method `Client.has_channel_permission(channel_id, perm)` could centralize this logic for both imposter mode and future general use.

### Custom permission picker
For the "Custom…" option, reuse the checkbox grid pattern from `role_management_dialog.gd:_build_perm_checkboxes()` (line 59). This lets the admin hand-pick exactly which permissions to preview — useful for testing edge cases like "what if a role has `send_messages` but not `attach_files`?"

## Implementation Status
- [x] Permission model with 37 granular permissions (`permission.gd`)
- [x] `Client.has_permission()` centralized check with admin/owner bypass (line 438)
- [x] All UI components gate features through `Client.has_permission()` — guild_icon (line 140), member_item (line 64), banner dropdown, member_list invite button
- [x] Role management dialog with permission checkboxes (`role_management_dialog.gd`)
- [x] Channel permission overwrites with allow/inherit/deny model (`channel_permissions_dialog.gd`)
- [x] Gateway events for role create/update/delete keeping caches current (`client_gateway.gd`)
- [ ] AppState imposter mode signal and state variables
- [ ] `Client.has_permission()` imposter mode branch
- [ ] ImposterPickerDialog (role selection + custom permissions)
- [ ] ImposterBanner (visual indicator + exit control)
- [ ] Channel visibility filtering based on impersonated permissions
- [ ] Channel-level permission overwrite resolution in imposter mode
- [ ] Write-protection guard (block mutations during imposter mode)
- [ ] Escape key shortcut to exit imposter mode
- [ ] "View As…" menu item in space icon context menu
- [ ] "View As…" menu item in banner admin dropdown

## Tasks

### IMPOSTER-1: No `has_channel_permission()` utility
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** permissions, ui
- **Notes:** `has_permission()` (client.gd:438) only checks space-level role permissions. Channel overwrites are only read in `channel_permissions_dialog.gd` for editing, not for runtime evaluation. Imposter mode needs a channel-aware permission resolver to correctly hide channels and gate per-channel actions.

### IMPOSTER-2: No channel visibility filtering
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** general
- **Notes:** `channel_list.gd` shows all channels unconditionally. Even outside imposter mode, channels the user can't view should arguably be hidden. This is a prerequisite for imposter mode's channel filtering.

### IMPOSTER-3: Write protection during preview
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** ci, permissions, ui
- **Notes:** If the admin clicks "Send" while previewing @everyone, the message would actually send (with admin permissions on the server). Either disable all mutations client-side, or add a confirmation dialog warning that actions are performed with real permissions. Design decision needed.

### IMPOSTER-4: DM mode interaction
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** dm
- **Notes:** Imposter mode is scoped to a single space. Entering DM mode while in imposter mode should either exit imposter mode automatically or block the transition.

### IMPOSTER-5: Multiple role combination
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** permissions
- **Notes:** Real users can have multiple roles whose permissions merge. The role picker only previews one role at a time. A "multi-role" picker (select several roles to merge) would be more accurate but adds complexity.

### IMPOSTER-6: Voice channel restrictions
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** api, permissions, voice
- **Notes:** Voice channels gated by `connect` / `speak` permissions should appear disabled or hidden in imposter mode. Currently voice permission checks happen in LiveKit, not through `Client.has_permission()`.

### IMPOSTER-7: Notification suppression
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** permissions, ui
- **Notes:** In imposter mode, the admin may receive mention highlights or unread badges that a regular user in that role wouldn't see (e.g., admin-only channel mentions). Consider suppressing notifications for hidden channels.
