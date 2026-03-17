# Responsive Layout

Priority: 9
Depends on: Space & Channel Navigation, Messaging
Status: Complete

Three layout modes (COMPACT <500px, MEDIUM 500-767px, FULL >=768px) with sidebar drawer overlay, panel toggles, resize handles, edge-swipe gestures, and reduced-motion support.

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | `LayoutMode` enum (line 191), `COMPACT_BREAKPOINT`/`MEDIUM_BREAKPOINT` constants (lines 193-194), layout state vars, `update_layout_mode()` (line 281), `toggle_sidebar_drawer()`, `close_sidebar_drawer()`, `toggle_channel_panel()`, `toggle_member_list()`, `toggle_search()`, `close_search()` |
| `scenes/main/main_window.gd` | Layout orchestration, `_on_layout_mode_changed()` (line 331), panel toggle wiring, resize handle creation (lines 150-177), `_sync_handle_visibility()` (line 393), `_clamp_panel_widths()` (line 403), voice view exception handling (lines 332-347) |
| `scenes/main/main_window_drawer.gd` | `MainWindowDrawer` class: sidebar reparenting (`move_sidebar_to_layout`/`move_sidebar_to_drawer`), drawer open/close animations, `get_drawer_width()`, reduced-motion support |
| `scenes/main/drawer_gestures.gd` | `DrawerGestures` class: edge-swipe open (lines 37-89), swipe-to-close (lines 174-225), interactive drag tracking with velocity-based snap (`_should_snap_open`, line 279) |
| `scenes/main/panel_resize_handle.gd` | `PanelResizeHandle` class: draggable resize handles for side panels, double-click-to-reset, visibility tracks target panel |
| `scenes/main/main_window.tscn` | Scene structure: LayoutHBox, ContentHeader (HamburgerButton, SidebarToggle, TabBar, SearchToggle, MemberListToggle), TopicBar, ContentBody (MessageView, ThreadPanel, MemberList, SearchPanel, VoiceTextPanel), DrawerBackdrop, DrawerContainer |
| `scenes/sidebar/sidebar.gd` | MEDIUM mode channel panel auto-show/hide on space/channel selection, `set_channel_panel_visible()` (animated), `set_channel_panel_visible_immediate()` |
| `scenes/messages/collapsed_message.gd` | Responsive timestamp: always visible in COMPACT, hover-only in MEDIUM/FULL |
| `scenes/messages/thread_panel.gd` | `_apply_layout()`: COMPACT uses back-arrow button + min width 0; non-COMPACT uses X button + min width 340 |
| `scenes/messages/message_view_hover.gd` | `on_layout_mode_changed()`: hides action bar in COMPACT; `on_msg_hovered()`: suppresses hover in COMPACT |
| `scenes/messages/forum_view.gd` | `_apply_layout()`: COMPACT shrinks title font and collapses "New Post" to "+" icon |
| `scenes/video/video_grid.gd` | `_update_grid_columns()`: inline mode uses 1 col (COMPACT) or 2 cols (MEDIUM/FULL); full-area mode uses adaptive columns |
| `scenes/main/welcome_screen.gd` | `_apply_layout()`: COMPACT switches feature cards from HBox to VBox layout |
