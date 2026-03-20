# Responsive Layout

Priority: 9
Depends on: Space & Channel Navigation, Messaging
Status: Complete

Three layout modes (COMPACT <500px, MEDIUM 500–767px, FULL ≥768px) driven by `AppState.update_layout_mode()`. COMPACT converts sidebar to a drawer overlay with edge-swipe gestures; MEDIUM auto-hides channel panel and member list; FULL shows all panels with drag-to-resize handles. DPI-aware auto-scaling via `_auto_ui_scale()` ensures logical viewport lands in the correct breakpoint on high-DPI and mobile screens.

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | LayoutMode enum, breakpoint constants, layout state, toggle methods |
| `scenes/main/main_window.gd` | Layout orchestration, mode-change dispatch, resize handles, panel clamping |
| `scenes/main/main_window_drawer.gd` | Sidebar reparenting, drawer open/close animations |
| `scenes/main/drawer_gestures.gd` | Edge-swipe open/close with velocity-based snap |
| `scenes/main/panel_resize_handle.gd` | Draggable resize handles with double-click reset |
| `scenes/sidebar/sidebar.gd` | MEDIUM mode channel panel auto-show/hide |
| `scenes/messages/collapsed_message.gd` | COMPACT: timestamps always visible |
| `scenes/messages/message_view_hover.gd` | COMPACT: suppresses hover action bar |
| `scenes/messages/thread_panel.gd` | COMPACT: back-arrow replaces X, min width 0 |
| `scenes/messages/forum_view.gd` | COMPACT: smaller title, "+" replaces "New Post" |
| `scenes/video/video_grid.gd` | Adaptive grid columns per layout mode |
| `scenes/main/welcome_screen.gd` | COMPACT: VBox feature cards instead of HBox |
