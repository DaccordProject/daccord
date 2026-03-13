# Responsive Layout

Priority: 9
Depends on: Space & Channel Navigation, Messaging

## Overview

daccord adapts its layout to three viewport width breakpoints: COMPACT (<500px), MEDIUM (500-767px), and FULL (>=768px). In FULL and MEDIUM modes, the sidebar sits in the main layout and can be toggled via a sidebar toggle button. In COMPACT mode, the entire sidebar moves to a drawer overlay that slides in from the left with a 0.2s animation, toggled by a hamburger button or edge-swipe gesture. Side panels (member list, search, thread, voice text) appear in the content body in FULL/MEDIUM modes with draggable resize handles. All drawer and panel animations respect the reduced-motion accessibility preference.

## User Steps

1. Application window resizes -> viewport width recalculated
2. `AppState.update_layout_mode(viewport_width)` determines new mode (line 281)
3. If mode changed, `layout_mode_changed` signal emitted (line 291)
4. Components adapt: sidebar position, panel visibility, header buttons, grid columns

FULL mode interactions (>=768px):
1. Sidebar visible in layout, channel panel respects toggle state
2. Sidebar toggle button toggles channel panel visibility
3. Member list toggle shows/hides member panel
4. Search toggle shows/hides search panel
5. Thread panel appears alongside message view with resize handle
6. Resize handles visible on all side panels (thread, member list, search, voice text)

MEDIUM mode interactions (500-767px):
1. Sidebar visible in layout, channel panel respects toggle state
2. Sidebar toggle button toggles channel panel visibility
3. Member list forced hidden on mode entry, toggle available to re-show
4. Search toggle shows/hides search panel
5. Space/DM selection shows channel panel; channel selection hides it (via sidebar.gd)
6. Resize handles visible on side panels

COMPACT mode interactions (<500px):
1. User taps hamburger button (44x44px) in content header, or swipes right from left edge (20px zone, 80px threshold)
2. Drawer slides in from left (sidebar + backdrop fade); drawer width adapts to viewport (max 308px, min 60px backdrop tap target preserved)
3. User selects space -> channel list appears inside drawer
4. User selects channel -> drawer auto-closes, messages load
5. Member list, search panel, and their toggles are all hidden
6. Thread panel replaces message view (back button instead of close X)
7. Action bar (hover toolbar) is disabled; context menu via long-press only
8. Video grid shows 1 column instead of 2
9. Forum view uses compact title font and "+" button instead of "New Post"

## Signal Flow

```
Window resize
    -> get_viewport().size_changed signal
    -> main_window._on_viewport_resized() (line 324)
        -> vp_size = get_viewport().get_visible_rect().size
        -> AppState.update_layout_mode(vp_size.x, vp_size.y)
            -> Determines COMPACT/MEDIUM/FULL based on breakpoint constants
            -> If changed: current_layout_mode = new_mode
            -> layout_mode_changed.emit(new_mode)
    -> If drawer is open: recalculates drawer width (line 328)
    -> main_window._on_layout_mode_changed(mode) (line 331)
        -> Voice view exception: if is_voice_view_open, only handles
           sidebar/drawer transitions, skips content visibility (lines 332-347)
        -> match mode:
            FULL:
                _drawer.move_sidebar_to_layout(), sidebar visible
                channel panel = AppState.channel_panel_visible (immediate)
                hamburger hidden, sidebar_toggle visible
                restores member_list_visible from _member_list_before_medium
                member list/search updated per state
                _sync_handle_visibility()
            MEDIUM:
                _drawer.move_sidebar_to_layout(), sidebar visible
                channel panel = AppState.channel_panel_visible (immediate)
                hamburger hidden, sidebar_toggle visible
                saves member_list_visible, then forces false
                member list/search updated per state
                _sync_handle_visibility()
            COMPACT:
                _drawer.move_sidebar_to_drawer()
                channel panel forced visible (immediate)
                hamburger visible, sidebar_toggle hidden
                member toggle/list hidden, search toggle/panel hidden
                AppState.close_search()
                _sync_handle_visibility()
                if thread_panel_visible: message_view hidden

Sidebar toggle (FULL/MEDIUM):
    -> main_window._on_sidebar_toggle_pressed() (line 450)
        -> AppState.toggle_channel_panel()
            -> channel_panel_visible toggled
            -> channel_panel_toggled.emit(is_visible)
    -> main_window._on_channel_panel_toggled(panel_visible) (line 453)
        -> sidebar.set_channel_panel_visible(panel_visible) [if not COMPACT]

Member list toggle (FULL/MEDIUM):
    -> main_window._on_member_toggle_pressed() (line 457)
        -> AppState.toggle_member_list()
            -> member_list_visible toggled
            -> member_list_toggled.emit(is_visible)
    -> main_window._on_member_list_toggled() (line 460)
        -> _update_member_list_visibility()
        -> _sync_handle_visibility()

Search toggle (FULL/MEDIUM):
    -> main_window._on_search_toggle_pressed() (line 464)
        -> AppState.toggle_search()
            -> search_open toggled
            -> search_toggled.emit(is_open)
    -> main_window._on_search_toggled(is_open) (line 467)
        -> search_panel.visible = is_open
        -> _sync_handle_visibility()
        -> if opening: search_panel.activate(current_space_id)

Hamburger button (COMPACT only):
    -> main_window._on_hamburger_pressed() (line 533)
        -> AppState.toggle_sidebar_drawer()
            -> sidebar_drawer_open toggled
            -> sidebar_drawer_toggled.emit(is_open)
    -> _drawer.on_sidebar_drawer_toggled(is_open) (main_window_drawer.gd:61)
        -> open_drawer() or close_drawer()

Drawer open triggers:
    - Hamburger button tap
    - Edge swipe gesture (touch or mouse drag from left 20px, exceeding 80px threshold)
    - Interactive drag tracking with velocity-based snap (drawer_gestures.gd)

Drawer close triggers:
    - Clicking/touching DrawerBackdrop (main_window._on_backdrop_input, line 536)
    - Swipe-to-close gesture (drag left on backdrop area, drawer_gestures.gd:174)
    - Selecting a channel (sidebar._on_channel_selected -> AppState.close_sidebar_drawer)
    - Selecting a DM (sidebar._on_dm_selected_channel -> AppState.close_sidebar_drawer)
    - Layout mode changing away from COMPACT (_drawer.close_drawer_immediate)

Thread panel in COMPACT:
    -> AppState.thread_opened -> main_window._on_thread_opened() (line 473)
        -> message_view.visible = false (thread replaces messages)
    -> AppState.thread_closed -> main_window._on_thread_closed() (line 478)
        -> message_view.visible = true

DM mode entered:
    -> main_window._on_dm_mode_entered() (line 482)
        -> search_toggle hidden, search closed
        -> _update_member_list_visibility() (shows for group DMs only)

Space selected:
    -> main_window._on_space_selected() (line 487)
        -> _update_member_list_visibility()
        -> _update_search_visibility()
        -> AppState.close_search()

Component-specific layout listeners:
    -> thread_panel._on_layout_mode_changed() -> _apply_layout()
    -> video_grid._on_layout_mode_changed() -> _update_grid_columns()
    -> collapsed_message._on_layout_mode_changed() -> _apply_timestamp_visibility()
    -> welcome_screen._on_layout_mode_changed() -> _apply_layout()
    -> forum_view._on_layout_mode_changed() -> _apply_layout()
    -> message_view_hover.on_layout_mode_changed() -> hides action bar in COMPACT
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | `LayoutMode` enum (line 191), `COMPACT_BREAKPOINT`/`MEDIUM_BREAKPOINT` constants (lines 193-194), layout state vars, `update_layout_mode()` (line 281), `toggle_sidebar_drawer()`, `close_sidebar_drawer()`, `toggle_channel_panel()`, `toggle_member_list()`, `toggle_search()`, `close_search()` |
| `scenes/main/main_window.gd` | Layout orchestration, `_on_layout_mode_changed()` (line 331), panel toggle wiring, resize handle creation (lines 150-177), `_sync_handle_visibility()` (line 393), `_clamp_panel_widths()` (line 403), voice view exception handling (lines 332-347) |
| `scenes/main/main_window_drawer.gd` | `MainWindowDrawer` class: sidebar reparenting (`move_sidebar_to_layout`/`move_sidebar_to_drawer`), drawer open/close animations, `get_drawer_width()`, reduced-motion support |
| `scenes/main/drawer_gestures.gd` | `DrawerGestures` class: edge-swipe open (lines 37-89), swipe-to-close (lines 174-225), interactive drag tracking with velocity-based snap (`_should_snap_open`, line 279) |
| `scenes/main/panel_resize_handle.gd` | `PanelResizeHandle` class: draggable resize handles for side panels, double-click-to-reset, visibility tracks target panel |
| `scenes/main/main_window.tscn` | Scene structure: LayoutHBox, ContentHeader (HamburgerButton, SidebarToggle, TabBar, SearchToggle, MemberListToggle), TopicBar, ContentBody (MessageView, ThreadPanel, MemberList, SearchPanel, VoiceTextPanel), DrawerBackdrop, DrawerContainer |
| `scenes/sidebar/sidebar.gd` | MEDIUM mode channel panel auto-show/hide on space/channel selection (lines 83-113), `set_channel_panel_visible()` (animated, line 124), `set_channel_panel_visible_immediate()` (line 143) |
| `scenes/messages/collapsed_message.gd` | Responsive timestamp: always visible in COMPACT (line 82), hover-only in MEDIUM/FULL (lines 70-75) |
| `scenes/messages/thread_panel.gd` | `_apply_layout()` (line 223): COMPACT uses back-arrow button + min width 0; non-COMPACT uses X button + min width 340 |
| `scenes/messages/message_view_hover.gd` | `on_layout_mode_changed()` (line 118): hides action bar in COMPACT; `on_msg_hovered()` (line 33): suppresses hover in COMPACT |
| `scenes/messages/forum_view.gd` | `_apply_layout()` (line 319): COMPACT shrinks title font and collapses "New Post" to "+" icon |
| `scenes/video/video_grid.gd` | `_update_grid_columns()` (line 95): inline mode uses 1 col (COMPACT) or 2 cols (MEDIUM/FULL); full-area mode uses adaptive columns based on tile count |
| `scenes/main/welcome_screen.gd` | `_apply_layout()` (line 257): COMPACT switches feature cards from HBox to VBox layout |

## Implementation Details

### Breakpoints (app_state.gd)
- `COMPACT_BREAKPOINT` = 500.0 (line 193), `MEDIUM_BREAKPOINT` = 768.0 (line 194)
- `< COMPACT_BREAKPOINT` -> COMPACT
- `COMPACT_BREAKPOINT to MEDIUM_BREAKPOINT` -> MEDIUM
- `>= MEDIUM_BREAKPOINT` -> FULL
- Only emits signal when mode actually changes (line 289, avoids redundant updates)

### Layout State (app_state.gd)
- `current_layout_mode: LayoutMode` -- current breakpoint mode, default FULL (line 201)
- `sidebar_drawer_open: bool` -- drawer state in COMPACT mode (line 202)
- `member_list_visible: bool` -- member list toggle state, default true (line 203)
- `channel_panel_visible: bool` -- channel panel toggle state, default true (line 204)
- `search_open: bool` -- search panel toggle state, default false (line 205)
- `thread_panel_visible: bool` -- thread panel open state (line 216)
- `is_voice_view_open: bool` -- voice view state, affects layout mode handling (line 212)

### Layout Mode Handling (main_window.gd)
- `_on_layout_mode_changed()` (line 331) handles all three modes
- **Voice view exception** (lines 332-347): When `is_voice_view_open`, only sidebar/drawer transitions are handled; content visibility management is skipped entirely. This prevents the voice view from being disrupted by layout changes.
- **FULL** (lines 350-361): `_drawer.move_sidebar_to_layout()`, sidebar visible, channel panel set immediately, hamburger hidden, sidebar_toggle visible, restores `member_list_visible` from saved state, member list/search updated per state, `_sync_handle_visibility()`
- **MEDIUM** (lines 362-374): Same as FULL except saves `member_list_visible` to `_member_list_before_medium` then forces to false on entry
- **COMPACT** (lines 375-391): `_drawer.move_sidebar_to_drawer()`, channel panel forced visible (immediate), hamburger visible, sidebar_toggle/member_toggle/search_toggle all hidden, member_list/search_panel hidden, `AppState.close_search()` called. If `thread_panel_visible`, `message_view` hidden (thread replaces it)

### Sidebar Toggle (main_window.gd)
- `SidebarToggle` button (44x44px, flat, sidebar_toggle.svg icon, tooltip "Toggle channel list")
- Visible in FULL and MEDIUM modes, hidden in COMPACT
- Calls `AppState.toggle_channel_panel()` -> emits `channel_panel_toggled`
- `_on_channel_panel_toggled()` (line 453): calls `sidebar.set_channel_panel_visible()` (animated) when not in COMPACT mode

### Member List Toggle (main_window.gd)
- `MemberListToggle` button (44x44px, flat, members.svg icon, tooltip "Toggle member list")
- Calls `AppState.toggle_member_list()` -> emits `member_list_toggled`
- `_update_member_list_visibility()` (line 493): per-mode visibility logic
  - FULL: toggle visible, member_list follows `AppState.member_list_visible`
  - MEDIUM: toggle visible, member_list follows `AppState.member_list_visible`
  - COMPACT: toggle hidden, member_list hidden
  - DM mode: toggle hidden, member_list hidden (except group DMs, lines 496-507)

### Search Toggle (main_window.gd)
- `SearchToggle` button (44x44px, flat, search.svg icon, tooltip "Search messages")
- Calls `AppState.toggle_search()` -> emits `search_toggled`
- `_on_search_toggled()` (line 467): shows/hides search_panel, calls `search_panel.activate()` on open, syncs handle visibility
- `_update_search_visibility()` (line 519): per-mode visibility logic
  - FULL/MEDIUM: toggle visible, panel follows `AppState.search_open`
  - COMPACT: toggle hidden, panel hidden, search closed
  - DM mode: toggle hidden, panel hidden

### Topic Bar (main_window.gd)
- Label node below ContentHeader, hidden by default
- Font size 12, themed color `text_muted` (line 148)
- Shown when selected channel has a non-empty `topic` field (lines 271-275)
- Hidden in DM mode (DMs have no topic)

### Drawer System (main_window_drawer.gd)

The drawer logic is extracted into `MainWindowDrawer`, a `RefCounted` helper instantiated in `main_window._ready()` (line 64).

- `BASE_DRAWER_WIDTH` = 308px (line 6), `MIN_BACKDROP_TAP_TARGET` = 60px (line 7)
- `get_drawer_width()` (line 46): returns `min(308, viewport_width - 60)` for dynamic drawer sizing
- `move_sidebar_to_layout()` (line 37): Removes sidebar from DrawerContainer, adds to LayoutHBox at index 0. Guarded by `_sidebar_in_drawer` flag.
- `move_sidebar_to_drawer()` (line 51): Removes sidebar from LayoutHBox, adds to DrawerContainer, sets anchors PRESET_LEFT_WIDE, offset_right = drawer width.
- `open_drawer()` (line 68): Shows backdrop + container, tweens sidebar.position.x from -dw to 0 (0.2s, EASE_OUT, TRANS_CUBIC) and backdrop alpha from 0 to 1, parallel. Respects reduced motion.
- `close_drawer()` (line 91): Tweens sidebar.position.x from 0 to -dw (0.2s, EASE_IN, TRANS_CUBIC) and backdrop alpha from 1 to 0, then chains `hide_drawer_nodes()`. Respects reduced motion.
- `close_drawer_immediate()` (line 108): Kills tween, hides immediately. Used on layout mode transitions.
- `hide_drawer_nodes()` (line 114): Hides backdrop + container, resets `sidebar_drawer_open` flag.
- Previous tween killed before starting new animation (lines 69, 92)
- Drawer width recalculated on viewport resize if drawer is open (main_window.gd:328)

### DrawerBackdrop (main_window.tscn)
- ColorRect covering full viewport
- Color from theme `overlay` color (re-applied in `_apply_theme`, line 761)
- Invisible by default
- Click/touch closes drawer via `_on_backdrop_input()` (line 536). Guards against close gesture tracking (`_gestures.is_close_tracking`) to prevent double-close.

### HamburgerButton (main_window.tscn)
- 44x44px Button with menu.svg icon
- Flat style
- Tooltip: "Open sidebar"
- Invisible by default, shown only in COMPACT mode

### Gesture System (drawer_gestures.gd)

The gesture logic is extracted into `DrawerGestures`, a `RefCounted` helper instantiated in `main_window._ready()` (line 72). Only active in COMPACT mode (`main_window._input()`, line 237).

**Open swipe** (lines 37-89):
- `EDGE_SWIPE_ZONE` = 20px from left edge (line 3), `SWIPE_THRESHOLD` = 80px (line 4), `SWIPE_DEAD_ZONE` = 10px (line 5)
- Supports both `InputEventScreenTouch`/`InputEventScreenDrag` (touch) and `InputEventMouseButton`/`InputEventMouseMotion` (mouse)
- **Interactive tracking**: Once dead zone exceeded, drawer follows finger position in real-time (`_update_drawer_position`, line 109). Sidebar position and backdrop alpha interpolated based on drag progress.
- **Velocity tracking** (lines 116-122): Tracks swipe velocity for snap decisions.
- **Snap decision** (`_should_snap_open`, line 279): Uses `VELOCITY_THRESHOLD` (400px/s) -- fast swipes snap regardless of position; slow swipes snap at 50% progress (`SNAP_PROGRESS`, line 7).
- **Proportional animation**: Snap animations use remaining progress to determine duration (`maxf(0.2 * remaining, 0.05)`), so short snaps are fast.

**Close swipe** (lines 174-225):
- Triggered by touch/click on backdrop area (x > drawer width)
- Interactive drag tracking moves drawer leftward
- Same velocity-based snap logic as open swipe
- Tap on backdrop (without drag) falls through to `AppState.close_sidebar_drawer()`
- `is_close_tracking` property (line 9) exposes state so `_on_backdrop_input` can skip duplicate close calls

### Panel Resize Handles (panel_resize_handle.gd, main_window.gd)

Resize handles are dynamically created in `main_window._ready()` (lines 150-177) and placed before their target panels in the content body HBox.

**Four handles:**
- Thread panel handle: min 240px, max ratio 0.8 of parent, default 340px (line 152)
- Member list handle: min 180px, max 400px, default 240px (line 157)
- Search panel handle: min 240px, max 500px, default 340px (line 163)
- Voice text handle: min 240px, max 500px, default 300px (line 169)

**Handle behavior** (panel_resize_handle.gd):
- 6px wide draggable strip (`HANDLE_WIDTH`, line 6)
- `CURSOR_HSIZE` cursor on hover
- Drag to resize: calculates delta from drag start, clamps to min/max range (lines 80-99)
- Double-click resets to default width (`_reset_to_default`, line 108; `DOUBLE_CLICK_MS` = 400, line 7)
- Visual indicator: vertical line drawn on hover/drag (line 52)
- Auto-hides when target panel is hidden (`visibility_changed` connection, line 40)

**Visibility sync** (`_sync_handle_visibility`, main_window.gd:393):
- Handles hidden in COMPACT mode (all handles invisible)
- Each handle visible only when its target panel is visible and not COMPACT
- Called after every layout mode change, panel toggle, or thread open/close

**Panel width clamping** (`_clamp_panel_widths`, main_window.gd:403):
- Triggered on content body resize
- Reserves `MESSAGE_VIEW_MIN` = 300px for the message view (line 4)
- Accounts for handle widths (6px each)
- Scales visible panels down proportionally if they exceed budget, respecting hard minimums

### MEDIUM Mode Channel Panel Auto-Toggle (sidebar.gd)
- `_on_space_selected()` (line 68): Shows channel_panel (animated) and sets `AppState.channel_panel_visible = true` in MEDIUM mode (line 83)
- `_on_dm_selected()` (line 87): Shows channel_panel (animated) and sets `AppState.channel_panel_visible = true` in MEDIUM mode (line 92)
- `_on_channel_selected()` (line 96): Hides channel_panel (animated) and sets `AppState.channel_panel_visible = false` in MEDIUM mode (line 100)
- `_on_dm_selected_channel()` (line 106): Hides channel_panel (animated) and sets `AppState.channel_panel_visible = false` in MEDIUM mode (line 109)
- `set_channel_panel_visible()` (line 124): Tween-based animation (`CHANNEL_PANEL_ANIM_DURATION` = 0.15s) for channel panel show/hide. Respects reduced motion.
- `set_channel_panel_visible_immediate()` (line 143): Instant show/hide for mode transitions (no animation)

### DM Mode Panel Hiding (main_window.gd)
- On `dm_mode_entered` (line 482): search_toggle hidden, search closed
- `_update_member_list_visibility()` (line 493): Shows member list for group DMs only (checks `dm.get("is_group", false)`, line 501); hides for 1:1 DMs
- Space selection restores visibility via `_update_member_list_visibility()` and `_update_search_visibility()` (lines 489-491)

### Thread Panel Responsive Layout (thread_panel.gd)
- Listens to `layout_mode_changed` (line 47)
- `_apply_layout()` (line 223):
  - COMPACT: close button text = "← Back", `custom_minimum_size.x = 0` (fills available space)
  - Non-COMPACT: close button text = "X", `custom_minimum_size.x = 340`
- In COMPACT mode, thread panel replaces message view entirely (main_window.gd:388-391, 473-480)

### Video Grid Responsive Columns (video_grid.gd)
- Listens to `layout_mode_changed` (line 41)
- `_update_grid_columns()` (line 95):
  - **Inline mode** (thumbnail strip): COMPACT = 1 column, MEDIUM/FULL = 2 columns (lines 114-120)
  - **Full-area mode** (voice view): Adaptive columns based on tile count (1-5 cols for 1-25+ tiles, lines 101-112); spotlight/screen-share uses single-row strip (`columns = 99`, line 99)

### Welcome Screen Responsive Layout (welcome_screen.gd)
- Listens to `layout_mode_changed` (line 29)
- `_apply_layout()` (line 257):
  - COMPACT: Reparents feature cards from HBox into a dynamically created VBox (`_switch_features_to_vbox`, line 264)
  - Non-COMPACT: Moves feature cards back to original HBox (`_switch_features_to_hbox`, line 282)

### Forum View Responsive Layout (forum_view.gd)
- Listens to `layout_mode_changed` (line 36)
- `_apply_layout()` (line 319):
  - COMPACT: Title font size 14, "New Post" button collapses to "+" with tooltip (lines 322-324)
  - Non-COMPACT: Title font size 16, full "New Post" label (lines 326-328)

### Collapsed Message Responsive Timestamp (collapsed_message.gd)
- Listens to `layout_mode_changed` (line 29)
- `_apply_timestamp_visibility()` (line 80):
  - COMPACT: timestamp always visible (line 82)
  - MEDIUM/FULL: timestamp hidden by default, shown on mouse hover (lines 70-75)
- Timestamp shows condensed time (e.g., "10:31") extracted from full timestamp string (lines 39-44)

### Message Action Bar in COMPACT (message_view_hover.gd)
- `on_msg_hovered()` (line 33): Returns early if COMPACT, suppressing the floating action bar entirely
- `on_layout_mode_changed()` (line 118): Hides the action bar when transitioning to COMPACT mode
- Users rely on long-press context menu for message actions in COMPACT mode

### Reduced Motion Support
All animated transitions check `Config.get_reduced_motion()` and skip animations when enabled:
- Drawer open/close (main_window_drawer.gd:76, 94) -- instant position/alpha
- Drawer gesture snaps (drawer_gestures.gd:138, 155, 262) -- instant snap
- Channel panel toggle (sidebar.gd:125) -- delegates to `set_channel_panel_visible_immediate()`
- Welcome screen entrance animation (welcome_screen.gd:111) -- skipped entirely
- CTA pulse animation (welcome_screen.gd:184) -- skipped; stopped on preference change (line 328)

## Implementation Status

- [x] Three layout modes (COMPACT/MEDIUM/FULL) with viewport breakpoints
- [x] Sidebar reparenting between layout and drawer (MainWindowDrawer class)
- [x] Drawer slide-in/slide-out animation (0.2s cubic easing)
- [x] DrawerBackdrop semi-transparent overlay
- [x] Hamburger button toggle (COMPACT only)
- [x] Backdrop click/touch to close drawer
- [x] Auto-close drawer on channel/DM selection
- [x] Sidebar toggle button (FULL/MEDIUM) to show/hide channel panel
- [x] MEDIUM mode: channel panel auto-show on space selection, auto-hide on channel selection
- [x] Member list toggle (FULL/MEDIUM) with per-mode visibility
- [x] Search panel toggle (FULL/MEDIUM) with per-mode visibility
- [x] Topic bar display for channels with topics
- [x] DM mode hides member list and search toggles (group DM exception for member list)
- [x] Responsive timestamps in collapsed messages
- [x] Touch support for backdrop dismiss
- [x] Swipe-to-open drawer (edge swipe gesture with interactive tracking)
- [x] Swipe-to-close drawer (backdrop area gesture with velocity snap)
- [x] Channel panel toggle animation (0.15s tween slide)
- [x] Dynamic drawer width (adapts to viewport, preserves 60px backdrop tap target)
- [x] Breakpoint constants (`COMPACT_BREAKPOINT`, `MEDIUM_BREAKPOINT`)
- [x] Member list state restored on MEDIUM -> FULL transition
- [x] Distinct sidebar toggle icon (`sidebar_toggle.svg` vs `menu.svg`)
- [x] Thread panel replaces message view in COMPACT mode (back button navigation)
- [x] Voice view exception in layout mode handling
- [x] Panel resize handles (thread, member list, search, voice text) with drag + double-click reset
- [x] Panel width clamping (proportional scaling, 300px message view minimum)
- [x] Action bar suppressed in COMPACT mode (long-press context menu only)
- [x] Video grid responsive columns (1 col COMPACT, 2 col MEDIUM/FULL, adaptive in full-area)
- [x] Welcome screen responsive layout (VBox in COMPACT, HBox otherwise)
- [x] Forum view responsive layout (compact title + icon button)
- [x] Reduced motion support across all animations
- [x] Gesture velocity-based snap with proportional animation duration

## Tasks

No open tasks.
