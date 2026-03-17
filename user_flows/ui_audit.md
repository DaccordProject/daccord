# UI Audit

## Overview
Every view, dialog, panel, and overlay in the daccord client needs to be screenshotted and reviewed by a designer and UX expert. This document catalogs all user-facing surfaces organized by area, providing a checklist for systematic visual review and design analysis.

## User Steps
1. Auditor launches the daccord client and connects to a test server with full admin permissions
2. Auditor navigates through each area of the application, capturing screenshots at each surface
3. Screenshots are annotated with the surface name and file path for developer cross-reference
4. Designer reviews each screenshot for visual consistency, spacing, typography, and color usage
5. UX expert reviews each screenshot for usability, discoverability, accessibility, and interaction patterns
6. Findings are logged per-surface with severity and recommended changes
7. Responsive variants are captured at COMPACT (<500px), MEDIUM (<768px), and FULL (>=768px) breakpoints

## Signal Flow
```
Auditor navigates UI
  → Each scene loads via preload() / instantiate()
  → AppState signals trigger view transitions
    ├── guild_selected → channel_list rebuild
    ├── channel_selected → message_view load
    ├── dm_mode_changed → DM list / friends list
    ├── settings_opened → app_settings panel
    └── voice_joined → voice_bar + video_grid
  → Screenshot captured at each stable state
```

## Key Files
| File | Role |
|------|------|
| `scenes/main/main_window.tscn` | Root layout — sidebar + content + video grid |
| `scenes/main/main_window.gd` | Layout mode switching, panel visibility |
| `scripts/autoload/app_state.gd` | Signal bus driving all view transitions |
| `scenes/sidebar/sidebar.tscn` | Sidebar container for guild bar + channel/DM lists |
| `scenes/messages/message_view.tscn` | Central message feed |
| `scenes/user/app_settings.tscn` | Global settings panel |
| `scenes/admin/server_management_panel.tscn` | Instance-level admin panel |

## Audit Checklist

### 1. Main Window & Navigation

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 1.1 | Main window (full layout) | `scenes/main/main_window.tscn` | `main_window.gd` | COMPACT, MEDIUM, FULL breakpoints |
| 1.2 | Welcome screen (no servers) | `scenes/main/welcome_screen.tscn` | `welcome_screen.gd` | Empty state with CTA |
| 1.3 | Toast notification | `scenes/main/toast.tscn` | `toast.gd` | Success, error, info variants |
| 1.4 | Mobile drawer overlay | — | `main_window_drawer.gd` | Open/closed states on COMPACT |
| 1.5 | Panel resize handle | — | `panel_resize_handle.gd` | Hover, dragging states |

### 2. Sidebar — Guild Bar

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 2.1 | Guild bar (server list) | `scenes/sidebar/guild_bar/guild_bar.tscn` | `guild_bar.gd` | With servers, empty, scrolled |
| 2.2 | Guild icon | `scenes/sidebar/guild_bar/guild_icon.tscn` | `guild_icon.gd` | Default, selected, with badge, hover, context menu |
| 2.3 | Guild folder | `scenes/sidebar/guild_bar/guild_folder.tscn` | `guild_folder.gd` | Collapsed, expanded |
| 2.4 | Mention badge | `scenes/sidebar/guild_bar/mention_badge.tscn` | — | Single digit, double digit |
| 2.5 | Selection pill | `scenes/sidebar/guild_bar/pill.tscn` | — | Active, hover states |
| 2.6 | DM button | `scenes/sidebar/guild_bar/dm_button.tscn` | `dm_button.gd` | Default, selected, with unread badge |
| 2.7 | Discover button | `scenes/sidebar/guild_bar/discover_button.tscn` | `discover_button.gd` | Default, selected |
| 2.8 | Add server button | `scenes/sidebar/guild_bar/add_server_button.tscn` | `add_server_button.gd` | Default, hover |
| 2.9 | Add server dialog | `scenes/sidebar/guild_bar/add_server_dialog.tscn` | `add_server_dialog.gd` | Join tab, create tab, loading, error |
| 2.10 | Auth dialog (login/register) | `scenes/sidebar/guild_bar/auth_dialog.tscn` | `auth_dialog.gd` | Login form, register form, loading, error, 2FA prompt |
| 2.11 | Change password dialog | `scenes/sidebar/guild_bar/change_password_dialog.tscn` | `change_password_dialog.gd` | Form, success, error |

### 3. Sidebar — Channel List

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 3.1 | Channel list panel | `scenes/sidebar/channels/channel_list.tscn` | `channel_list.gd` | Populated, empty, loading skeleton |
| 3.2 | Channel list banner | `scenes/sidebar/channels/banner.tscn` | — | With/without server icon |
| 3.3 | Category item | `scenes/sidebar/channels/category_item.tscn` | `category_item.gd` | Expanded, collapsed, context menu |
| 3.4 | Text channel item | `scenes/sidebar/channels/channel_item.tscn` | `channel_item.gd` | Default, selected, unread, with mentions, NSFW, context menu |
| 3.5 | Voice channel item | `scenes/sidebar/channels/voice_channel_item.tscn` | `voice_channel_item.gd` | Empty, with users, full |
| 3.6 | Channel loading skeleton | `scenes/sidebar/channels/channel_skeleton.tscn` | — | Loading state |
| 3.7 | Uncategorized drop target | `scenes/sidebar/channels/uncategorized_drop_target.tscn` | — | Drag hover state |

### 4. Sidebar — Direct Messages & Friends

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 4.1 | DM list panel | `scenes/sidebar/direct/dm_list.tscn` | `dm_list.gd` | With DMs, empty state |
| 4.2 | Friends list | `scenes/sidebar/direct/friends_list.tscn` | `friends_list.gd` | All/Online/Pending/Blocked tabs, empty states |
| 4.3 | Friend item | `scenes/sidebar/direct/friend_item.tscn` | `friend_item.gd` | Online, offline, pending (incoming/outgoing), blocked |
| 4.4 | DM channel item | `scenes/sidebar/direct/dm_channel_item.tscn` | `dm_channel_item.gd` | 1:1 DM, group DM, unread, selected |
| 4.5 | Add friend dialog | `scenes/sidebar/direct/add_friend_dialog.tscn` | `add_friend_dialog.gd` | Search form, results, error |
| 4.6 | Add member dialog | `scenes/sidebar/direct/add_member_dialog.tscn` | `add_member_dialog.gd` | Search, selection state |
| 4.7 | Create group DM dialog | `scenes/sidebar/direct/create_group_dm_dialog.tscn` | `create_group_dm_dialog.gd` | Member selection, creating |

### 5. Sidebar — User Bar & Voice Bar

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 5.1 | User bar | `scenes/sidebar/user_bar.tscn` | `user_bar.gd` | Online, idle, DND, invisible, with custom status |
| 5.2 | Voice bar | `scenes/sidebar/voice_bar.tscn` | `voice_bar.gd` | Connected, muted, deafened, screen sharing, with activity |
| 5.3 | Screen picker dialog | `scenes/sidebar/screen_picker_dialog.tscn` | `screen_picker_dialog.gd` | Screen list, window list, selection |

### 6. Messages — Message View

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 6.1 | Message view (full) | `scenes/messages/message_view.tscn` | `message_view.gd` | Normal, NSFW gate, guest banner, connection lost, empty channel |
| 6.2 | Cozy message | `scenes/messages/cozy_message.tscn` | `cozy_message.gd` | Normal, with reply, with attachments, with embeds, with reactions, with thread indicator, edited, system message |
| 6.3 | Collapsed message | `scenes/messages/collapsed_message.tscn` | — | Sequential message from same author |
| 6.4 | Message content | `scenes/messages/message_content.tscn` | `message_content.gd` | Text, markdown, code block, mentions, links |
| 6.5 | Message action bar | `scenes/messages/message_action_bar.tscn` | `message_view_actions.gd` | Hover actions (reply, react, edit, delete, thread, pin) |
| 6.6 | Reaction bar | `scenes/messages/reaction_bar.tscn` | — | Single reaction, multiple, own reaction highlighted |
| 6.7 | Reaction pill | `scenes/messages/reaction_pill.tscn` | — | Default, self-reacted, hover |
| 6.8 | Reaction picker | `scenes/messages/reaction_picker.tscn` | — | Emoji grid popup |
| 6.9 | Embed | `scenes/messages/embed.tscn` | — | Link preview, rich embed |
| 6.10 | Image lightbox | `scenes/messages/image_lightbox.tscn` | — | Full-screen image view |
| 6.11 | Loading skeleton | `scenes/messages/loading_skeleton.tscn` | — | Message loading placeholder |
| 6.12 | Typing indicator | `scenes/messages/typing_indicator.tscn` | — | One user, multiple users typing |
| 6.13 | Update banner | `scenes/messages/update_banner.tscn` | `update_banner.gd` | Update available notification |
| 6.14 | Update download dialog | `scenes/messages/update_download_dialog.tscn` | `update_download_dialog.gd` | Download progress, complete, error |

### 7. Messages — Composer

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 7.1 | Composer | `scenes/messages/composer/composer.tscn` | `composer.gd` | Empty, typing, with attachment preview, reply mode, edit mode, disabled (read-only/guest) |
| 7.2 | Message input | `scenes/messages/composer/message_input.tscn` | — | Empty placeholder, multiline expanded |
| 7.3 | Emoji picker | `scenes/messages/composer/emoji_picker.tscn` | `emoji_picker.gd` | Category tabs, search, custom emoji, recent |
| 7.4 | Emoji button cell | `scenes/messages/composer/emoji_button_cell.tscn` | — | Default, hover |

### 8. Messages — Threads & Forums

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 8.1 | Thread panel | `scenes/messages/thread_panel.tscn` | `thread_panel.gd` | Thread with replies, empty thread, "also send to channel" checkbox |
| 8.2 | Active threads dialog | — | `active_threads_dialog.gd` | Thread list, empty state |
| 8.3 | Forum view | `scenes/messages/forum_view.tscn` | `forum_view.gd` | Post list, sort options (Latest/Newest/Oldest), new post form, empty state |
| 8.4 | Forum post row | `scenes/messages/forum_post_row.tscn` | `forum_post_row.gd` | Post with replies count, author, date |
| 8.5 | Voice text panel | `scenes/messages/voice_text_panel.tscn` | `voice_text_panel.gd` | Voice channel text chat |

### 9. Members

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 9.1 | Member list | `scenes/members/member_list.tscn` | `member_list.gd` | Populated with role groups, search active, empty search, loading |
| 9.2 | Member item | `scenes/members/member_item.tscn` | `member_item.gd` | Online, offline, with role badge, with nickname, context menu |
| 9.3 | Member header | `scenes/members/member_header.tscn` | `member_header.gd` | Expanded, collapsed, with count |
| 9.4 | Anonymous entry item | `scenes/members/anonymous_entry_item.tscn` | `anonymous_entry_item.gd` | Guest/anonymous user display |

### 10. User Profile & Settings

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 10.1 | Profile card (popup) | `scenes/user/profile_card.tscn` | `profile_card.gd` | Own profile, other user, with bio, with roles, with custom status, admin actions visible |
| 10.2 | App settings panel | `scenes/user/app_settings.tscn` | `app_settings.gd` | Each tab: Profiles, Voice & Video, Sound, Appearance, Notifications, Updates, About |
| 10.3 | Profiles settings page | — | `user_settings_profiles_page.gd` | Profile list, active profile highlighted |
| 10.4 | User settings profile page | — | `user_settings_profile.gd` | Edit username, avatar, bio |
| 10.5 | User settings danger page | — | `user_settings_danger.gd` | Account deletion section |
| 10.6 | User settings 2FA page | — | `user_settings_twofa.gd` | Enable/disable 2FA, QR code, recovery codes |
| 10.7 | Updates settings page | — | `app_settings_updates_page.gd` | Auto-update toggle, channel selector |
| 10.8 | About page | — | `app_settings_about_page.gd` | Version, credits, links |
| 10.9 | Create profile dialog | `scenes/user/create_profile_dialog.tscn` | `create_profile_dialog.gd` | New profile form |
| 10.10 | Server settings | `scenes/user/server_settings.tscn` | `server_settings.gd` | Per-server user settings |
| 10.11 | Change password dialog | `scenes/user/profile_password_dialog.tscn` | `profile_password_dialog.gd` | Password change form |
| 10.12 | Set password dialog | `scenes/user/profile_set_password_dialog.tscn` | `profile_set_password_dialog.gd` | Initial password set |
| 10.13 | Password field | `scenes/user/password_field.tscn` | — | Show/hide toggle |
| 10.14 | Settings base | — | `settings_base.gd` | Base theming (verify consistent across all settings) |

### 11. Admin — Server & Space Management

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 11.1 | Server management panel | `scenes/admin/server_management_panel.tscn` | `server_management_panel.gd` | Spaces tab, Users tab, Settings tab, Reports tab |
| 11.2 | Space settings dialog | `scenes/admin/space_settings_dialog.tscn` | `space_settings_dialog.gd` | General tab, rules tab, icon/banner upload |
| 11.3 | Create space dialog | — | `create_space_dialog.gd` | Space creation form |
| 11.4 | Transfer ownership dialog | — | `transfer_ownership_dialog.gd` | Ownership transfer confirmation |

### 12. Admin — Channel Management

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 12.1 | Channel management dialog | `scenes/admin/channel_management_dialog.tscn` | `channel_management_dialog.gd` | Channel list with reorder |
| 12.2 | Create channel dialog | `scenes/admin/create_channel_dialog.tscn` | `create_channel_dialog.gd` | Name, type selector, category picker |
| 12.3 | Channel edit dialog | `scenes/admin/channel_edit_dialog.tscn` | `channel_edit_dialog.gd` | Edit name, description, NSFW toggle |
| 12.4 | Category edit dialog | `scenes/admin/category_edit_dialog.tscn` | `category_edit_dialog.gd` | Category name edit |
| 12.5 | Channel row | `scenes/admin/channel_row.tscn` | `channel_row.gd` | Drag handle, edit/delete buttons |
| 12.6 | Channel permissions dialog | `scenes/admin/channel_permissions_dialog.tscn` | `channel_permissions_dialog.gd` | Role/member permission matrix, allow/deny toggles |
| 12.7 | Permission overwrite row | `scenes/admin/perm_overwrite_row.tscn` | `perm_overwrite_row.gd` | Individual permission toggle row |

### 13. Admin — Roles

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 13.1 | Role management dialog | `scenes/admin/role_management_dialog.tscn` | `role_management_dialog.gd` | Role list, create/edit/delete, member assignment |
| 13.2 | Role row | `scenes/admin/role_row.tscn` | `role_row.gd` | Color swatch, name, member count, actions |

### 14. Admin — Moderation & Members

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 14.1 | Moderate member dialog | `scenes/admin/moderate_member_dialog.tscn` | `moderate_member_dialog.gd` | Kick/ban/timeout options, role assignment |
| 14.2 | Ban dialog | `scenes/admin/ban_dialog.tscn` | `ban_dialog.gd` | Reason input, duration selector |
| 14.3 | Ban list dialog | `scenes/admin/ban_list_dialog.tscn` | `ban_list_dialog.gd` | Banned users list, empty state |
| 14.4 | Ban row | `scenes/admin/ban_row.tscn` | `ban_row.gd` | User name, reason, unban button |
| 14.5 | Nickname dialog | `scenes/admin/nickname_dialog.tscn` | `nickname_dialog.gd` | Nickname input |
| 14.6 | Imposter picker dialog | `scenes/admin/imposter_picker_dialog.tscn` | `imposter_picker_dialog.gd` | Member list for "View As" selection |
| 14.7 | Imposter banner | `scenes/admin/imposter_banner.tscn` | `imposter_banner.gd` | Warning banner during imposter mode |
| 14.8 | Reset password dialog | `scenes/admin/reset_password_dialog.tscn` | `reset_password_dialog.gd` | Admin force-reset password |
| 14.9 | Confirm dialog (generic) | `scenes/admin/confirm_dialog.tscn` | `confirm_dialog.gd` | Destructive action confirmation |

### 15. Admin — Invites & Reports

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 15.1 | Invite management dialog | `scenes/admin/invite_management_dialog.tscn` | `invite_management_dialog.gd` | Invite list, create new, empty state |
| 15.2 | Invite row | `scenes/admin/invite_row.tscn` | `invite_row.gd` | Code, uses, expiry, revoke button |
| 15.3 | Report dialog | `scenes/admin/report_dialog.tscn` | `report_dialog.gd` | Report form with reason selection |
| 15.4 | Report list dialog | `scenes/admin/report_list_dialog.tscn` | `report_list_dialog.gd` | Reported content list, empty state |
| 15.5 | Report row | `scenes/admin/report_row.tscn` | `report_row.gd` | Content preview, actions |
| 15.6 | Audit log dialog | `scenes/admin/audit_log_dialog.tscn` | `audit_log_dialog.gd` | Action filter, log entries, pagination |
| 15.7 | Audit log row | `scenes/admin/audit_log_row.tscn` | `audit_log_row.gd` | Action, actor, target, timestamp |

### 16. Admin — Content & Customization

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 16.1 | Emoji management dialog | `scenes/admin/emoji_management_dialog.tscn` | `emoji_management_dialog.gd` | Emoji grid, upload, empty state |
| 16.2 | Emoji cell | `scenes/admin/emoji_cell.tscn` | `emoji_cell.gd` | Emoji with delete hover |
| 16.3 | Soundboard management dialog | `scenes/admin/soundboard_management_dialog.tscn` | `soundboard_management_dialog.gd` | Sound list, upload |
| 16.4 | Sound row | `scenes/admin/sound_row.tscn` | `sound_row.gd` | Name, preview, delete |
| 16.5 | NSFW gate dialog | `scenes/admin/nsfw_gate_dialog.tscn` | `nsfw_gate_dialog.gd` | Age verification prompt |
| 16.6 | Rules interstitial dialog | — | `rules_interstitial_dialog.gd` | Rules acceptance before entry |
| 16.7 | Plugin management dialog | — | `plugin_management_dialog.gd` | Plugin list, enable/disable/delete |

### 17. Discovery

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 17.1 | Discovery panel | `scenes/discovery/discovery_panel.tscn` | `discovery_panel.gd` | Server grid, search, tag filter, loading, empty results |
| 17.2 | Discovery card | `scenes/discovery/discovery_card.tscn` | `discovery_card.gd` | Server icon, name, members, hover |
| 17.3 | Discovery detail | `scenes/discovery/discovery_detail.tscn` | `discovery_detail.gd` | Full server info, join button |

### 18. Search

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 18.1 | Search panel | `scenes/search/search_panel.tscn` | `search_panel.gd` | Empty, with results, no results, loading |
| 18.2 | Search result item | `scenes/search/search_result_item.tscn` | `search_result_item.gd` | Message preview with jump-to |

### 19. Video & Voice

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 19.1 | Video grid | `scenes/video/video_grid.tscn` | `video_grid.gd` | 1 participant, 2-4 grid, spotlight mode, with activity overlay |
| 19.2 | Video tile | `scenes/video/video_tile.tscn` | `video_tile.gd` | Camera on, camera off, muted, speaking indicator, screen share |
| 19.3 | Video PiP | `scenes/video/video_pip.tscn` | — | Picture-in-picture window |
| 19.4 | Vertical resize handle | — | `vertical_resize_handle.gd` | Drag handle for grid height |

### 20. Soundboard

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 20.1 | Soundboard panel | `scenes/soundboard/soundboard_panel.tscn` | `soundboard_panel.gd` | Sound buttons, playing state, empty state |

### 21. Plugins

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 21.1 | Activity modal | — | `activity_modal.gd` | Available activities list |
| 21.2 | Activity lobby | — | `activity_lobby.gd` | Player slots, waiting, host controls |
| 21.3 | Plugin trust dialog | — | `plugin_trust_dialog.gd` | Trust prompt (once/always/deny) |
| 21.4 | Plugin canvas | — | `plugin_canvas.gd` | Plugin rendered content area |

### 22. Common / Reusable

| # | Surface | Scene File | Script | States to Capture |
|---|---------|------------|--------|-------------------|
| 22.1 | Modal base | `scenes/common/modal_base.tscn` | `modal_base.gd` | Backdrop, open/close animation |
| 22.2 | Avatar | `scenes/common/avatar.tscn` | — | User avatar, server icon, placeholder, loading |
| 22.3 | Group avatar | `scenes/common/group_avatar.tscn` | — | Multi-user composite avatar |

## Responsive Variants

Every surface in sections 1-21 must be captured at three breakpoints:

| Layout Mode | Width | Behavior |
|-------------|-------|----------|
| COMPACT | <500px | Sidebar becomes drawer overlay; single-panel content |
| MEDIUM | <768px | Sidebar visible; member list/thread panel hidden by default |
| FULL | >=768px | All panels visible simultaneously |

Responsive layout is driven by `AppState.current_layout_mode` and handled in `main_window.gd`.

## Implementation Details

### Screenshot Capture Strategy
The audit requires systematic navigation through all states. Key entry points:

- **Main window** (`scenes/main/main_window.gd`): The root scene. All other views are children or popups launched from here.
- **AppState signals** (`scripts/autoload/app_state.gd`): Driving all view transitions. Key signals include `guild_selected`, `channel_selected`, `dm_mode_changed`, `settings_opened`, `voice_joined`, `profile_card_requested`.
- **Dialog launches**: Most dialogs are instantiated via `preload()` and shown with `.popup()` or `.show()` — they must be triggered through their normal UI paths to capture accurate state.

### Context Menus (Hidden Surfaces)
Right-click context menus exist on:
- Messages (edit, delete, reply, react, pin, copy)
- Channel items (edit, delete, permissions, mute)
- Member items (profile, message, moderate, roles)
- Guild icons (settings, leave, notifications)
- Category items (edit, delete, create channel)

These are generated dynamically via `PopupMenu` and must be triggered interactively.

### Platform-Specific Surfaces
| Platform | Differences |
|----------|-------------|
| Web | Guest banner, shareable URL bar, WebVoiceSession (no screen share) |
| Android | Touch gestures, edge-swipe drawer, on-screen keyboard adjustments |
| Desktop (Linux/Windows) | Screen picker dialog, system tray, native file dialogs |

## Implementation Status
- [x] All scene files exist and are loadable
- [x] Responsive layout modes (COMPACT/MEDIUM/FULL) implemented
- [x] All admin dialogs accessible via server management panel
- [x] Profile card popup on member click
- [x] Context menus on messages, channels, members
- [ ] Automated screenshot capture tooling (not yet built)
- [ ] Design system documentation (colors, typography, spacing tokens)
- [ ] Figma/design file with current state
- [ ] Accessibility audit annotations (contrast ratios, focus order)
- [ ] Dark/light theme variant captures

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| No automated screenshot tooling | High | Need a script or test harness that navigates to each surface and captures screenshots programmatically; consider GUT test + `get_viewport().get_texture().get_image().save_png()` |
| No design tokens file | Medium | Colors, fonts, spacing are defined inline in `.tscn` theme overrides — no central design system file to audit against |
| Context menus not cataloged in scenes | Medium | PopupMenu instances are created in code, not `.tscn` files — must be triggered interactively to capture |
| No dark/light theme toggle | Medium | App currently has single theme; audit should note if a second theme is planned |
| Platform-specific surfaces need separate passes | Medium | Web guest mode, Android touch targets, and desktop-only dialogs (screen picker) require platform-specific test runs |
| No Figma/design source of truth | High | Without a design file, the audit can only compare against general UX heuristics, not intended designs |
| Loading/error states underspecified | Low | Many dialogs lack explicit error state designs — auditor should flag where error feedback is missing |
| Animation timing not auditable from screenshots | Low | Transitions and animations (`modal_base.gd` open/close, drawer slide) need video capture or live review |

## Audit Execution Plan

### Phase 1: Static Capture (Screenshots)
1. Launch app at each breakpoint (resize window or use `--resolution` flag)
2. Navigate to each surface in the checklist above
3. Capture default state + all listed variant states
4. Name files: `{section}_{number}_{state}.png` (e.g., `6.2_cozy_message_with_reply.png`)

### Phase 2: Design Review
1. Designer reviews all captures for visual consistency
2. Check: spacing, alignment, typography hierarchy, color usage, icon consistency
3. Flag: misaligned elements, inconsistent padding, orphaned styles

### Phase 3: UX Review
1. UX expert reviews all captures for usability
2. Check: information hierarchy, discoverability, cognitive load, error recovery
3. Flag: confusing flows, missing affordances, accessibility barriers

### Phase 4: Remediation
1. Prioritize findings by severity (High/Medium/Low)
2. Create issues per finding with screenshot + recommendation
3. Track fixes against this checklist

## Total Surface Count

| Category | Surfaces |
|----------|----------|
| Main Window & Navigation | 5 |
| Guild Bar | 11 |
| Channel List | 7 |
| DMs & Friends | 7 |
| User Bar & Voice Bar | 3 |
| Message View | 14 |
| Composer | 4 |
| Threads & Forums | 5 |
| Members | 4 |
| User Profile & Settings | 14 |
| Admin — Server/Space | 4 |
| Admin — Channels | 7 |
| Admin — Roles | 2 |
| Admin — Moderation | 9 |
| Admin — Invites/Reports | 7 |
| Admin — Content/Customization | 7 |
| Discovery | 3 |
| Search | 2 |
| Video & Voice | 4 |
| Soundboard | 1 |
| Plugins | 4 |
| Common/Reusable | 3 |
| **Total** | **121** |

Each surface requires multiple state captures (avg ~3-4 states), yielding an estimated **350-500 screenshots** for a complete audit across all three responsive breakpoints.
