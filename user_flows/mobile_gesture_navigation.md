# Mobile Gesture Navigation

## Overview

Daccord supports touch-based gesture navigation in COMPACT layout mode (viewport < 500px). Users can swipe from the left edge to reveal the sidebar drawer, from the right edge to reveal the member list drawer, swipe drawers closed, use swipe-down-to-dismiss on the image lightbox, swipe right from the left edge to close a thread panel, and use the Android back button to dismiss overlays. This flow covers the edge-swipe drawer system, velocity-based snap decisions, close gestures, long-press detection, DPI-scaled edge zones, and the back button / navigation history stack.

## User Steps

1. On a mobile device or narrow viewport (< 500px), the app enters COMPACT layout mode
2. The sidebar moves into a left-side drawer overlay, hidden off-screen to the left
3. The member list moves into a right-side drawer overlay, hidden off-screen to the right
4. User swipes right from the left edge (within DPI-scaled zone) to reveal the sidebar drawer
5. The sidebar follows the finger in real-time with a darkening backdrop
6. Releasing the finger snaps the drawer open or closed based on progress/velocity
7. With the drawer open, user taps the backdrop area (right of drawer) to close it
8. Alternatively, user swipes left on the backdrop to drag the drawer closed
9. User taps a channel in the sidebar; the drawer closes and the channel loads
10. User swipes left from the right edge to reveal the member list drawer
11. The member list follows the finger in real-time with a darkening backdrop
12. Releasing the finger snaps the member drawer open or closed based on progress/velocity
13. With the member drawer open, user taps the backdrop or swipes right to close it
14. When viewing a thread in COMPACT mode, user swipes right from the left edge to close the thread and return to messages
15. In the image lightbox, user swipes down (or up) to dismiss the lightbox with an animated slide-out
16. On Android, pressing the hardware/software back button dismisses the current overlay (dialog, drawer, member drawer, thread, lightbox)

## Signal Flow

```
User touches left edge (< DPI-scaled zone)
  │
  ▼
DrawerGestures._handle_open_swipe()
  │
  ├─ Drag detected (> 10px dead zone)
  │    │
  │    ▼
  │  _begin_drawer_tracking()          ← kills existing tween, shows drawer nodes
  │    │
  │    ▼
  │  _update_drawer_position()         ← sidebar.position.x + backdrop.modulate.a
  │    │                                  tracks velocity via dt calculation
  │    ▼
  │  [finger released]
  │    │
  │    ▼
  │  _finish_open_swipe()
  │    │
  │    ├─ _should_snap_open() == true  → _snap_drawer_open()
  │    │    │                               sets AppState.sidebar_drawer_open = true
  │    │    │                               tweens to position 0.0, alpha 1.0
  │    │    ▼
  │    │  Drawer fully open
  │    │
  │    └─ _should_snap_open() == false → _snap_drawer_closed()
  │         │                               tweens to -dw, alpha 0.0
  │         ▼                               chains _hide_drawer_nodes()
  │       Drawer closed
  │
  └─ Quick swipe (> 80px, no drag activation)
       │
       ▼
     AppState.toggle_sidebar_drawer()
       │
       ▼
     AppState.sidebar_drawer_toggled signal
       │
       ▼
     MainWindowDrawer.on_sidebar_drawer_toggled()
       │
       ▼
     open_drawer() / close_drawer()    ← full 0.2s tween animation


User touches right edge (< DPI-scaled zone from right)
  │
  ▼
DrawerGestures._handle_right_edge_swipe()
  │
  ├─ Drag detected (leftward > 10px dead zone)
  │    │
  │    ▼
  │  _begin_member_drawer_tracking()   ← kills existing tween, shows member drawer nodes
  │    │
  │    ▼
  │  _update_member_drawer_position()  ← member_list.position.x + backdrop.modulate.a
  │    │
  │    ▼
  │  [finger released]
  │    │
  │    ▼
  │  _finish_member_open_swipe()
  │    │
  │    ├─ snap open  → _snap_member_open()
  │    │    │             sets AppState.member_drawer_open = true
  │    │    │             tweens to vp_width - dw, alpha 1.0
  │    │    ▼
  │    │  Member drawer fully open
  │    │
  │    └─ snap close → _snap_member_closed()
  │
  └─ Quick swipe (> 80px leftward, no drag)
       │
       ▼
     AppState.toggle_member_drawer()


User touches backdrop (x < drawer_left) while member drawer is open
  │
  ▼
DrawerGestures._handle_member_close_swipe()
  │
  ├─ Drag detected (rightward > 10px dead zone)
  │    │
  │    ▼
  │  _update_member_close_position()
  │    │
  │    ▼
  │  [finger released]
  │    │
  │    ▼
  │  _finish_member_close_swipe()
  │    │
  │    ├─ snap open  → _snap_member_open()
  │    └─ snap close → _snap_member_closed_from_close()
  │
  └─ Simple tap (no drag)
       │
       ▼
     _on_member_backdrop_input()
       │
       ▼
     AppState.close_member_drawer()


User touches backdrop (x > drawer width) while sidebar drawer is open
  │
  ▼
DrawerGestures._handle_close_swipe()
  │
  ├─ Drag detected (leftward > 10px dead zone)
  │    │
  │    ▼
  │  _update_close_drawer_position()   ← sidebar.position.x = -dw * close_progress
  │    │                                  backdrop.modulate.a = 1.0 - close_progress
  │    ▼
  │  [finger released]
  │    │
  │    ▼
  │  _finish_close_swipe()
  │    │
  │    ├─ snap open  → _snap_drawer_open()
  │    └─ snap close → _snap_drawer_closed_from_close()
  │
  └─ Simple tap (no drag)
       │
       ▼
     _on_backdrop_input()              ← main_window.gd (line 633)
       │
       ▼
     AppState.close_sidebar_drawer()


Thread panel visible in COMPACT + user touches left edge
  │
  ▼
DrawerGestures._handle_thread_swipe_back()
  │
  ├─ Swipe right > 80px or drag active → AppState.close_thread()
  └─ Below threshold → falls through to sidebar open swipe


Image lightbox open + user swipes vertically
  │
  ▼
image_lightbox._on_backdrop_input()
  │
  ├─ Drag > 10px vertically activates swipe mode
  │    │
  │    ▼
  │  Image follows finger, backdrop fades proportionally
  │    │
  │    ▼
  │  [finger released]
  │    │
  │    ├─ displacement >= 100px → _animate_dismiss()
  │    │    │                        tweens image off-screen + fade out
  │    │    ▼
  │    │  _close() → queue_free()
  │    │
  │    └─ displacement < 100px → _snap_back()
  │                                 tweens image back to center
  │
  └─ Simple tap (no drag) → _close()
```

## Key Files

| File | Role |
|------|------|
| `scenes/main/drawer_gestures.gd` | Core swipe gesture detection: left-edge sidebar open, right-edge member drawer open, close swipes for both drawers, thread swipe-back, velocity tracking, snap decisions, DPI-scaled edge zone |
| `scenes/main/main_window_drawer.gd` | Drawer state machine: sidebar ↔ drawer reparenting, member list ↔ drawer reparenting, tween animations, hide/show nodes for both drawers |
| `scenes/main/main_window.gd` | Input routing (`_input`, line 284), layout mode transitions (line 412), backdrop tap handlers (lines 633, 641), back navigation (line 296), member drawer wiring |
| `scenes/main/main_window.tscn` | Scene nodes: `DrawerBackdrop`, `DrawerContainer` (left sidebar), `MemberDrawerBackdrop`, `MemberDrawerContainer` (right member list) |
| `scripts/autoload/app_state.gd` | Layout mode enum/breakpoints (line 218), drawer state (`sidebar_drawer_open` line 229, `member_drawer_open` line 230), toggle/close methods (lines 339-368) |
| `scripts/autoload/config.gd` | `get_reduced_motion()` — skips tween animations when enabled |
| `scripts/helpers/long_press_detector.gd` | Touch-specific long-press detection with drag cancellation (500ms threshold) |
| `scripts/helpers/navigation_history.gd` | Stack-based navigation history for back button unwinding (max 32 entries) |
| `scenes/messages/image_lightbox.gd` | Image lightbox overlay — swipe-to-dismiss, pushes/pops nav history, handles `ui_cancel` directly |

## Implementation Details

### Edge-Swipe Open Gesture (Left — Sidebar)

`DrawerGestures` (extends `RefCounted`) handles all touch/mouse input when `AppState.current_layout_mode == COMPACT` (gated at `main_window.gd` line 285).

**Constants** (lines 3-7):
- `EDGE_SWIPE_ZONE = 20.0` — base left/right-edge detection zone in logical pixels
- `SWIPE_THRESHOLD = 80.0` — minimum displacement for a quick toggle (no drag)
- `SWIPE_DEAD_ZONE = 10.0` — displacement before drag mode activates
- `VELOCITY_THRESHOLD = 400.0` — px/s threshold for momentum-based snap
- `SNAP_PROGRESS = 0.5` — 50% progress threshold for position-based snap

**DPI-Scaled Edge Zone** (`_get_edge_zone`, line 42):
- On mobile devices, scales `EDGE_SWIPE_ZONE` by `DPI / 160 / content_scale_factor`
- Clamped to `[1.0, 2.0]` multiplier range
- Result cached for performance
- On desktop, returns the base 20px value unchanged

**Open flow** (`_handle_open_swipe`, line 82):
- `InputEventScreenTouch.pressed` at `x <= edge_zone` starts tracking (line 89)
- `InputEventScreenDrag` activates drag after 10px dead zone (line 101), calls `_begin_drawer_tracking()` (line 131) which kills any existing tween, shows drawer/backdrop nodes, positions sidebar at `-dw`
- `_update_drawer_position()` (line 143) maps finger X to progress `[0,1]`, sets `sidebar.position.x = -dw + (dw * progress)` and `backdrop.modulate.a = progress`
- Velocity tracked via `dt = now - _swipe_last_time` (lines 151-156)
- Mouse events mirror touch events for desktop testing (lines 108-125)

### Snap Decision

`_should_snap_open(progress, velocity)` (line 696):
- If `|velocity| > 400 px/s`: snap in direction of velocity (momentum)
- Otherwise: snap open if `progress >= 0.5` (position-based)

### Drawer Animation

`_snap_drawer_open(progress)` (line 168):
- Sets `AppState.sidebar_drawer_open = true`
- Duration scales: `max(0.2 * (1.0 - progress), 0.05)` — shorter when already close to open
- Tweens `position:x → 0.0` with `EASE_OUT` + `TRANS_CUBIC`
- Tweens `backdrop.modulate:a → 1.0` in parallel
- Reduced motion: sets final values immediately, no tween (line 171)

`_snap_drawer_closed(progress)` (line 186):
- Duration: `max(0.2 * progress, 0.05)`
- Tweens `position:x → -dw` with `EASE_IN` + `TRANS_CUBIC`
- Chains `_hide_drawer_nodes()` callback after tween completes (line 201)

### Close Gesture (Sidebar)

`_handle_close_swipe()` (line 207):
- Touch on backdrop (`x > dw`) starts close tracking (line 213)
- Leftward drag beyond dead zone activates close swipe (line 229)
- `_update_close_drawer_position()` (line 268) maps leftward displacement to `close_progress [0,1]`, sets `sidebar.position.x = -dw * close_progress` and `backdrop.alpha = 1.0 - close_progress`
- On release, `_finish_close_swipe()` (line 284) decides snap direction
- Simple tap (no drag) falls through to `_on_backdrop_input()` (main_window.gd line 633) which calls `AppState.close_sidebar_drawer()`

### Right-Edge Member List Drawer

`_handle_right_edge_swipe()` (line 315):
- Touch at `x >= vp_width - edge_zone` starts right-edge tracking
- Leftward drag beyond dead zone activates member drawer opening
- `_begin_member_drawer_tracking()` (line 378) shows member drawer backdrop/container, positions member list at `vp_width` (off-screen right)
- `_update_member_drawer_position()` (line 393) maps leftward displacement to progress, sets `member_list.position.x = vp_width - (dw * progress)` and `backdrop.modulate.a = progress`
- Velocity is inverted for snap decisions since leftward motion opens (line 415)
- Quick leftward swipe (> 80px) triggers `AppState.toggle_member_drawer()`

**Member drawer close** (`_handle_member_close_swipe`, line 463):
- Touch on backdrop (`x < drawer_left`) starts close tracking
- Rightward drag closes the member drawer
- Simple tap on backdrop calls `AppState.close_member_drawer()`

### Member Drawer State Management

`MainWindowDrawer` manages the member list between content_body and member_drawer_container:
- `move_member_to_drawer()` (line 130): reparents member list from `content_body` to `member_drawer_container`, sets `PRESET_RIGHT_WIDE` anchors, `offset_left = -dw`
- `move_member_to_layout()` (line 142): reparents back to `content_body`
- `get_member_drawer_width()` (line 126): `min(308px, viewport_width - 60px)` ensures 60px backdrop tap target
- `open_member_drawer()` (line 152): animates member list from `vp_width` to `vp_width - dw` with 0.2s tween
- `close_member_drawer()` (line 173): animates member list off-screen to `vp_width`
- `hide_member_drawer_nodes()` (line 195): hides backdrop + container, resets `AppState.member_drawer_open`

### Drawer State Management (Sidebar)

`MainWindowDrawer` (extends `RefCounted`) manages the sidebar between layout and drawer container:
- `move_sidebar_to_drawer()` (line 51): reparents sidebar from `layout_hbox` to `drawer_container`, sets `PRESET_LEFT_WIDE` anchors, `offset_right = drawer_width`
- `move_sidebar_to_layout()` (line 37): reparents back to `layout_hbox` at index 0
- `get_drawer_width()` (line 46): `min(308px, viewport_width - 60px)` ensures 60px backdrop tap target
- `on_sidebar_drawer_toggled()` (line 61): routes open/close from AppState signal
- `hide_drawer_nodes()` (line 114): hides backdrop + container, resets `AppState.sidebar_drawer_open`

### Layout Mode Transitions

`main_window.gd` `_on_layout_mode_changed()` (line 412):
- **COMPACT**: moves sidebar to left drawer, member list to right drawer, shows hamburger button, hides member list/search/member toggle, thread panel replaces message view (line 470)
- **MEDIUM**: restores sidebar and member list to layout, saves member list state then hides it (line 451)
- **FULL**: restores sidebar and member list to layout, restores member list from saved state (line 449)
- Voice view open: special-cases sidebar/member transitions without content visibility changes (line 414)

### Thread Panel Swipe-Back

`_handle_thread_swipe_back()` (line 616) provides a swipe-right gesture to close the thread panel in COMPACT mode:
- Only active when `AppState.thread_panel_visible` is true and no drawer is open
- Left-edge touch (within DPI-scaled zone) starts tracking
- Rightward drag beyond dead zone activates the swipe
- On release: if drag was active or displacement >= 80px, calls `AppState.close_thread()`
- Takes priority over the sidebar open swipe to avoid conflicts

### Image Lightbox Swipe-to-Dismiss

`image_lightbox.gd` supports vertical swipe-to-dismiss (line 37):
- `InputEventScreenTouch.pressed` starts tracking the vertical swipe
- `InputEventScreenDrag` activates after 10px vertical dead zone
- Image container follows the finger vertically; backdrop fades proportionally (40% viewport height = full fade)
- On release: if displacement >= 100px, `_animate_dismiss()` tweens the image off-screen (0.15s) and calls `_close()`
- If below threshold, `_snap_back()` tweens back to center position
- Simple tap (no drag) closes immediately
- Reduced motion: skips animation, closes instantly

### Long-Press Detection

`LongPressDetector` (line 1-43) provides touch-specific context menu triggering:
- 500ms hold duration (line 4)
- Cancels if finger moves > 10px (line 32)
- Fires callback with screen position as `Vector2i`

### Hamburger Button

`hamburger_button` (visible only in COMPACT mode) calls `AppState.toggle_sidebar_drawer()` on press (main_window.gd line 631). Connected at line 79.

### Reduced Motion Support

All drawer animations check `Config.get_reduced_motion()`. When enabled:
- Open: sets final position/alpha immediately, no tween
- Close: calls `hide_drawer_nodes()` / `hide_member_drawer_nodes()` immediately, no tween
- Gesture snaps: same skip behavior in all snap methods
- Lightbox dismiss: skips slide-out animation, closes instantly

### Navigation History Stack

`NavigationHistory` (`scripts/helpers/navigation_history.gd`) tracks a stack of `StringName` entries representing dismissable layers. Capped at 32 entries. Consecutive duplicate entries are deduplicated on push.

**Tracked entries:**
- `&"drawer"` — sidebar drawer open (pushed by `toggle_sidebar_drawer()`, `_snap_drawer_open()`)
- `&"member_drawer"` — member list drawer open (pushed by `toggle_member_drawer()`, `_snap_member_open()`)
- `&"thread"` — thread panel open (pushed by `open_thread()`)
- `&"voice_view"` — voice view open (pushed by `open_voice_view()`)
- `&"discovery"` — discovery panel open (pushed by `open_discovery()`)
- `&"lightbox"` — image lightbox open (pushed in `image_lightbox.gd` `_ready()`)

Each entry is removed when its corresponding close method fires (e.g., `close_sidebar_drawer()` removes `&"drawer"`).

### Android Back Button / Global Back Handler

`main_window.gd` `_unhandled_input()` (line 289) catches `ui_cancel` (Android back button / Escape) after dialogs have had their chance to handle it via `_input()`:

1. Pops the most recent `NavigationHistory` entry
2. Matches the entry and calls the corresponding close method:
   - `&"drawer"` → `AppState.close_sidebar_drawer()`
   - `&"thread"` → `AppState.close_thread()`
   - `&"voice_view"` → `AppState.close_voice_view()`
   - `&"discovery"` → `AppState.close_discovery()`
   - `&"member_drawer"` → `AppState.close_member_drawer()`
3. If the stack is empty and in COMPACT mode, opens the sidebar drawer as a fallback

The image lightbox handles `ui_cancel` in its own `_input()` handler (line 67), which runs before `_unhandled_input`, so it closes itself and removes its nav history entry.

Individual dialogs (25+ files) continue to handle `ui_cancel` independently in their own `_input()` handlers. These do not participate in the nav history stack since they self-manage.

## Implementation Status

- [x] Left-edge swipe to open sidebar drawer (DPI-scaled zone)
- [x] Finger-following drawer position during drag
- [x] Velocity-based momentum snapping (400 px/s threshold)
- [x] Position-based snap at 50% progress
- [x] Backdrop tap to close drawer
- [x] Leftward swipe on backdrop to close drawer
- [x] Tween animations with EASE_OUT/EASE_IN cubic curves
- [x] Duration scales with gesture progress
- [x] Reduced motion accessibility support
- [x] Mouse event mirroring for desktop testing
- [x] Dead zone (10px) before activating drag mode
- [x] Hamburger button fallback for non-gesture open
- [x] Drawer width capped to preserve 60px backdrop tap target
- [x] Long-press detection helper (500ms, 10px cancel threshold)
- [x] Layout mode breakpoints (COMPACT < 500px, MEDIUM < 768px, FULL >= 768px)
- [x] Sidebar reparenting between layout and drawer container
- [x] Thread panel replaces message view in COMPACT mode
- [x] Android back button global handler (`_unhandled_input` + `ui_cancel`)
- [x] Navigation history stack (`NavigationHistory` class, 32-entry cap)
- [x] Lightbox handles back button via `ui_cancel` in `_input()`
- [x] Right-edge swipe to reveal member list drawer
- [x] Member list reparenting between content_body and right-side drawer container
- [x] Member drawer backdrop tap and swipe-right to close
- [x] DPI-scaled edge swipe zone for high-DPI mobile devices
- [x] Swipe-to-dismiss for image lightbox (vertical swipe, 100px threshold)
- [x] Thread panel swipe-back gesture (left-edge swipe-right closes thread in COMPACT mode)
- [ ] Horizontal page-swipe navigation between sidebar / content / member panels (ViewPager-style)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No horizontal page-swipe navigation | Low | Mobile chat apps commonly allow full-width swiping between sidebar, content, and member panels (ViewPager pattern). Currently the three panels are accessed via separate edge swipes (left for sidebar, right for member list) and taps, which covers the same functionality but doesn't feel as native as a continuous horizontal pager. A full ViewPager would require significant layout refactoring. |
| Drawer closes channel panel auto-open only | Low | When entering COMPACT mode, `sidebar.set_channel_panel_visible_immediate(true)` forces the channel panel open (line 459). There is no memory of which space/channel the user was browsing if they close and reopen the drawer. |
