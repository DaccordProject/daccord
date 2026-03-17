# UI Animations

Priority: 33
Depends on: None
Status: Complete

Tween-based drawer/panel/pill/avatar animations, shader morphing, typing indicator sine wave, hover state machines, loading skeleton shimmer, gesture-driven swipe tracking, and flash feedback.

## Key Files

| File | Role |
|------|------|
| `scenes/main/main_window.gd` | Drawer slide/fade tweens, gesture-driven open/close swipe |
| `scenes/sidebar/sidebar.gd` | Channel panel expand/collapse tweens (lines 87-101) |
| `scenes/common/avatar.gd` | `tween_radius()` for shader-driven shape morphing (lines 93-104) |
| `theme/avatar_circle.gdshader` | Shader that interpolates circle <-> rounded rectangle via `radius` uniform |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Hover/press/active avatar morphing (lines 92-104) |
| `scenes/sidebar/guild_bar/pill.gd` | Animated pill height transitions (lines 29-40) |
| `scenes/messages/typing_indicator.gd` | Sine wave dot alpha animation in `_process` (lines 25-31) |
| `scenes/messages/message_view.gd` | Scroll-to-bottom tween, message/channel fade-in, diff fade-in, action bar hover state machine |
| `scenes/messages/message_action_bar.gd` | Action bar fade-in/fade-out alpha tweens |
| `scenes/messages/reaction_pill.gd` | Press bounce scale animation with TRANS_BACK |
| `scenes/messages/cozy_message.gd` | `set_hovered()` / `_draw()` for hover highlight |
| `scenes/messages/collapsed_message.gd` | `set_hovered()` / `_draw()` for hover highlight |
| `scenes/members/member_item.gd` | `_flash_feedback()` modulate tween |
| `scenes/messages/loading_skeleton.gd` | Skeleton shimmer `_process` loop, builds 5 placeholder rows |
| `scenes/messages/loading_skeleton.tscn` | VBoxContainer scene for skeleton placeholders |
| `theme/skeleton_shimmer.gdshader` | SDF rounded rect + horizontal shimmer sweep shader |
