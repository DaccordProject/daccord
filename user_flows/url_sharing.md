# URL Sharing

Priority: 82
Depends on: URL Protocol, Space & Channel Navigation, Messaging

## Overview

"Copy Link" context menu actions on spaces, channels, and messages that generate shareable `daccord://` deep links and copy them to the clipboard. Recipients clicking these links open daccord and navigate directly to the linked location. Builds on the existing `UriHandler` autoload and `daccord://` URI scheme (see `url_protocol.md`). This flow addresses URL-3 from the URL Protocol user flow ("No URL generation / sharing UI").

## URL Formats

| Context | Generated URL | Example |
|---------|--------------|---------|
| Space | `daccord://connect/<host>[:<port>]/<space-slug>` | `daccord://connect/chat.example.com/general` |
| Channel | `daccord://connect/<host>[:<port>]/<space-slug>?channel=<channel-name>` | `daccord://connect/chat.example.com/general?channel=announcements` |
| Message | `daccord://navigate/<space-id>/<channel-id>?msg=<message-id>` | `daccord://navigate/123456/789012?msg=345678` |

Space and channel links use the `connect` route with human-readable host + slug, so they work for users who aren't already connected to the server. Message links use the `navigate` route with snowflake IDs, which only works for users already connected to the same space.

## User Steps

### Copy Server Link (space icon context menu)

1. User right-clicks a space icon in the space bar
2. Context menu appears with existing items (Administration, Mute, Folder, Remove)
3. User clicks **Copy Server Link**
4. `daccord://connect/<host>/<space-slug>` is copied to clipboard
5. Toast notification shows "Link copied!" briefly at the bottom of the window

### Copy Channel Link (channel item context menu)

1. User right-clicks a channel in the channel list
2. Context menu appears with existing items (Mute, Notification Settings, Edit, Delete)
3. User clicks **Copy Channel Link**
4. `daccord://connect/<host>/<space-slug>?channel=<channel-name>` is copied to clipboard
5. Toast notification shows "Link copied!"

### Copy Message Link (message context menu)

1. User right-clicks a message (or long-presses on mobile)
2. Context menu appears with existing items (Reply, Edit, Delete, Reaction, Thread, Report)
3. User clicks **Copy Message Link**
4. `daccord://navigate/<space-id>/<channel-id>?msg=<message-id>` is copied to clipboard
5. Toast notification shows "Link copied!"

### Recipient opens a shared link

1. Recipient clicks or pastes the `daccord://` URL
2. OS routes to daccord via registered protocol handler (see `url_protocol.md`)
3. For `connect` links: AddServerDialog opens pre-filled; if already connected, navigates directly
4. For `navigate` links: daccord navigates to the space/channel (and scrolls to the message, once implemented)

## Signal Flow

```
User right-clicks space/channel/message
    |
    v
PopupMenu._show_context_menu() adds "Copy ... Link" item
    |
    v
User clicks "Copy ... Link"
    |
    v
_on_context_menu_id_pressed() matches the item
    |
    v
UriHandler.build_connect_url(host, port, space_slug, channel_name)
    or UriHandler.build_navigate_url(space_id, channel_id, message_id)
    |
    v
DisplayServer.clipboard_set(url)
    |
    v
MainWindow._overlays.show_toast(tr("Link copied!"))
    (or local toast pattern — see implementation details)
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/uri_handler.gd` | URL builder statics: `build_base_url()` (line 228), `build_connect_url()` (line 235), `build_navigate_url()` (line 249); query param parsing for `?channel=` (line 99) and `?msg=` (line 177); auto-navigate on connect (line 260) |
| `scripts/autoload/app_state.gd` | `toast_requested` signal (line 130), `navigate_to_message` signal (line 132) |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Space context menu: "Copy Server Link" item (line 237), handler (line 303), `_copy_server_link()` (line 308) |
| `scenes/sidebar/channels/channel_item.gd` | Channel context menu: "Copy Channel Link" item (line 222), handler (line 234), `_on_copy_channel_link()` (line 257) |
| `scenes/messages/message_view_actions.gd` | Message context menu: "Copy Message Link" item (line 35), handler (line 136), `_copy_message_link()` (line 222); guest mode exemption (line 94) |
| `scenes/main/main_window.gd` | `toast_requested` connection (line 115), `_on_toast_requested()` handler (line 678) |
| `scenes/admin/invite_row.gd` | Reference implementation: `_build_invite_url()` (line 27), `_on_copy()` (line 22) |
| `scripts/autoload/client.gd` | `get_base_url_for_space()` (line 750), `get_space_by_id()` (line 495), `_channel_to_space` (line 135), `_channel_cache` (line 101) |
| `scripts/client/client_models_space.gd` | `space_to_dict()` (line 20) includes `slug` (line 35); `channel_to_dict()` (line 60) includes `name` (line 75) and `space_id` (line 67) |
| `scenes/main/main_window_overlays.gd` | `show_toast()` (line 91) — instantiates toast PanelContainer |
| `scenes/main/toast.gd` | Toast widget: auto-positioned, 4s display, fade-out dismiss (line 58-65) |
| `tests/unit/test_uri_handler.gd` | Unit tests for `build_connect_url` (lines 157-181), `build_navigate_url` (lines 186-196), `?channel=` parsing (lines 200-213), `?msg=` parsing (lines 218-227) |

## Implementation Details

### URL Builder Helpers (uri_handler.gd)

Two static methods on `UriHandler` alongside `build_base_url()` (line 228):

**`build_connect_url(host, port, space_slug, channel_name)`:**
- Constructs `daccord://connect/<host>[:<port>]/<space-slug>[?channel=<channel-name>]`
- Omits port when 443 (same logic as `build_base_url`, line 210)
- Omits `?channel=` when `channel_name` is empty (space-only link)
- Channel name is URL-encoded to handle special characters

**`build_navigate_url(space_id, channel_id, message_id)`:**
- Constructs `daccord://navigate/<space-id>/<channel-id>[?msg=<message-id>]`
- Omits `?msg=` when `message_id` is empty (channel-only navigate)

### Extracting Host from Base URL

The existing pattern from `invite_row.gd` (line 31) strips the scheme:
```gdscript
var host := base_url.replace("https://", "").replace("http://", "")
```

`Client.get_base_url_for_space(space_id)` (line 750) returns the full base URL including scheme (e.g., `https://chat.example.com` or `https://chat.example.com:8443`). The host extraction strips the scheme, preserving any port suffix.

### Space Context Menu — "Copy Server Link" (guild_icon.gd)

**Current menu structure** (`_show_context_menu`, line 157-250):
1. Administration submenu (permission-gated)
2. Server Settings / Server Reports (admin-only)
3. Reconnect (if disconnected)
4. Mute/Unmute Server
5. Move to/Remove from Folder
6. Separator
7. Remove Server

**Proposed insertion point:** After Mute/Unmute Server (line 235), before the folder item. The "Copy Server Link" item is always shown (no permission gate — any connected user can share a server link).

**Data available:**
- `space_id` instance variable (line 21) — used with `Client.get_base_url_for_space()` to get the host
- `Client.get_space_by_id(space_id)` returns a dict with `"slug"` key (from `client_models_space.gd` line 35)

**Handler** (`_on_context_menu_id_pressed`, line 276): Uses label-based dispatch. Match `tr("Copy Server Link")`, call `UriHandler.build_connect_url()`, copy to clipboard via `DisplayServer.clipboard_set()`.

### Channel Context Menu — "Copy Channel Link" (channel_item.gd)

**Current menu structure** (`_show_context_menu`, line 209-227):
1. Mute/Unmute Channel (id 10)
2. Notification Settings submenu (id 11)
3. Separator (if has MANAGE_CHANNELS permission)
4. Edit Channel (id 0)
5. Delete Channel (id 1)

**Proposed insertion point:** After Notification Settings (line 220), before the admin separator. Uses a new menu item id (e.g., 12).

**Data available:**
- `space_id` instance variable (line 14) — for `Client.get_base_url_for_space()` and `Client.get_space_by_id()`
- `_channel_data` dict (line 19) — contains `"name"` key (from `client_models_space.gd` line 75)

**Handler** (`_on_context_menu_id_pressed`, line 229): Add a new match arm for id 12. Build URL using space slug + channel name, copy to clipboard.

### Message Context Menu — "Copy Message Link" (message_view_actions.gd)

**Current menu structure** (`setup_context_menu`, line 26-36):
- Reply (id 0), Edit (id 1), Delete (id 2), Add Reaction (id 3), Remove All Reactions (id 4), Start Thread (id 5), Report (id 6)

**Proposed insertion:** Add "Copy Message Link" as id 7 after Report (line 34). Not disabled in guest mode — guests can share links too.

**Data available from `_context_menu_data`:**
- `"id"` — message snowflake ID
- `"channel_id"` — channel snowflake ID
- `Client._channel_to_space.get(channel_id, "")` — resolves to space_id (line 105-107)

**Handler** (`on_context_menu_id_pressed`, line 133): Add match arm for id 7. Does not need `GuestPrompt.show_if_guest()` guard — copying a link is a read-only action. Build navigate URL, copy to clipboard.

### Toast Feedback

Two toast patterns exist in the codebase:

1. **`main_window_overlays.show_toast()`** (line 91): Instantiates `ToastScene`, adds to MainWindow. Used by `main_window.gd` for voice errors (line 675). The toast auto-positions at the bottom center, shows for 4 seconds, then fades out (toast.gd line 58-65).

2. **Inline label toast** (`user_bar.gd` line 329-350): Creates a temporary Label styled as `text_muted`, auto-removes after 2 seconds. Simpler but less polished.

For context menu copy actions, the overlays toast is preferred. The challenge is accessing `_overlays.show_toast()` from components that don't have a reference to `MainWindow._overlays`. Options:

- **AppState signal:** Add a `signal toast_requested(text: String)` to `AppState`, connect in `main_window.gd` to `_overlays.show_toast()`. Context menu handlers emit `AppState.toast_requested.emit(tr("Link copied!"))`.
- **Direct tree walk:** Components can find MainWindow via `get_tree().root.get_node_or_null("MainWindow")` (same pattern used by `UriHandler._open_add_server_prefilled`, line 290). Less clean but avoids adding a signal.

The AppState signal approach is cleaner and reusable for other copy/clipboard feedback in the future.

### Receiving Side — UriHandler Changes

The `connect` route parser (`_parse_connect`, line 83-134) already handles query parameters (line 88-99) but only recognizes `token` and `invite`. To support `?channel=<name>`, a new `channel` key needs to be added to the query parameter matching.

The `navigate` route parser (`_parse_navigate`, line 174-188) uses path segments only. To support `?msg=<id>`, query parameter extraction needs to be added.

**Connect route with channel:**
- `_parse_connect` adds `"channel"` to the parsed dictionary when `?channel=` is present
- `_handle_connect` (line 232) passes the channel name through to AddServerDialog, or if already connected, calls `AppState.select_channel()` after finding the channel by name in `Client._channel_cache`

**Navigate route with message:**
- `_parse_navigate` extracts `?msg=` query parameter and includes `"message_id"` in the result
- `_handle_navigate` (line 267) passes the message ID for scroll-to-message behavior (requires message view support)

### Existing Reference: invite_row.gd

`invite_row.gd` demonstrates the complete copy-to-clipboard pattern:
1. `_build_invite_url()` (line 27-32): Gets base URL via `Client.get_base_url_for_space()`, strips scheme, constructs `daccord://invite/<code>@<host>`
2. `_on_copy()` (line 22-25): Calls `DisplayServer.clipboard_set(url)`, emits `copy_requested` signal
3. Parent (`invite_management_dialog.gd`) can react to the signal for UI feedback

### Web Platform Consideration

On web exports, `DisplayServer.clipboard_set()` requires a user gesture (click) to write to the clipboard. Context menu clicks satisfy this requirement, so clipboard writes from PopupMenu handlers work correctly. The existing `app_settings.gd` "Copy Theme" (line 543) and `user_settings_twofa.gd` copy buttons (lines 337, 344, 351) confirm this pattern works on web.

## Implementation Status

- [x] `daccord://` URL scheme and parser (`uri_handler.gd`)
- [x] `build_base_url()` static helper (`uri_handler.gd` line 228)
- [x] Invite copy-to-clipboard reference implementation (`invite_row.gd` lines 22-32)
- [x] Space context menu infrastructure (`guild_icon.gd` lines 50-52, 157-252, 278-304)
- [x] Channel context menu infrastructure (`channel_item.gd` lines 48-51, 209-228, 229-235)
- [x] Message context menu infrastructure (`message_view_actions.gd` lines 26-37, 133-212)
- [x] Toast notification system (`toast.gd`, `main_window_overlays.gd` line 91)
- [x] `Client.get_base_url_for_space()` for host extraction (`client.gd` line 750)
- [x] Space `slug` field in data model (`client_models_space.gd` line 35)
- [x] `UriHandler.build_connect_url()` static method (`uri_handler.gd` line 235)
- [x] `UriHandler.build_navigate_url()` static method (`uri_handler.gd` line 249)
- [x] "Copy Server Link" in space context menu (`guild_icon.gd` line 237, handler line 303, impl line 308)
- [x] "Copy Channel Link" in channel context menu (`channel_item.gd` line 222, handler line 234, impl line 257)
- [x] "Copy Message Link" in message context menu (`message_view_actions.gd` line 35, handler line 136, impl line 222)
- [x] `AppState.toast_requested` signal for clipboard feedback (`app_state.gd` line 130)
- [x] `MainWindow` connection to `toast_requested` -> `_overlays.show_toast()` (`main_window.gd` line 115, handler line 678)
- [x] `_parse_connect` support for `?channel=` query parameter (`uri_handler.gd` line 99)
- [x] `_parse_navigate` support for `?msg=` query parameter (`uri_handler.gd` line 177)
- [x] `_handle_connect` auto-navigate to channel when already connected (`uri_handler.gd` line 260)
- [x] `_handle_navigate` emit `navigate_to_message` when `msg` ID is provided (`uri_handler.gd` line 303)
- [x] Unit tests for `build_connect_url()` and `build_navigate_url()` (`test_uri_handler.gd` lines 157-213)
- [ ] `message_view.gd` scroll-to-message on `navigate_to_message` signal (message fetching if not in current page)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Scroll-to-message on navigate | Medium | `navigate_to_message` signal emitted but no listener in `message_view.gd` — message may not be in current page, needs fetch-then-scroll |
| Category context menu "Copy Link" | Low | Categories aren't directly navigable; SHARE-8 deferred |

## Tasks

### SHARE-1: Add URL builder statics to UriHandler
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** core
- **Notes:** Added `build_connect_url()` (line 235) and `build_navigate_url()` (line 249) as static methods in `uri_handler.gd`. Unit tests added in `test_uri_handler.gd` (lines 157-213).

### SHARE-2: Add "Copy Server Link" to space context menu
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** ui
- **Notes:** Added "Copy Server Link" item in `guild_icon.gd` `_show_context_menu()` (line 237) after Mute/Unmute. Handler dispatches via label match (line 303) to `_copy_server_link()` (line 308). Not shown when disconnected (early return at line 165).

### SHARE-3: Add "Copy Channel Link" to channel context menu
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** ui
- **Notes:** Added "Copy Channel Link" (id 12) in `channel_item.gd` `_show_context_menu()` (line 222). Handler in match (line 234) calls `_on_copy_channel_link()` (line 257). Only shown when `space_id` is non-empty.

### SHARE-4: Add "Copy Message Link" to message context menu
- **Status:** done
- **Impact:** 2
- **Effort:** 1
- **Tags:** ui
- **Notes:** Added "Copy Message Link" (id 7) in `message_view_actions.gd` `setup_context_menu()` (line 35). Handled before guest prompt check (line 136) since it's read-only. Guest mode keeps this item enabled while disabling others (line 94). `_copy_message_link()` at line 222.

### SHARE-5: Toast feedback for clipboard copy
- **Status:** done
- **Impact:** 2
- **Effort:** 1
- **Tags:** ui
- **Notes:** Added `signal toast_requested(text: String)` to `AppState` (line 130). Connected in `main_window.gd` (line 115) to `_on_toast_requested()` (line 678) which calls `_overlays.show_toast()`. All copy handlers emit `AppState.toast_requested.emit(tr("Link copied!"))`.

### SHARE-6: Connect route `?channel=` support
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** core
- **Notes:** `_parse_connect` now recognizes `?channel=<name>` (line 99, URI-decoded). `_handle_connect` checks if already connected and auto-navigates (line 260) via `_navigate_to_channel_by_name()` (line 350).

### SHARE-7: Navigate route `?msg=` support and scroll-to-message
- **Status:** partial
- **Impact:** 2
- **Effort:** 3
- **Tags:** core, ui
- **Notes:** `_parse_navigate` now extracts `?msg=<id>` (line 177). `_handle_navigate` emits `AppState.navigate_to_message` signal (line 303). Signal declared in `app_state.gd` (line 132). **Remaining:** `message_view.gd` listener to scroll to the message ID and potentially fetch it if not loaded.

### SHARE-8: Category context menu "Copy Link"
- **Status:** open
- **Impact:** 1
- **Effort:** 1
- **Tags:** ui
- **Notes:** `category_item.gd` has a context menu (`_show_context_menu`, line 163-178). Could add "Copy Channel Link" for the category's first channel, but low priority — categories aren't directly navigable.
