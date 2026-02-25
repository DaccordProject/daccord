# Responsive Layout


## Overview

daccord adapts its layout to three viewport width breakpoints: COMPACT (<500px), MEDIUM (500-767px), and FULL (>=768px). In FULL and MEDIUM modes, the sidebar sits in the main layout and can be toggled via a sidebar toggle button. In COMPACT mode, the entire sidebar moves to a drawer overlay that slides in from the left with a 0.2s animation, toggled by a hamburger button. A member list panel and search panel appear in the content body in FULL/MEDIUM modes, with toggle buttons in the content header.

## User Steps

1. Application window resizes -> viewport width recalculated
2. `AppState.update_layout_mode(viewport_width, viewport_height)` determines new mode and landscape orientation
3. If mode changed, `layout_mode_changed` signal emitted
4. Components adapt: sidebar position, panel visibility, header buttons

FULL mode interactions:
1. Sidebar visible in layout, channel panel respects toggle state
2. Sidebar toggle button toggles channel panel visibility
3. Member list toggle shows/hides member panel
4. Search toggle shows/hides search panel

MEDIUM mode interactions:
1. Sidebar visible in layout, channel panel respects toggle state
2. Sidebar toggle button toggles channel panel visibility
3. Member list forced hidden on mode entry, toggle available to re-show
4. Search toggle shows/hides search panel
5. Space/DM selection shows channel panel; channel selection hides it (via sidebar.gd)

COMPACT mode interactions:
1. User taps hamburger button (44x44px) in content header, or swipes right from left edge (20px zone, 80px threshold)
2. Drawer slides in from left (sidebar + backdrop fade); drawer width adapts to viewport (max 308px, min 48px tap target preserved)
3. User selects space -> channel list appears inside drawer
4. User selects channel -> drawer auto-closes, messages load
5. Member list, search panel, and their toggles are all hidden

## Signal Flow

```
Window resize
    -> get_viewport().size_changed signal
    -> main_window._on_viewport_resized()
        -> vp_size = get_viewport().get_visible_rect().size
        -> AppState.update_layout_mode(vp_size.x, vp_size.y)
            -> Determines COMPACT/MEDIUM/FULL based on breakpoint constants
            -> If changed: current_layout_mode = new_mode
            -> layout_mode_changed.emit(new_mode)
            -> Computes landscape (width/height > 1.5)
            -> If orientation changed: orientation_changed.emit(is_landscape)
    -> main_window._on_layout_mode_changed(mode)
        -> match mode:
            FULL:
                sidebar in layout, channel panel = AppState.channel_panel_visible
                hamburger hidden, sidebar_toggle visible
                restores member_list_visible from before MEDIUM; member list/search updated per state
            MEDIUM:
                sidebar in layout, channel panel = AppState.channel_panel_visible
                hamburger hidden, sidebar_toggle visible
                saves member_list_visible, then forces false; search updated per state
            COMPACT:
                sidebar in drawer, channel panel forced visible
                hamburger visible, sidebar_toggle hidden
                member toggle/list hidden, search toggle/panel hidden

Sidebar toggle (FULL/MEDIUM):
    -> main_window._on_sidebar_toggle_pressed()
        -> AppState.toggle_channel_panel()
            -> channel_panel_visible toggled
            -> channel_panel_toggled.emit(is_visible)
    -> main_window._on_channel_panel_toggled(panel_visible)
        -> sidebar.set_channel_panel_visible(panel_visible) [if not COMPACT]

Member list toggle (FULL/MEDIUM):
    -> main_window._on_member_toggle_pressed()
        -> AppState.toggle_member_list()
            -> member_list_visible toggled
            -> member_list_toggled.emit(is_visible)
    -> main_window._on_member_list_toggled()
        -> _update_member_list_visibility()

Search toggle (FULL/MEDIUM):
    -> main_window._on_search_toggle_pressed()
        -> AppState.toggle_search()
            -> search_open toggled
            -> search_toggled.emit(is_open)
    -> main_window._on_search_toggled(is_open)
        -> search_panel.visible = is_open
        -> if opening: search_panel.activate(current_space_id)

Hamburger button (COMPACT only):
    -> main_window._on_hamburger_pressed()
        -> AppState.toggle_sidebar_drawer()
            -> sidebar_drawer_open toggled
            -> sidebar_drawer_toggled.emit(is_open)
    -> main_window._on_sidebar_drawer_toggled(is_open)
        -> _open_drawer() or _close_drawer()

Drawer open triggers:
    - Hamburger button tap
    - Edge swipe gesture (touch or mouse drag from left 20px, exceeding 80px threshold)

Drawer close triggers:
    - Clicking/touching DrawerBackdrop
    - Selecting a channel (sidebar._on_channel_selected -> AppState.close_sidebar_drawer)
    - Selecting a DM (sidebar._on_dm_selected_channel -> AppState.close_sidebar_drawer)
    - Layout mode changing away from COMPACT

DM mode entered:
    -> main_window._on_dm_mode_entered()
        -> member_toggle hidden, member_list hidden
        -> search_toggle hidden, search closed

Space selected:
    -> main_window._on_space_selected()
        -> _update_member_list_visibility()
        -> _update_search_visibility()
        -> AppState.close_search()
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | `LayoutMode` enum, `COMPACT_BREAKPOINT`/`MEDIUM_BREAKPOINT` constants, layout state vars (incl. `is_landscape`), `update_layout_mode()` (with landscape detection), `toggle_sidebar_drawer()`, `close_sidebar_drawer()`, `toggle_channel_panel()`, `toggle_member_list()`, `toggle_search()`, `close_search()` |
| `scenes/main/main_window.gd` | Layout orchestration, sidebar reparenting, drawer animations, panel toggle wiring |
| `scenes/main/main_window.tscn` | Scene structure: LayoutHBox, ContentHeader (HamburgerButton, SidebarToggle, TabBar, SearchToggle, MemberListToggle), TopicBar, ContentBody (MessageView, MemberList, SearchPanel), DrawerBackdrop, DrawerContainer |
| `scenes/sidebar/sidebar.gd` | MEDIUM mode channel panel auto-show/hide on space/channel selection, `set_channel_panel_visible()` (animated), `set_channel_panel_visible_immediate()` (for mode transitions) |
| `scenes/messages/collapsed_message.gd` | Responsive timestamp: always visible in COMPACT, hover-only in MEDIUM/FULL |
| `scenes/members/member_list.gd` | Member list panel with virtualized scrolling, status grouping |
| `scenes/search/search_panel.gd` | Search panel with `activate(space_id)` entry point |

## Implementation Details

### Breakpoints (app_state.gd)
- `COMPACT_BREAKPOINT` = 500.0, `MEDIUM_BREAKPOINT` = 768.0
- `< COMPACT_BREAKPOINT` -> COMPACT
- `COMPACT_BREAKPOINT to MEDIUM_BREAKPOINT` -> MEDIUM
- `>= MEDIUM_BREAKPOINT` -> FULL
- Only emits signal when mode actually changes (avoids redundant updates)
- Also computes landscape orientation (width/height > 1.5) and emits `orientation_changed` on change

### Layout State (app_state.gd)
- `current_layout_mode: LayoutMode` -- current breakpoint mode (default FULL)
- `sidebar_drawer_open: bool` -- drawer state in COMPACT mode
- `member_list_visible: bool` -- member list toggle state (default true)
- `channel_panel_visible: bool` -- channel panel toggle state (default true)
- `search_open: bool` -- search panel toggle state (default false)
- `is_landscape: bool` -- true when viewport width/height > 1.5

### Layout Mode Handling (main_window.gd)
- FULL: `_move_sidebar_to_layout()`, sidebar visible, channel panel set immediately, hamburger hidden, sidebar_toggle visible, restores `member_list_visible` from saved state, member list/search updated per state
- MEDIUM: Same as FULL except saves `member_list_visible` then forces to false on entry
- COMPACT: `_move_sidebar_to_drawer()`, channel panel forced visible (immediate), hamburger visible, sidebar_toggle/member_toggle/search_toggle all hidden, member_list/search_panel hidden, `AppState.close_search()` called

### Sidebar Toggle (main_window.gd)
- `SidebarToggle` button (44x44px, flat, sidebar_toggle.svg icon, tooltip "Toggle channel list")
- Visible in FULL and MEDIUM modes, hidden in COMPACT
- Calls `AppState.toggle_channel_panel()` -> emits `channel_panel_toggled`
- `_on_channel_panel_toggled()`: calls `sidebar.set_channel_panel_visible()` (animated) when not in COMPACT mode

### Member List Toggle (main_window.gd)
- `MemberListToggle` button (44x44px, flat, members.svg icon, tooltip "Toggle member list")
- Calls `AppState.toggle_member_list()` -> emits `member_list_toggled`
- `_update_member_list_visibility()`: per-mode visibility logic
  - FULL: toggle visible, member_list follows `AppState.member_list_visible`
  - MEDIUM: toggle visible, member_list follows `AppState.member_list_visible`
  - COMPACT: toggle hidden, member_list hidden
  - DM mode: toggle hidden, member_list hidden

### Search Toggle (main_window.gd)
- `SearchToggle` button (44x44px, flat, search.svg icon, tooltip "Search messages")
- Calls `AppState.toggle_search()` -> emits `search_toggled`
- `_on_search_toggled()`: shows/hides search_panel, calls `search_panel.activate()` on open
- `_update_search_visibility()`: per-mode visibility logic
  - FULL/MEDIUM: toggle visible, panel follows `AppState.search_open`
  - COMPACT: toggle hidden, panel hidden, search closed
  - DM mode: toggle hidden, panel hidden

### Topic Bar (main_window.tscn/main_window.gd)
- Label node below ContentHeader, hidden by default
- Font size 12, color `Color(0.58, 0.608, 0.643)` (lines 43-44)
- Shown when selected channel has a non-empty `topic` field (lines 72-77)
- Hidden in DM mode (DMs have no topic)

### Sidebar Reparenting (main_window.gd)
- `_move_sidebar_to_layout()`: Removes sidebar from DrawerContainer, adds to LayoutHBox at index 0
- `_move_sidebar_to_drawer()`: Removes sidebar from LayoutHBox, adds to DrawerContainer, sets anchors PRESET_LEFT_WIDE, offset_right = `_get_drawer_width()`
- `_sidebar_in_drawer: bool` flag prevents redundant reparenting

### Drawer Animation (main_window.gd)
- `BASE_DRAWER_WIDTH` = 308px, `MIN_BACKDROP_TAP_TARGET` = 48px
- `_get_drawer_width()`: returns `min(308, viewport_width - 48)` for dynamic drawer sizing
- `_open_drawer()`:
  - Shows DrawerBackdrop and DrawerContainer
  - Updates sidebar.offset_right to current drawer width
  - Tween: sidebar.position.x from -dw to 0 (0.2s, EASE_OUT, TRANS_CUBIC)
  - Tween: DrawerBackdrop.modulate.a from 0 to 1 (0.2s, parallel)
- `_close_drawer()`:
  - Tween: sidebar.position.x from 0 to -dw (0.2s, EASE_IN, TRANS_CUBIC)
  - Tween: DrawerBackdrop.modulate.a from 1 to 0 (0.2s, parallel)
  - Chains `_hide_drawer_nodes()` callback after animation
- `_close_drawer_immediate()`: Kills tween, hides immediately (used on mode change)
- Previous tween killed before starting new animation
- Drawer width recalculated on viewport resize if drawer is open

### Swipe-to-Open Drawer (main_window.gd)
- `_input()` handles edge-swipe gesture detection in COMPACT mode
- `EDGE_SWIPE_ZONE` = 20px from left edge, `SWIPE_THRESHOLD` = 80px drag distance
- Supports both `InputEventScreenTouch`/`InputEventScreenDrag` (touch) and `InputEventMouseButton`/`InputEventMouseMotion` (mouse)
- Only active when COMPACT mode and drawer is closed
- Opens drawer via `AppState.toggle_sidebar_drawer()` when threshold exceeded

### DrawerBackdrop (main_window.tscn)
- ColorRect covering full viewport (lines 98-105)
- Color: black with 0.5 alpha (semi-transparent overlay)
- Invisible by default
- Click/touch closes drawer via `_on_backdrop_input()` (lines 232-236)

### HamburgerButton (main_window.tscn)
- 44x44px Button with menu.svg icon
- Flat style
- Tooltip: "Open sidebar"
- Invisible by default, shown only in COMPACT mode

### MEDIUM Mode Channel Panel Auto-Toggle (sidebar.gd)
- `_on_space_selected()`: Shows channel_panel (animated) and sets `AppState.channel_panel_visible = true` in MEDIUM mode
- `_on_dm_selected()`: Shows channel_panel (animated) and sets `AppState.channel_panel_visible = true` in MEDIUM mode
- `_on_channel_selected()`: Hides channel_panel (animated) and sets `AppState.channel_panel_visible = false` in MEDIUM mode
- `_on_dm_selected_channel()`: Hides channel_panel (animated) and sets `AppState.channel_panel_visible = false` in MEDIUM mode
- `set_channel_panel_visible()`: Tween-based animation (0.15s) for channel panel show/hide
- `set_channel_panel_visible_immediate()`: Instant show/hide for mode transitions (no animation)

### DM Mode Panel Hiding (main_window.gd:170-174)
- On `dm_mode_entered`: member_toggle hidden, member_list hidden, search_toggle hidden, search closed
- Space selection restores visibility via `_update_member_list_visibility()` and `_update_search_visibility()` (lines 176-179)

### Collapsed Message Responsive Timestamp (collapsed_message.gd)
- In COMPACT mode: timestamp always visible (line 69-70)
- In MEDIUM/FULL modes: timestamp hidden by default, shown on mouse hover (lines 57-63)
- Listens to `AppState.layout_mode_changed` to update behavior (line 37)
- `_apply_timestamp_visibility()` (lines 68-72) applies initial and changed mode
- Timestamp shows condensed time (e.g., "10:31") extracted from full timestamp string (lines 43-48)

## Implementation Status

- [x] Three layout modes (COMPACT/MEDIUM/FULL) with viewport breakpoints
- [x] Sidebar reparenting between layout and drawer
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
- [x] DM mode hides member list and search toggles
- [x] Responsive timestamps in collapsed messages
- [x] Touch support for backdrop dismiss
- [x] Swipe-to-open drawer (edge swipe gesture in COMPACT mode)
- [x] Landscape/orientation detection (`is_landscape` state + `orientation_changed` signal)
- [x] Channel panel toggle animation (0.15s tween slide)
- [x] Dynamic drawer width (adapts to viewport, preserves 48px backdrop tap target)
- [x] Breakpoint constants (`COMPACT_BREAKPOINT`, `MEDIUM_BREAKPOINT`)
- [x] Member list state restored on MEDIUM -> FULL transition
- [x] Distinct sidebar toggle icon (`sidebar_toggle.svg` vs `menu.svg`)

## Gaps / TODO

| Gap | Severity | Status | Notes |
|-----|----------|--------|-------|
| Swipe-to-open drawer | Medium | Done | Edge-swipe gesture (20px zone, 80px threshold) opens drawer in COMPACT mode. Supports both touch and mouse. |
| Landscape/orientation detection | Low | Done | `AppState.is_landscape` and `orientation_changed` signal. Landscape = width/height > 1.5. |
| Channel panel toggle animation | Low | Done | Tween-based slide animation (0.15s) on `set_channel_panel_visible()`. Instant variant for mode transitions. |
| Dynamic drawer width | Low | Done | `_get_drawer_width()` caps at viewport width minus 48px tap target. Recalculates on resize. |
| Breakpoint constants | Low | Done | `COMPACT_BREAKPOINT` (500) and `MEDIUM_BREAKPOINT` (768) constants in `app_state.gd`. |
| Member list state restored on MEDIUM -> FULL | Low | Done | Saves `member_list_visible` before MEDIUM forces it off; restores on FULL. |
| Sidebar toggle uses distinct icon | Low | Done | `SidebarToggle` uses `sidebar_toggle.svg` (layout sidebar icon); `HamburgerButton` keeps `menu.svg`. |
