# UI Animations


## Overview

Daccord uses tween-based animations, shader-driven effects, per-frame `_process` loops, and signal-driven hover states to provide visual feedback across the UI. All tweens use 0.15–0.3s durations with cubic easing for a snappy feel. There are no `AnimationPlayer` nodes — every animation is code-driven.

## User Steps

1. **Sidebar drawer (compact mode):** User taps the hamburger button → sidebar slides in from the left with a backdrop fade. Tapping the backdrop or navigating closes it with a reverse slide. Edge-swiping from the left tracks the finger in real-time, snapping open or closed on release.
2. **Channel panel expand/collapse (medium mode):** User clicks a guild icon → channel panel width animates from 0 → 240px. Selecting a channel collapses it back.
3. **Guild icon hover:** User hovers over a guild icon → avatar morphs from circle to rounded square via shader. Moving away reverses the morph.
4. **Pill indicator:** Selecting a guild animates the left-side pill from hidden to active height (20px). Switching away shrinks it back.
5. **Typing indicator:** When another user types, three dots pulse with a sine wave alpha animation.
6. **Message hover:** Hovering a message highlights it and shows an action bar. Moving away hides both after a 0.1s debounce.
7. **Role assignment feedback:** Toggling a role on a member flashes the row green (success) or red (failure).
8. **Loading skeleton:** While messages load, animated skeleton placeholders (avatar circles + text bars) with a horizontal shimmer sweep appear instead of static text.
9. **Gesture-driven drawer swipe:** In compact mode, swiping from the left edge tracks the drawer position in real-time. Release past 50% or with a fast flick to open; otherwise it snaps closed. Swiping left on the backdrop closes the drawer with the same tracking behavior.

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
    ├─ Typing event ──────► AppState.typing_started
    │                              │
    │                    typing_indicator.show_typing()
    │                              │
    │                    set_process(true) → _process() sine loop
    │
    ├─ Channel select ───► message_view._on_channel_selected()
    │                              │
    │                    loading_skeleton.visible = true
    │                    loading_skeleton.reset_shimmer()
    │                              │
    │                    _process() sweeps shimmer_offset -0.5→1.5
    │                              │
    │                    messages arrive → skeleton hidden
    │
    └─ Edge swipe ───────► main_window._handle_open_swipe()
                                   │
                         _begin_drawer_tracking() → show nodes
                                   │
                         _update_drawer_position() → track finger
                                   │
                         release → _finish_open_swipe()
                                   │
                         _should_snap_open() → snap tween
```

## Key Files

| File | Role |
|------|------|
| `scenes/main/main_window.gd` | Drawer slide/fade tweens, gesture-driven open/close swipe |
| `scenes/sidebar/sidebar.gd` | Channel panel expand/collapse tweens (lines 87–101) |
| `scenes/common/avatar.gd` | `tween_radius()` for shader-driven shape morphing (lines 93–104) |
| `theme/avatar_circle.gdshader` | Shader that interpolates circle ↔ rounded rectangle via `radius` uniform |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Hover/press/active avatar morphing (lines 92–104) |
| `scenes/sidebar/guild_bar/pill.gd` | Animated pill height transitions (lines 29–40) |
| `scenes/messages/typing_indicator.gd` | Sine wave dot alpha animation in `_process` (lines 25–31) |
| `scenes/messages/message_view.gd` | Scroll-to-bottom tween (lines 705–715), message/channel fade-in (lines 256–271), diff fade-in (lines 416–422), action bar hover state machine (lines 498–548) |
| `scenes/messages/message_action_bar.gd` | Action bar fade-in/fade-out alpha tweens (lines 32–49) |
| `scenes/messages/reaction_pill.gd` | Press bounce scale animation with TRANS_BACK (lines 50–57) |
| `scenes/messages/cozy_message.gd` | `set_hovered()` / `_draw()` for hover highlight (lines 133–139) |
| `scenes/messages/collapsed_message.gd` | `set_hovered()` / `_draw()` for hover highlight (lines 123–129) |
| `scenes/members/member_item.gd` | `_flash_feedback()` modulate tween (lines 154–158) |
| `scenes/sidebar/channels/channel_item.gd` | Gear button show/hide on hover (lines 104–110) |
| `scenes/sidebar/channels/category_item.gd` | Plus button show/hide on hover (lines 111–117) |
| `scenes/sidebar/direct/dm_channel_item.gd` | Close button show/hide on hover (lines 20–21) |
| `scenes/messages/collapsed_message.gd` | Timestamp show/hide on hover (lines 58–64) |
| `scenes/search/search_result_item.gd` | StyleBox swap on hover (lines 74–79) |
| `scenes/messages/loading_skeleton.gd` | Skeleton shimmer `_process` loop, builds 5 placeholder rows |
| `scenes/messages/loading_skeleton.tscn` | VBoxContainer scene for skeleton placeholders |
| `theme/skeleton_shimmer.gdshader` | SDF rounded rect + horizontal shimmer sweep shader |

## Implementation Details

### Drawer Slide Animation (main_window.gd)

The sidebar drawer is used in compact layout mode (<500px viewport). It supports both signal-driven tweens (hamburger button) and gesture-driven real-time tracking (edge swipe / backdrop swipe).

**Signal-driven (hamburger button):** Two parallel tweens run simultaneously:

- **Open** (`_open_drawer`): Sidebar starts off-screen at `position.x = -dw` and tweens to `0.0` over 0.2s with `EASE_OUT` / `TRANS_CUBIC`. The backdrop fades from alpha 0 → 1.
- **Close** (`_close_drawer`): Reverses both tweens using `EASE_IN` / `TRANS_CUBIC`. A chained callback (`_hide_drawer_nodes`) hides the backdrop and container after the animation completes.
- **Immediate close** (`_close_drawer_immediate`): Kills any running tween and hides nodes instantly — used when switching layout modes.

**Gesture-driven (edge swipe to open):** `_handle_open_swipe()` processes touch/mouse events:

1. Press in edge zone (x <= 20px) starts tracking.
2. Past a 10px dead zone, `_begin_drawer_tracking()` shows drawer nodes and sets initial position.
3. `_update_drawer_position()` maps finger position to drawer progress (0–1), updating `sidebar.position.x` and `drawer_backdrop.modulate.a` in real-time. Velocity is tracked via `(pos_x - last_x) / dt`.
4. On release, `_finish_open_swipe()` decides snap direction: if `|velocity| > 400px/s`, snap based on velocity direction; otherwise snap based on progress vs 0.5 threshold.
5. `_snap_drawer_open()` / `_snap_drawer_closed()` tween from the current position with proportional duration (`0.2 * remaining_progress`, minimum 0.05s).

**Gesture-driven (backdrop swipe to close):** `_handle_close_swipe()` processes events on the backdrop area (pos_x > drawer_width):

1. Press on backdrop starts close tracking, consuming the event to prevent the backdrop tap handler from firing.
2. Past a 10px leftward dead zone, `_update_close_drawer_position()` tracks finger in real-time.
3. On release, same velocity/progress snap logic as open (inverted).
4. A simple tap on the backdrop (no drag) still closes instantly via the fallback path.

The drawer width is calculated by `_get_drawer_width()` based on viewport size, clamped to `BASE_DRAWER_WIDTH` (308px).

Any running tween is killed before starting a new one to prevent conflicts. All gesture animations respect `Config.get_reduced_motion()` — when enabled, snaps are instant.

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

### Scroll-to-Bottom Animation (message_view.gd)

`_scroll_to_bottom_animated()` (line 705) smoothly scrolls the message list to the bottom:

- Calculates the target scroll position from `scroll_container.get_v_scroll_bar().max_value` (line 706).
- **Short-circuit** (lines 708–710): If the distance is less than 50px, snaps instantly — tweening a tiny distance looks jittery.
- Kills any existing scroll tween before creating a new one (lines 711–712).
- Tweens `scroll_container.scroll_vertical` to the target over **0.2s** with `EASE_OUT` / `TRANS_CUBIC` (lines 714–715).

Triggered in two places:
1. **Channel load** (line 277): After `_load_messages()` populates the message list, called unconditionally (unless loading older messages).
2. **New messages via diff** (line 427): After `_diff_messages()` appends new nodes, called only when `auto_scroll` is enabled and nodes were appended. Waits one `process_frame` to let layout settle.

### Channel Transition Fade-In (message_view.gd)

When switching channels, the entire `scroll_container` fades in (lines 264–271):

- Sets `scroll_container.modulate.a = 0.0` (line 268).
- Tweens `modulate:a` to `1.0` over **0.15s** with `EASE_OUT` / `TRANS_CUBIC` (lines 270–271).
- Kills any existing `_channel_transition_tween` first (lines 266–267).

The condition (line 264) ensures this only fires when:
- NOT loading older messages (`not _is_loading_older`)
- AND the message count changed by more than one (`old_count != new_count`), which excludes single new messages that get their own per-node fade.

### Message Appear Fade-In (message_view.gd)

New messages fade in individually at two code paths:

**Single new message** (lines 256–263): When exactly one message is added to an existing list (`old_count > 0 and new_count == old_count + 1`), the last message child's `modulate.a` is set to `0.0` and tweened to `1.0` over **0.15s** with `EASE_OUT` / `TRANS_CUBIC`.

**Diff-appended messages** (lines 416–422): When `_diff_messages()` appends new nodes, each appended node's `modulate.a` is set to `0.0` and tweened individually with the same parameters. The `old_count > 0` guard prevents the animation on initial channel load.

Both paths use the same tween parameters for visual consistency: **0.15s**, `EASE_OUT`, `TRANS_CUBIC`.

### Action Bar Fade-In/Fade-Out (message_action_bar.gd)

The action bar uses alpha tweens for smooth appear/disappear:

- **Fade-in** (`show_for_message`, lines 32–38): Sets `modulate.a = 0.0`, makes `visible = true`, then tweens `modulate:a` to `1.0` over **0.1s** with `EASE_OUT` / `TRANS_CUBIC`. Also configures edit/delete button visibility based on message ownership (lines 29–31).
- **Fade-out** (`hide_bar`, lines 40–49): Tweens `modulate:a` to `0.0` over **0.1s** with `EASE_IN` / `TRANS_CUBIC`. A chained callback (lines 46–49) sets `visible = false` and resets `modulate.a = 1.0` so the next show starts clean.
- Both paths kill any existing `_fade_tween` before creating a new one (lines 32–33, 41–42).

The faster 0.1s duration (vs 0.15s for messages) keeps the bar snappy — it should feel like a tooltip, not a panel.

### Reaction Pill Press Bounce (reaction_pill.gd)

`_on_toggled()` (line 40) plays a bounce when the user clicks a reaction pill:

- **Scale up** (line 54): Instantly sets `scale = Vector2(1.15, 1.15)` (15% larger).
- **Bounce back** (lines 55–57): Tweens `scale` to `Vector2.ONE` over **0.15s** with `EASE_OUT` / `TRANS_BACK`. The `TRANS_BACK` transition overshoots slightly before settling, creating a spring-like feel.
- **Pivot** (line 53): Sets `pivot_offset = size / 2` so the scale animation expands from the pill's center.
- Kills any existing `_press_tween` first (lines 51–52).

The bounce runs alongside optimistic count updates (lines 44–48) and the server API call (lines 60–64), so visual feedback is instantaneous.

### Instant Hover Effects (No Tween)

Several components use instant show/hide on `mouse_entered` / `mouse_exited`:

| Component | What appears | Lines |
|-----------|-------------|-------|
| `channel_item.gd` | Settings gear button | 104–110 |
| `category_item.gd` | Create channel (+) button | 111–117 |
| `dm_channel_item.gd` | Close (×) button | 20–21 |
| `collapsed_message.gd` | Timestamp label | 58–64 |
| `search_result_item.gd` | Background highlight (StyleBox swap) | 74–79 |

### Loading Skeleton Shimmer (loading_skeleton.gd + skeleton_shimmer.gdshader)

While messages load, 5 skeleton placeholder rows appear instead of the static "Loading messages..." text. Each row mimics the cozy message layout:

- **Avatar placeholder:** 42×42 `ColorRect` with `corner_radius=0.5` (circle).
- **Text bars:** Author bar (90–140px wide, 14px tall) + 1–2 content bars (240–320px wide, 14px tall). Width varies per row for a natural look.
- **Color:** `Color(0.24, 0.25, 0.27)` — matching the message area background but slightly lighter.

The shimmer effect uses `skeleton_shimmer.gdshader`, which combines SDF-based rounded rectangle clipping (same pattern as `avatar_circle.gdshader`) with a horizontal brightness sweep:

- `shimmer_offset` uniform sweeps from -0.5 to 1.5 over 1.2s, looping continuously.
- The shimmer is a `smoothstep`-based highlight that adds ~0.15 brightness at the sweep position.
- All bars share the same `ShaderMaterial` offset so the shimmer looks coordinated across the row.

The `_process()` loop increments `shimmer_offset` each frame. `set_process(false)` is called in `_ready()` when `Config.get_reduced_motion()` is true, showing static gray shapes instead. `reset_shimmer()` resets the offset and re-enables processing when the skeleton becomes visible again (e.g., on retry).

**Integration with message_view.gd:**
- `_on_channel_selected()`: Shows skeleton, hides loading label.
- `_update_empty_state()`: Shows skeleton when `_is_loading`, hides it otherwise.
- `_on_message_fetch_failed()` / `_on_loading_timeout()`: Hides skeleton, shows error label.
- `_on_loading_label_input()` (retry): Hides error label, shows skeleton again.
- All message list iteration loops skip the skeleton node alongside `older_btn`, `empty_state`, and `loading_label`.

### Guild Folder Expand/Collapse (guild_folder.gd)

Toggling a guild folder (`_toggle_expanded`) swaps between a mini-grid preview and the full guild list with a fade animation. The mini-grid swap stays instant (it's the collapsed preview), but the guild list fades in/out:

- **Expand:** Makes `guild_list` visible, sets `modulate.a = 0`, tweens to 1.0 over 0.15s with `EASE_OUT` / `TRANS_CUBIC`.
- **Collapse:** Tweens `modulate.a` to 0.0 over 0.15s with `EASE_IN` / `TRANS_CUBIC`, then hides via tween callback.
- Any running tween is killed before starting a new one.

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
- [x] Guild folder expand/collapse fade animation
- [x] Scroll-to-bottom smooth tween animation
- [x] Channel selection transition fade-in
- [x] Message appear fade-in animation (single new messages)
- [x] Action bar fade-in/fade-out animation
- [x] Reaction pill press bounce animation
- [x] Loading skeleton shimmer animation
- [x] Gesture-driven drawer swipe (open + close)

## Gaps / TODO

No remaining gaps.
