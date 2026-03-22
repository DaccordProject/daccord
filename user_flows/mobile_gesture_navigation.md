# Mobile Gesture Navigation

## Overview

Daccord supports touch-based gesture navigation in COMPACT layout mode (viewport < 500px). Users can swipe from the left edge to reveal the sidebar drawer, swipe it closed, and use the Android back button to dismiss overlays. This flow covers the edge-swipe drawer system, velocity-based snap decisions, close gestures, long-press detection, and the back button / navigation history gap.

## User Steps

1. On a mobile device or narrow viewport (< 500px), the app enters COMPACT layout mode
2. The sidebar moves into a drawer overlay, hidden off-screen to the left
3. User swipes right from the left edge (within 20px) to reveal the sidebar drawer
4. The sidebar follows the finger in real-time with a darkening backdrop
5. Releasing the finger snaps the drawer open or closed based on progress/velocity
6. With the drawer open, user taps the backdrop area (right of drawer) to close it
7. Alternatively, user swipes left on the backdrop to drag the drawer closed
8. User taps a channel in the sidebar; the drawer closes and the channel loads
9. On Android, pressing the hardware/software back button dismisses the current overlay (dialog, drawer, thread, lightbox) — **currently unimplemented as a global handler**

## Signal Flow

```
User touches left edge (< 20px)
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


User touches backdrop (x > drawer width) while drawer is open
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
     _on_backdrop_input()              ← main_window.gd (line 553)
       │
       ▼
     AppState.close_sidebar_drawer()
```

## Key Files

| File | Role |
|------|------|
| `scenes/main/drawer_gestures.gd` | Core swipe gesture detection: edge-swipe open, close-swipe, velocity tracking, snap decisions |
| `scenes/main/main_window_drawer.gd` | Drawer state machine: sidebar ↔ drawer reparenting, tween animations, hide/show nodes |
| `scenes/main/main_window.gd` | Input routing (`_input`, line 236), layout mode transitions (line 331), backdrop tap handler (line 553) |
| `scripts/autoload/app_state.gd` | Layout mode enum/breakpoints (line 217), drawer state (line 228), toggle/close methods (line 336) |
| `scripts/autoload/config.gd` | `get_reduced_motion()` (line 548) — skips tween animations when enabled |
| `scripts/helpers/long_press_detector.gd` | Touch-specific long-press detection with drag cancellation (500ms threshold) |
| `scripts/helpers/navigation_history.gd` | Stack-based navigation history for back button unwinding (max 32 entries) |
| `scenes/messages/image_lightbox.gd` | Image lightbox overlay — pushes/pops nav history, handles `ui_cancel` directly |

## Implementation Details

### Edge-Swipe Open Gesture

`DrawerGestures` (extends `RefCounted`) handles all touch/mouse input when `AppState.current_layout_mode == COMPACT` (gated at `main_window.gd` line 237).

**Constants** (lines 3-7):
- `EDGE_SWIPE_ZONE = 20.0` — left-edge detection zone in pixels
- `SWIPE_THRESHOLD = 80.0` — minimum displacement for a quick toggle (no drag)
- `SWIPE_DEAD_ZONE = 10.0` — displacement before drag mode activates
- `VELOCITY_THRESHOLD = 400.0` — px/s threshold for momentum-based snap
- `SNAP_PROGRESS = 0.5` — 50% progress threshold for position-based snap

**Open flow** (`_handle_open_swipe`, line 37):
- `InputEventScreenTouch.pressed` at `x <= 20px` starts tracking (line 40)
- `InputEventScreenDrag` activates drag after 10px dead zone (line 57), calls `_begin_drawer_tracking()` (line 97) which kills any existing tween, shows drawer/backdrop nodes, positions sidebar at `-dw`
- `_update_drawer_position()` (line 109) maps finger X to progress `[0,1]`, sets `sidebar.position.x = -dw + (dw * progress)` and `backdrop.modulate.a = progress`
- Velocity tracked via `dt = now - _swipe_last_time` (lines 117-122)
- Mouse events mirror touch events for desktop testing (lines 64-89)

### Snap Decision

`_should_snap_open(progress, velocity)` (line 279):
- If `|velocity| > 400 px/s`: snap in direction of velocity (momentum)
- Otherwise: snap open if `progress >= 0.5` (position-based)

### Drawer Animation

`_snap_drawer_open(progress)` (line 136):
- Sets `AppState.sidebar_drawer_open = true`
- Duration scales: `max(0.2 * (1.0 - progress), 0.05)` — shorter when already close to open
- Tweens `position:x → 0.0` with `EASE_OUT` + `TRANS_CUBIC`
- Tweens `backdrop.modulate:a → 1.0` in parallel
- Reduced motion: sets final values immediately, no tween (line 138)

`_snap_drawer_closed(progress)` (line 154):
- Duration: `max(0.2 * progress, 0.05)`
- Tweens `position:x → -dw` with `EASE_IN` + `TRANS_CUBIC`
- Chains `_hide_drawer_nodes()` callback after tween completes (line 169)

### Close Gesture

`_handle_close_swipe()` (line 174):
- Touch on backdrop (`x > dw`) starts close tracking (line 180)
- Leftward drag beyond dead zone activates close swipe (line 196)
- `_update_close_drawer_position()` (line 233) maps leftward displacement to `close_progress [0,1]`, sets `sidebar.position.x = -dw * close_progress` and `backdrop.alpha = 1.0 - close_progress`
- On release, `_finish_close_swipe()` (line 249) decides snap direction
- Simple tap (no drag) falls through to `_on_backdrop_input()` (main_window.gd line 553) which calls `AppState.close_sidebar_drawer()`

### Drawer State Management

`MainWindowDrawer` (extends `RefCounted`) manages the sidebar between layout and drawer container:
- `move_sidebar_to_drawer()` (line 51): reparents sidebar from `layout_hbox` to `drawer_container`, sets `PRESET_LEFT_WIDE` anchors, `offset_right = drawer_width`
- `move_sidebar_to_layout()` (line 37): reparents back to `layout_hbox` at index 0
- `get_drawer_width()` (line 46): `min(308px, viewport_width - 60px)` ensures 60px backdrop tap target
- `on_sidebar_drawer_toggled()` (line 61): routes open/close from AppState signal
- `hide_drawer_nodes()` (line 114): hides backdrop + container, resets `AppState.sidebar_drawer_open`

### Layout Mode Transitions

`main_window.gd` `_on_layout_mode_changed()` (line 331):
- **COMPACT**: moves sidebar to drawer, shows hamburger button, hides member list/search/member toggle, thread panel replaces message view (line 389)
- **MEDIUM**: restores sidebar to layout, saves member list state then hides it (line 370)
- **FULL**: restores sidebar to layout, restores member list from saved state (line 368)
- Voice view open: special-cases sidebar transition without content visibility changes (line 332)

### Long-Press Detection

`LongPressDetector` (line 1-43) provides touch-specific context menu triggering:
- 500ms hold duration (line 4)
- Cancels if finger moves > 10px (line 32)
- Fires callback with screen position as `Vector2i`

### Hamburger Button

`hamburger_button` (visible only in COMPACT mode) calls `AppState.toggle_sidebar_drawer()` on press (main_window.gd line 550-551). Connected at line 74.

### Reduced Motion Support

All drawer animations check `Config.get_reduced_motion()` (config.gd line 548). When enabled:
- Open: sets final position/alpha immediately, no tween
- Close: calls `hide_drawer_nodes()` immediately, no tween
- Gesture snaps: same skip behavior in `_snap_drawer_open` (line 139), `_snap_drawer_closed` (line 156), `_snap_drawer_closed_from_close` (line 263)

### Navigation History Stack

`NavigationHistory` (`scripts/helpers/navigation_history.gd`) tracks a stack of `StringName` entries representing dismissable layers. Capped at 32 entries. Consecutive duplicate entries are deduplicated on push.

**Tracked entries:**
- `&"drawer"` — sidebar drawer open (pushed by `toggle_sidebar_drawer()`, `_snap_drawer_open()`)
- `&"thread"` — thread panel open (pushed by `open_thread()`)
- `&"voice_view"` — voice view open (pushed by `open_voice_view()`)
- `&"discovery"` — discovery panel open (pushed by `open_discovery()`)
- `&"lightbox"` — image lightbox open (pushed in `image_lightbox.gd` `_ready()`)

Each entry is removed when its corresponding close method fires (e.g., `close_sidebar_drawer()` removes `&"drawer"`).

### Android Back Button / Global Back Handler

`main_window.gd` `_unhandled_input()` (line 241) catches `ui_cancel` (Android back button / Escape) after dialogs have had their chance to handle it via `_input()`:

1. Pops the most recent `NavigationHistory` entry
2. Matches the entry and calls the corresponding close method:
   - `&"drawer"` → `AppState.close_sidebar_drawer()`
   - `&"thread"` → `AppState.close_thread()`
   - `&"voice_view"` → `AppState.close_voice_view()`
   - `&"discovery"` → `AppState.close_discovery()`
3. If the stack is empty and in COMPACT mode, opens the sidebar drawer as a fallback

The image lightbox handles `ui_cancel` in its own `_input()` handler (line 28), which runs before `_unhandled_input`, so it closes itself and removes its nav history entry.

Individual dialogs (25+ files) continue to handle `ui_cancel` independently in their own `_input()` handlers. These do not participate in the nav history stack since they self-manage.

## Implementation Status

- [x] Left-edge swipe to open sidebar drawer (20px zone)
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
- [ ] Right-edge swipe to reveal member list
- [ ] Swipe between content panels (messages ↔ threads ↔ members)
- [ ] Horizontal page-swipe navigation between sidebar / content / member panels

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| ~~No global Android back button handler~~ | ~~High~~ | Implemented: `main_window.gd` `_unhandled_input()` pops `NavigationHistory` and dispatches close actions. |
| ~~No navigation history stack~~ | ~~High~~ | Implemented: `NavigationHistory` class tracks drawer, thread, voice_view, discovery, lightbox entries. |
| No right-edge swipe for member list | Medium | The drawer gesture system only handles the left-edge sidebar. In COMPACT mode the member list is hidden entirely (main_window.gd line 383) with no swipe gesture to reveal it. A right-edge swipe mirroring the drawer system could show a member list overlay. |
| No horizontal page-swipe navigation | Medium | Mobile chat apps commonly allow swiping left/right to move between sidebar, content, and member panels. Currently the only way to access the sidebar in COMPACT mode is the edge swipe or hamburger button. A full-width page-swipe system would feel more native. |
| Drawer closes channel panel auto-open only | Low | When entering COMPACT mode, `sidebar.set_channel_panel_visible_immediate(true)` forces the channel panel open (line 378). There is no memory of which space/channel the user was browsing if they close and reopen the drawer. |
| Edge swipe zone may be too narrow on high-DPI | Low | `EDGE_SWIPE_ZONE = 20.0` is in logical pixels. On high-DPI Android devices this maps to ~7-10 physical pixels, which may be difficult to hit. The value is not scaled by `_get_screen_density_scale()` (main_window.gd line 222). |
| No swipe-to-dismiss for image lightbox | Low | The image lightbox overlay has no swipe-down-to-dismiss gesture, which is a common mobile pattern. Currently requires tapping outside the image. |
| Thread panel has no swipe-back gesture | Low | In COMPACT mode, the thread panel replaces the message view (line 389). The only way back is the thread close button. A left-swipe or back gesture to return to messages would improve navigation. |
