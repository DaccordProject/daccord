# Responsive Layout

Priority: 9
Depends on: Space & Channel Navigation, Messaging
Status: Complete

## Overview

Three layout modes (COMPACT <500px, MEDIUM 500-767px, FULL >=768px) with sidebar drawer overlay, panel toggles, resize handles, edge-swipe gestures, and reduced-motion support. Layout mode is determined by viewport width in logical pixels. On high-DPI desktop screens, `_auto_ui_scale()` adjusts `content_scale_factor` based on `DisplayServer.screen_get_scale()`. On mobile platforms, it uses `DisplayServer.screen_get_dpi()` with Android's 160 DPI baseline to calculate the appropriate scale (up to 3.0x). The `allow_hidpi` project setting is enabled, so `content_scale_factor` is set automatically, dividing the native resolution down to a logical viewport that triggers the correct breakpoint. Additionally, wide-but-short viewports (height < 500px) are demoted from FULL to MEDIUM to handle landscape tablets and very short windows.

## User Steps

### Desktop (FULL mode, >=768px)

1. User sees sidebar inline with guild bar + channel panel on the left.
2. Content area shows tab bar, topic bar, message view, and optionally member list / search / thread panels.
3. User clicks sidebar toggle to show/hide channel panel.
4. User clicks member list toggle to show/hide member panel.
5. User clicks search toggle to show/hide search panel.
6. User drags resize handles between panels to adjust widths.
7. User double-clicks a resize handle to reset panel to default width.

### Desktop (MEDIUM mode, 500-767px)

8. Sidebar remains inline but member list is auto-hidden to save space.
9. Channel panel auto-hides after user selects a channel (sidebar.gd line 100).
10. Channel panel auto-shows when user selects a space (sidebar.gd line 83).
11. Member list toggle remains visible but member list starts hidden.

### Mobile / Narrow (COMPACT mode, <500px)

12. Sidebar moves to a drawer overlay, hamburger button appears in content header.
13. User taps hamburger button or swipes from left edge to open sidebar drawer.
14. User selects a channel; drawer auto-closes (sidebar.gd line 104).
15. User taps backdrop or swipes left to close drawer.
16. Member list and search panel are completely hidden (no toggles visible).
17. Thread panel replaces message view instead of appearing alongside it.
18. Collapsed message timestamps are always visible (no hover on touch).
19. Hover action bar is suppressed; all message actions via long-press context menu.

### Window Resize / Device Rotation

20. On viewport resize, `main_window._on_viewport_resized()` fires.
21. `AppState.update_layout_mode(viewport_width)` recalculates the mode.
22. If mode changed, `layout_mode_changed` signal fires, all listeners adapt.

## Signal Flow

```
Viewport resized (window drag / device rotation)
  -> main_window._on_viewport_resized() (line 327)
  -> get_viewport().get_visible_rect().size  (logical pixels, affected by content_scale_factor)
  -> AppState.update_layout_mode(width, height) (line 307)
     -> width < 500  -> COMPACT
     -> width < 768  -> MEDIUM
     -> width >= 768 && height < 500 -> MEDIUM (landscape/short viewport demotion)
     -> width >= 768 -> FULL
  -> if mode changed: layout_mode_changed signal emitted (line 317)
     -> main_window._on_layout_mode_changed(mode) (line 334)
        -> COMPACT: move sidebar to drawer, show hamburger, hide member/search toggles
        -> MEDIUM/FULL: move sidebar to layout, restore panels
     -> collapsed_message._on_layout_mode_changed(mode) (line 77)
        -> COMPACT: timestamps always visible
     -> message_view_hover.on_layout_mode_changed(mode)
        -> COMPACT: hide action bar
     -> thread_panel._apply_layout()
        -> COMPACT: back-arrow instead of X, min width 0
     -> forum_view._apply_layout()
        -> COMPACT: smaller title font, "+" instead of "New Post"
     -> video_grid._update_grid_columns()
        -> COMPACT: 1 column; MEDIUM/FULL: 2+ columns
     -> welcome_screen._apply_layout()
        -> COMPACT: VBox card layout instead of HBox

Hamburger button pressed (COMPACT mode)
  -> AppState.toggle_sidebar_drawer() (line 319)
  -> sidebar_drawer_toggled signal (line 321)
  -> MainWindowDrawer.open_drawer() (line 68)
     -> sidebar slides in (tween 0.2s ease-out)
     -> backdrop fades in

Edge-swipe from left (COMPACT mode, touch or mouse)
  -> main_window._input(event) (line 239)
  -> DrawerGestures.handle_input(event) (line 28)
  -> Track touch/drag within 20px edge zone (EDGE_SWIPE_ZONE)
  -> On release: velocity-based snap decision (line 279)
     -> |velocity| > 400px/s: snap in velocity direction
     -> else: snap open if progress >= 50%
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | `LayoutMode` enum (line 211), `COMPACT_BREAKPOINT`/`MEDIUM_BREAKPOINT` constants (lines 213-214), layout state vars, `update_layout_mode()` (line 307), `toggle_sidebar_drawer()`, `close_sidebar_drawer()`, `toggle_channel_panel()`, `toggle_member_list()`, `toggle_search()`, `close_search()` |
| `scenes/main/main_window.gd` | Layout orchestration, `_on_layout_mode_changed()` (line 334), panel toggle wiring, resize handle creation (lines 154-178), `_sync_handle_visibility()` (line 397), `_clamp_panel_widths()` (line 411), `_apply_ui_scale()` (line 202), `_auto_ui_scale()` (line 225), voice view exception handling (lines 336-360) |
| `scenes/main/main_window_drawer.gd` | `MainWindowDrawer` class: sidebar reparenting (`move_sidebar_to_layout`/`move_sidebar_to_drawer`), drawer open/close animations, `get_drawer_width()` (line 46), reduced-motion support |
| `scenes/main/drawer_gestures.gd` | `DrawerGestures` class: edge-swipe open (lines 37-89), swipe-to-close (lines 174-225), interactive drag tracking with velocity-based snap (`_should_snap_open`, line 279) |
| `scenes/main/panel_resize_handle.gd` | `PanelResizeHandle` class: draggable resize handles for side panels, double-click-to-reset, visibility tracks target panel |
| `scenes/main/main_window.tscn` | Scene structure: LayoutHBox, ContentHeader (HamburgerButton, SidebarToggle, TabBar, SearchToggle, MemberListToggle), TopicBar, ContentBody (MessageView, ThreadPanel, MemberList, SearchPanel, VoiceTextPanel), DrawerBackdrop, DrawerContainer |
| `scenes/sidebar/sidebar.gd` | MEDIUM mode channel panel auto-show/hide on space/channel selection, `set_channel_panel_visible()` (animated), `set_channel_panel_visible_immediate()` |
| `scenes/messages/collapsed_message.gd` | Responsive timestamp: always visible in COMPACT (line 81), hover-only in MEDIUM/FULL |
| `scenes/messages/thread_panel.gd` | `_apply_layout()`: COMPACT uses back-arrow button + min width 0; non-COMPACT uses X button + min width 340 |
| `scenes/messages/message_view_hover.gd` | `on_layout_mode_changed()`: hides action bar in COMPACT; `on_msg_hovered()` (line 33): suppresses hover in COMPACT |
| `scenes/messages/forum_view.gd` | `_apply_layout()`: COMPACT shrinks title font and collapses "New Post" to "+" icon |
| `scenes/video/video_grid.gd` | `_update_grid_columns()`: inline mode uses 1 col (COMPACT) or 2 cols (MEDIUM/FULL); full-area mode uses adaptive columns |
| `scenes/main/welcome_screen.gd` | `_apply_layout()`: COMPACT switches feature cards from HBox to VBox layout |
| `project.godot` | `allow_hidpi=true` (line 53), `content_scale/mode="canvas_items"` (line 54), viewport 1280x720 (lines 48-49), min size 320x480 (lines 51-52), handheld orientation auto-rotate (line 50) |

## Implementation Details

### Breakpoint Detection

`AppState.update_layout_mode()` (app_state.gd line 307) receives the viewport width in logical pixels and sets the layout mode:

```
COMPACT:  viewport_width < 500px  (COMPACT_BREAKPOINT, line 213)
MEDIUM:   viewport_width < 768px  (MEDIUM_BREAKPOINT, line 214)
FULL:     viewport_width >= 768px
```

The viewport width comes from `get_viewport().get_visible_rect().size.x` (main_window.gd line 328). With `content_scale/mode="canvas_items"` (project.godot line 54), this returns the logical viewport size, which equals the physical window size divided by `content_scale_factor`.

When the viewport is wide enough for FULL mode (≥768px), a height check is applied (lines 314-319): if `viewport_height` is below `COMPACT_BREAKPOINT` (500px), the mode is demoted to MEDIUM. This handles landscape tablets and very short desktop windows where the full layout (with member list, search panel, etc.) would not fit vertically.

### UI Scale and DPI

`_apply_ui_scale()` (main_window.gd line 202) reads the user's configured scale or falls back to `_auto_ui_scale()` (line 225). The auto-scale:

1. Checks `display/window/dpi/allow_hidpi` project setting (line 226) -- if false, returns 1.0
2. **Mobile path** (line 236): uses `DisplayServer.screen_get_dpi()` with 160 DPI baseline (Android mdpi standard), clamps to 1.0-3.0x
3. **Desktop path** (line 241): reads `DisplayServer.screen_get_scale()`, clamps to 1.0-3.0x
4. Sets `window.content_scale_factor` (line 207)
5. On desktop (not web or mobile), resizes and re-centres the window to compensate (lines 211-223)

**Example mobile calculation:**
- A 1080px-wide phone at 480 DPI → scale = 480/160 = 3.0
- `content_scale_factor` = 3.0
- Effective viewport = 1080 / 3.0 = 360px → **COMPACT mode**
- UI elements rendered at 3x, appropriate size for touch

**Example desktop calculation:**
- A 2560px-wide monitor with `screen_get_scale()` = 2.0
- `content_scale_factor` = 2.0
- Window resized to 2560x1440 to compensate
- Effective viewport = 1280px → **FULL mode**

### COMPACT Mode Behavior

When entering COMPACT mode (main_window.gd lines 379-395):

- Sidebar reparented from `LayoutHBox` to `DrawerContainer` (`_drawer.move_sidebar_to_drawer()`)
- Channel panel always visible within the drawer (`sidebar.set_channel_panel_visible_immediate(true)`)
- Hamburger button shown, sidebar toggle hidden
- Member list toggle hidden, member list hidden
- Search toggle hidden, search panel hidden, search closed
- Thread panel replaces message view (mutually exclusive)
- Resize handles hidden in compact mode (`_sync_handle_visibility()`, line 397)

### MEDIUM Mode Behavior

When entering MEDIUM mode (main_window.gd lines 362-378):

- Sidebar inline in layout (same as FULL)
- Member list state saved (`_member_list_before_medium`, line 373) then hidden (line 374)
- Channel panel auto-hides after channel selection (sidebar.gd line 100)
- Channel panel auto-shows on space selection (sidebar.gd line 83)
- Search panel available via toggle

### FULL Mode Behavior

When entering FULL mode:

- Sidebar inline, member list state restored from `_member_list_before_medium` (line 371)
- All panels and toggles available
- Resize handles visible for thread, member, search, and voice text panels

### Drawer System

**MainWindowDrawer** (main_window_drawer.gd):
- Base width: 308px (`BASE_DRAWER_WIDTH`, line 6)
- Clamped to `min(308, viewport_width - 60)` to ensure 60px backdrop tap target (line 48)
- Open/close animations: 0.2s cubic ease (lines 82-88, 98-105)
- Reduced motion: instant position changes (lines 76-78, 94-95)

**DrawerGestures** (drawer_gestures.gd):
- Edge swipe zone: 20px from left edge (`EDGE_SWIPE_ZONE`, line 3)
- Dead zone: 10px before tracking begins (`SWIPE_DEAD_ZONE`, line 5)
- Swipe threshold: 80px for non-tracking opens (`SWIPE_THRESHOLD`, line 4)
- Velocity threshold: 400px/s for snap decision (`VELOCITY_THRESHOLD`, line 6)
- Snap progress: 50% for position-based snap (`SNAP_PROGRESS`, line 7)
- Handles both `InputEventScreenTouch`/`InputEventScreenDrag` (touch) and `InputEventMouseButton`/`InputEventMouseMotion` (desktop testing)
- Only active in COMPACT mode (main_window.gd lines 240-242)

### Panel Resize Handles

Created in `main_window._ready()` (lines 154-178) for thread, member, search, and voice text panels. Each `PanelResizeHandle` tracks its target panel's visibility and supports:
- Drag to resize panel width
- Double-click to reset to default width
- Hidden in COMPACT mode (`_sync_handle_visibility()`, line 397)
- Panel widths auto-clamped when total exceeds available space (`_clamp_panel_widths()`, line 411)

### Voice View Exception

When the voice view is open, layout mode changes skip content visibility management but still handle sidebar/drawer transitions (main_window.gd lines 336-360). Voice text panel is hidden in COMPACT mode during voice view.

### Per-Component Layout Adaptations

| Component | COMPACT Behavior |
|-----------|-----------------|
| `collapsed_message.gd` | Timestamps always visible (line 81) -- no hover on touch |
| `message_view_hover.gd` | Action bar suppressed (line 33) -- use long-press context menu |
| `thread_panel.gd` | Back-arrow button replaces X, min width 0 |
| `forum_view.gd` | Smaller title font, "+" icon replaces "New Post" button |
| `video_grid.gd` | 1-column layout in inline mode |
| `welcome_screen.gd` | Feature cards in VBox instead of HBox |
| `sidebar.gd` | Auto-closes drawer on channel selection (line 104) |

## Implementation Status

- [x] Three layout modes with correct breakpoint thresholds (app_state.gd lines 211-214)
- [x] Sidebar drawer with open/close animations (main_window_drawer.gd)
- [x] Edge-swipe open gesture with velocity-based snap (drawer_gestures.gd)
- [x] Swipe-to-close gesture on backdrop (drawer_gestures.gd lines 174-225)
- [x] Hamburger button in COMPACT mode (main_window.gd line 382)
- [x] Sidebar/member/search toggle buttons in MEDIUM/FULL (main_window.gd lines 367-368)
- [x] Channel panel auto-show/hide in MEDIUM mode (sidebar.gd lines 83, 100)
- [x] Member list state save/restore across MEDIUM transitions (main_window.gd lines 371-374)
- [x] Panel resize handles with drag and double-click-to-reset (lines 154-178)
- [x] Panel width clamping when panels overflow (lines 411-458)
- [x] Thread panel replaces message view in COMPACT (lines 392-395, 483-490)
- [x] Compact timestamp visibility (collapsed_message.gd line 81)
- [x] Hover action bar suppressed in COMPACT (message_view_hover.gd line 33)
- [x] Forum view compact adaptations (forum_view.gd)
- [x] Video grid column adaptations (video_grid.gd)
- [x] Welcome screen layout adaptations (welcome_screen.gd)
- [x] Drawer width capped to leave 60px backdrop tap target (main_window_drawer.gd line 48)
- [x] Reduced motion support in drawer animations (main_window_drawer.gd lines 76, 94; drawer_gestures.gd lines 138, 155, 262)
- [x] Voice view exception handling during layout transitions (main_window.gd lines 336-360)
- [x] Auto UI scale infrastructure (`_apply_ui_scale`, `_auto_ui_scale`)
- [x] `allow_hidpi` enabled in project.godot (line 53)
- [x] Mobile DPI-based auto-scaling via `OS.has_feature("mobile")` + `screen_get_dpi()` (main_window.gd lines 236-240)
- [x] Window resize skipped on mobile platforms (main_window.gd line 209)
- [x] Scale cap raised to 3.0 for both mobile and desktop (main_window.gd lines 240, 244)
- [x] Height/aspect ratio awareness -- wide-but-short viewports demote to MEDIUM (app_state.gd lines 314-319)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Android DPI reporting untested on real devices | Medium | `DisplayServer.screen_get_dpi()` is used to calculate mobile scale (main_window.gd line 237). The 160 DPI baseline assumes Android-standard density buckets. Needs verification on a range of real Android devices to confirm `screen_get_dpi()` returns expected values. |
| Tablet vs phone distinction not yet implemented | Low | A large tablet (e.g. 10" at 1600x2560) with ~320 DPI gets scale 2.0, yielding ~800px logical viewport → FULL mode. This is correct for tablets but the system has no way to force COMPACT on smaller tablets where MEDIUM might be more appropriate. Physical screen diagonal calculation could help. |
