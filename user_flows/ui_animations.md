# UI Animations

## Overview

Daccord uses tween-based animations, shader-driven effects, per-frame `_process` loops, and signal-driven hover states to provide visual feedback across the UI. All tweens use 0.15–0.3s durations with cubic easing for a snappy feel. There are no `AnimationPlayer` nodes — every animation is code-driven.

## User Steps

1. **Sidebar drawer (compact mode):** User taps the hamburger button → sidebar slides in from the left with a backdrop fade. Tapping the backdrop or navigating closes it with a reverse slide.
2. **Channel panel expand/collapse (medium mode):** User clicks a guild icon → channel panel width animates from 0 → 240px. Selecting a channel collapses it back.
3. **Guild icon hover:** User hovers over a guild icon → avatar morphs from circle to rounded square via shader. Moving away reverses the morph.
4. **Pill indicator:** Selecting a guild animates the left-side pill from hidden to active height (20px). Switching away shrinks it back.
5. **Typing indicator:** When another user types, three dots pulse with a sine wave alpha animation.
6. **Message hover:** Hovering a message highlights it and shows an action bar. Moving away hides both after a 0.1s debounce.
7. **Role assignment feedback:** Toggling a role on a member flashes the row green (success) or red (failure).

## Signal Flow

```
User action
    │
    ├─ Hamburger tap ─────► AppState.sidebar_drawer_toggled
    │                              │
    │                    main_window._on_sidebar_drawer_toggled()
    │                              │
    │                    ┌─────────┴──────────┐
    │                    │ is_open?           │
    │                    ▼                    ▼
    │              _open_drawer()      _close_drawer()
    │              tween slide+fade    tween slide+fade
    │
    ├─ Guild click ───────► sidebar.set_channel_panel_visible(true)
    │                              │
    │                    tween custom_minimum_size:x → 240
    │
    ├─ Guild hover ───────► guild_icon._on_hover_enter()
    │                              │
    │                    avatar_rect.tween_radius(0.5, 0.3)
    │                              │
    │                    avatar.tween_method → set_radius()
    │                              │
    │                    shader uniform "radius" updated
    │
    ├─ Guild select ──────► guild_icon.set_active(true)
    │                              │
    │                    pill.set_state_animated(ACTIVE)
    │                              │
    │                    tween size:y → 20.0
    │
    ├─ Message hover ─────► message_view._on_msg_hovered()
    │                              │
    │                    msg_node.set_hovered(true) → queue_redraw()
    │                    _action_bar.show_for_message()
    │
    └─ Typing event ──────► AppState.typing_started
                                   │
                         typing_indicator.show_typing()
                                   │
                         set_process(true) → _process() sine loop
```

## Key Files

| File | Role |
|------|------|
| `scenes/main/main_window.gd` | Drawer slide/fade tweens (lines 289–315) |
| `scenes/sidebar/sidebar.gd` | Channel panel expand/collapse tweens (lines 87–101) |
| `scenes/common/avatar.gd` | `tween_radius()` for shader-driven shape morphing (lines 93–104) |
| `theme/avatar_circle.gdshader` | Shader that interpolates circle ↔ rounded rectangle via `radius` uniform |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Hover/press/active avatar morphing (lines 92–104) |
| `scenes/sidebar/guild_bar/pill.gd` | Animated pill height transitions (lines 29–40) |
| `scenes/messages/typing_indicator.gd` | Sine wave dot alpha animation in `_process` (lines 25–31) |
| `scenes/messages/message_view.gd` | Action bar hover state machine with debounce timer (lines 266–316) |
| `scenes/messages/cozy_message.gd` | `set_hovered()` / `_draw()` for hover highlight (lines 133–139) |
| `scenes/messages/collapsed_message.gd` | `set_hovered()` / `_draw()` for hover highlight (lines 123–129) |
| `scenes/members/member_item.gd` | `_flash_feedback()` modulate tween (lines 154–158) |
| `scenes/sidebar/channels/channel_item.gd` | Gear button show/hide on hover (lines 104–110) |
| `scenes/sidebar/channels/category_item.gd` | Plus button show/hide on hover (lines 111–117) |
| `scenes/sidebar/direct/dm_channel_item.gd` | Close button show/hide on hover (lines 20–21) |
| `scenes/messages/collapsed_message.gd` | Timestamp show/hide on hover (lines 58–64) |
| `scenes/search/search_result_item.gd` | StyleBox swap on hover (lines 74–79) |

## Implementation Details

### Drawer Slide Animation (main_window.gd)

The sidebar drawer is used in compact layout mode (<500px viewport). Two parallel tweens run simultaneously (line 300):

- **Open** (`_open_drawer`, line 289): Sidebar starts off-screen at `position.x = -dw` and tweens to `0.0` over 0.2s with `EASE_OUT` / `TRANS_CUBIC`. The backdrop fades from alpha 0 → 1.
- **Close** (`_close_drawer`, line 306): Reverses both tweens using `EASE_IN` / `TRANS_CUBIC`. A chained callback (`_hide_drawer_nodes`, line 315) hides the backdrop and container after the animation completes.
- **Immediate close** (`_close_drawer_immediate`, line 317): Kills any running tween and hides nodes instantly — used when switching layout modes.

The drawer width is calculated by `_get_drawer_width()` based on viewport size, clamped to `BASE_DRAWER_WIDTH` (308px, line 3).

Any running tween is killed before starting a new one (lines 290, 307) to prevent conflicts.

### Channel Panel Expand/Collapse (sidebar.gd)

The channel panel animates its `custom_minimum_size.x` between 0 and `CHANNEL_PANEL_WIDTH` (240px, line 3) over `CHANNEL_PANEL_ANIM_DURATION` (0.15s, line 4):

- **Expand** (line 90): Makes panel visible first, then tweens width up with `EASE_OUT` / `TRANS_CUBIC`.
- **Collapse** (line 96): Tweens width down with `EASE_IN` / `TRANS_CUBIC`, then hides the panel via a tween callback (line 101).
- **Immediate** (`set_channel_panel_visible_immediate`, line 103): Kills any tween and sets state instantly — used during layout mode transitions.

### Avatar Shape Morphing (avatar.gd + avatar_circle.gdshader)

The avatar shader (`avatar_circle.gdshader`) uses a `radius` uniform (range 0.0–0.5, line 3). When `radius >= 0.5` (line 8), it renders a pure circle using `length(uv)`. Below 0.5, it computes a signed distance field for a rounded rectangle (lines 12–14), producing smooth corners. Anti-aliasing is applied via `fwidth()` + `smoothstep()` (lines 18–19).

`avatar.gd` exposes `tween_radius(from, to, duration)` (line 99) which uses `tween_method()` to animate the shader parameter. Default duration is 0.15s. The method returns the `Tween` object (or `null` if no shader material is set).

### Guild Icon Hover Morphing (guild_icon.gd)

Four signal connections (lines 29–32) drive the avatar shape:

- `mouse_entered` → `tween_radius(0.5, 0.3)` — circle to rounded square (line 93)
- `mouse_exited` → `tween_radius(0.3, 0.5)` — only if not active (lines 95–97)
- `button_down` → `tween_radius(0.5, 0.3)` — press feedback (line 100)
- `button_up` → `tween_radius(0.3, 0.5)` — only if not active (lines 102–104)

When `set_active(true)` is called (line 79), the avatar stays in rounded-square form permanently.

### Pill Selection Indicator (pill.gd)

Three states (line 3): `HIDDEN` (invisible), `UNREAD` (6px tall), `ACTIVE` (20px tall).

`set_state_animated()` (line 29) bypasses the property setter via `_skip_update`, then creates a tween that animates both `custom_minimum_size:y` and `size:y` in parallel to the target height over 0.15s (lines 39–40). For `HIDDEN`, it simply sets `visible = false` without tweening (line 34).

### Typing Indicator Dots (typing_indicator.gd)

Uses `_process(delta)` (line 25) for continuous animation:

- Increments `anim_time` each frame (line 26).
- Each dot's alpha is calculated as `sin(anim_time * 3.0 - float(i) * 0.8)` (line 28), creating a staggered wave. The `0.8` phase offset spaces the dots' peaks apart.
- Alpha is normalized to 0–1 range and clamped between 0.3 and 1.0 (lines 29–30), so dots never fully disappear.
- `set_process(false)` in `_ready()` (line 23) ensures no CPU cost when hidden. Processing is enabled by `show_typing()` (line 37) and disabled by `hide_typing()` (line 42).
- A 10-second timeout timer (line 19) auto-hides if no further typing events arrive.

### Message Hover Highlight (cozy_message.gd / collapsed_message.gd)

Both message types implement `set_hovered(bool)` which sets a flag and calls `queue_redraw()`. The `_draw()` override renders a translucent overlay (`Color(0.24, 0.25, 0.27, 0.3)`) over the full node rect when hovered (cozy_message.gd lines 137–139, collapsed_message.gd lines 127–129). This is an instant visual change — no tween.

### Action Bar Hover State Machine (message_view.gd)

The action bar (reply/edit/delete buttons) appears on message hover with debounce logic:

1. `_on_msg_hovered()` (line 266): Stops the hide timer, clears previous highlight, applies new highlight, positions the action bar above the message.
2. `_on_msg_unhovered()` (line 292): Sets `_hover_hide_pending = true` and starts a 0.1s debounce timer.
3. `_on_hover_timer_timeout()` (line 300): If still pending and the action bar itself isn't hovered, hides everything.
4. `_on_action_bar_unhovered()` (line 296): Also starts the debounce timer, allowing the user to move between message and action bar without flickering.

The action bar is suppressed in compact mode (line 267) and when a message is being edited (lines 270–272).

### Role Assignment Flash (member_item.gd)

`_flash_feedback(color)` (line 154) creates a two-step tween:
1. Tween `modulate` to the feedback color (blended with white) over 0.15s.
2. Tween `modulate` back to the original value over 0.3s.

Green (`Color(0.231, 0.647, 0.365, 0.3)`) for success, red (`Color(0.929, 0.259, 0.271, 0.3)`) for failure (lines 148–150).

### Instant Hover Effects (No Tween)

Several components use instant show/hide on `mouse_entered` / `mouse_exited`:

| Component | What appears | Lines |
|-----------|-------------|-------|
| `channel_item.gd` | Settings gear button | 104–110 |
| `category_item.gd` | Create channel (+) button | 111–117 |
| `dm_channel_item.gd` | Close (×) button | 20–21 |
| `collapsed_message.gd` | Timestamp label | 58–64 |
| `search_result_item.gd` | Background highlight (StyleBox swap) | 74–79 |

### Guild Folder Expand/Collapse (guild_folder.gd)

Toggling a guild folder (`_toggle_expanded`, line 56) instantly swaps between a mini-grid preview of up to 4 color swatches and the full guild list. No animation — pure visibility toggle (lines 58–59).

## Implementation Status

- [x] Drawer slide + backdrop fade animation
- [x] Channel panel width expand/collapse animation
- [x] Avatar circle ↔ rounded-square shader morph
- [x] Guild icon hover/press/active avatar transitions
- [x] Pill height animation for guild selection indicator
- [x] Typing indicator sine wave dot animation
- [x] Message hover highlight with `_draw()` overlay
- [x] Action bar hover debounce state machine
- [x] Role assignment flash feedback
- [x] Instant hover effects for secondary UI elements (gear, plus, close, timestamp)
- [x] Search result hover highlight
- [ ] Guild folder expand/collapse animation (currently instant)
- [ ] Scroll-to-bottom animation (currently instant jump)
- [ ] Channel selection transition (no cross-fade or slide)
- [ ] Message appear/disappear animation (messages pop in instantly)
- [ ] Action bar fade-in/fade-out (appears/disappears instantly)
- [ ] Reaction pill press animation (no scale/bounce feedback)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Guild folder expand/collapse has no animation | Low | `guild_folder.gd:56` — just toggles `visible` on mini_grid and guild_list. A height tween would be smoother. |
| Scroll-to-bottom is instant | Low | `message_view.gd:230` — calls `_scroll_to_bottom()` directly. Could use `scroll_container.ensure_control_visible()` with a tween for smooth scrolling. |
| No message enter/exit animation | Medium | Messages appear instantly when added to `message_list`. A fade-in or slide-up would improve perceived polish. |
| Action bar appears/disappears instantly | Low | `message_view.gd:289,312` — `show_for_message()` and `hide_bar()` have no opacity tween. A quick fade (0.1s) would feel less jarring. |
| No channel transition animation | Low | Switching channels replaces the message list instantly. A brief cross-fade or slide could smooth the transition. |
| Reaction pill has no press animation | Low | `reaction_pill.gd:64` — `_update_active_style()` swaps StyleBoxes instantly. A subtle scale bounce would add tactile feedback. |
| Drawer tween not reused for edge swipe | Low | `main_window.gd` supports edge swipe detection (lines 5–6) but the swipe doesn't drive the drawer position interactively — it triggers the same tween. A gesture-driven animation would feel more native on touch. |
| No loading skeleton/shimmer animation | Medium | While messages load, `loading_label` shows static text. A shimmer or skeleton placeholder animation would improve perceived performance. |
