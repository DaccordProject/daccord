# Responsive Layout

## Overview

daccord adapts its layout to three viewport width breakpoints: COMPACT (<500px), MEDIUM (500-767px), and FULL (>=768px). In FULL mode, the sidebar is always visible alongside the content. In MEDIUM mode, the sidebar shows only the guild bar by default and reveals the channel panel on guild selection. In COMPACT mode, the entire sidebar moves to a drawer overlay that slides in from the left with a 0.2s animation, toggled by a hamburger button.

## User Steps

1. Application window resizes -> viewport width recalculated
2. `AppState.update_layout_mode(viewport_width)` determines new mode
3. If mode changed, `layout_mode_changed` signal emitted
4. Components adapt: sidebar position, channel panel visibility, hamburger button

COMPACT mode interactions:
1. User taps hamburger button (44x44px) in content header
2. Drawer slides in from left (sidebar + backdrop fade)
3. User selects guild -> channel list appears inside drawer
4. User selects channel -> drawer auto-closes, messages load

## Signal Flow

```
Window resize
    -> get_viewport().size_changed signal
    -> main_window._on_viewport_resized()
        -> viewport_width = get_viewport().get_visible_rect().size.x
        -> AppState.update_layout_mode(viewport_width)
            -> Determines COMPACT/MEDIUM/FULL based on breakpoints
            -> If changed: current_layout_mode = new_mode
            -> layout_mode_changed.emit(new_mode)
    -> main_window._on_layout_mode_changed(mode)
        -> match mode:
            FULL: sidebar in layout, channel panel visible, hamburger hidden
            MEDIUM: sidebar in layout, channel panel hidden, hamburger hidden
            COMPACT: sidebar in drawer, channel panel visible, hamburger visible

Hamburger button (COMPACT only):
    -> main_window._on_hamburger_pressed()
        -> AppState.toggle_sidebar_drawer()
            -> sidebar_drawer_open toggled
            -> sidebar_drawer_toggled.emit(is_open)
    -> main_window._on_sidebar_drawer_toggled(is_open)
        -> _open_drawer() or _close_drawer()

Drawer close triggers:
    - Clicking/touching DrawerBackdrop
    - Selecting a channel (sidebar._on_channel_selected -> AppState.close_sidebar_drawer)
    - Selecting a DM (sidebar._on_dm_selected_channel -> AppState.close_sidebar_drawer)
    - Layout mode changing away from COMPACT
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | `LayoutMode` enum (line 21), `update_layout_mode()` (lines 68-78), `toggle_sidebar_drawer()` (lines 80-82), `close_sidebar_drawer()` (lines 84-87), `layout_mode_changed` signal, `sidebar_drawer_toggled` signal |
| `scenes/main/main_window.gd` | Layout orchestration, sidebar reparenting, drawer animations |
| `scenes/main/main_window.tscn` | Scene structure: LayoutHBox, DrawerBackdrop, DrawerContainer, HamburgerButton |
| `scenes/sidebar/sidebar.gd` | MEDIUM mode channel panel toggle on guild/channel selection |
| `scenes/messages/collapsed_message.gd` | Responsive timestamp: always visible in COMPACT, hover-only in MEDIUM/FULL |

## Implementation Details

Breakpoints (app_state.gd:68-78):
- `< 500px` -> COMPACT
- `500-767px` -> MEDIUM
- `>= 768px` -> FULL
- Only emits signal when mode actually changes (avoids redundant updates)

Layout Mode Handling (main_window.gd:104-122):
- FULL: `_move_sidebar_to_layout()`, channel_panel visible, hamburger hidden, drawer closed
- MEDIUM: `_move_sidebar_to_layout()`, channel_panel hidden, hamburger hidden, drawer closed
- COMPACT: `_move_sidebar_to_drawer()`, channel_panel visible, hamburger visible, drawer closed

Sidebar Reparenting:
- `_move_sidebar_to_layout()` (lines 124-130): Removes sidebar from DrawerContainer, adds to LayoutHBox at index 0
- `_move_sidebar_to_drawer()` (lines 132-140): Removes sidebar from LayoutHBox, adds to DrawerContainer, sets anchors PRESET_LEFT_WIDE, offset_right = DRAWER_WIDTH (308px)
- `_sidebar_in_drawer: bool` flag prevents redundant reparenting

Drawer Animation (main_window.gd):
- DRAWER_WIDTH constant: 308 pixels
- `_open_drawer()` (lines 157-170):
  - Shows DrawerBackdrop and DrawerContainer
  - Tween: sidebar.position.x from -308 to 0 (0.2s, EASE_OUT, TRANS_CUBIC)
  - Tween: DrawerBackdrop.modulate.a from 0 to 1 (0.2s, parallel)
- `_close_drawer()` (lines 172-180):
  - Tween: sidebar.position.x from 0 to -308 (0.2s, EASE_IN, TRANS_CUBIC)
  - Tween: DrawerBackdrop.modulate.a from 1 to 0 (0.2s, parallel)
  - Chains `_hide_drawer_nodes()` callback after animation
- `_close_drawer_immediate()` (lines 182-185): Kills tween, hides immediately (used on mode change)
- Previous tween killed before starting new animation

DrawerBackdrop (main_window.tscn):
- ColorRect covering full viewport
- Color: black with 0.5 alpha (semi-transparent overlay)
- Invisible by default
- Click/touch closes drawer via `_on_backdrop_input()`

HamburgerButton (main_window.tscn):
- 44x44px Button with menu.svg icon
- Flat style
- Tooltip: "Open sidebar"
- Invisible by default, shown only in COMPACT mode

MEDIUM Mode Channel Panel Toggle (sidebar.gd):
- `_on_guild_selected()` (line 26): Shows channel_panel in MEDIUM mode
- `_on_dm_selected()` (line 34): Shows channel_panel in MEDIUM mode
- `_on_channel_selected()` (line 40): Hides channel_panel in MEDIUM mode
- `_on_dm_selected_channel()` (line 48): Hides channel_panel in MEDIUM mode

Collapsed Message Responsive Timestamp (collapsed_message.gd):
- In COMPACT mode: timestamp always visible
- In MEDIUM/FULL modes: timestamp hidden by default, shown on mouse hover
- Listens to `AppState.layout_mode_changed` to update behavior
- Timestamp shows condensed time (e.g., "10:31") extracted from full timestamp string

## Implementation Status

- [x] Three layout modes (COMPACT/MEDIUM/FULL) with viewport breakpoints
- [x] Sidebar reparenting between layout and drawer
- [x] Drawer slide-in/slide-out animation (0.2s cubic easing)
- [x] DrawerBackdrop semi-transparent overlay
- [x] Hamburger button toggle (COMPACT only)
- [x] Backdrop click/touch to close drawer
- [x] Auto-close drawer on channel/DM selection
- [x] MEDIUM mode: channel panel show/hide on guild/channel selection
- [x] Responsive timestamps in collapsed messages
- [x] Touch support for backdrop dismiss

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No swipe-to-open drawer | Medium | Drawer only opens via hamburger button tap; no edge-swipe gesture detection |
| No landscape/orientation detection | Low | Layout purely based on width; no special handling for landscape vs portrait |
| No animation on MEDIUM channel panel toggle | Low | Channel panel appears/disappears instantly in MEDIUM mode (no slide transition) |
| DRAWER_WIDTH is fixed 308px | Low | Doesn't adapt to actual viewport width; on very narrow screens, 308px may be too wide |
| No breakpoint customization | Low | 500px and 768px breakpoints are hardcoded in `app_state.gd` |
