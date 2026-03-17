# Theming

Priority: 32
Depends on: None
Status: Complete

daccord uses a centralized `ThemeManager` autoload that holds a semantic color palette with 37 keys. Five built-in presets (Dark, Light, Nord, Monokai, Solarized) and a Custom mode with per-color pickers are available from the Appearance settings page. Theme sharing works via base64-encoded JSON strings that can be copied/pasted or detected inline in chat messages. The global Godot Theme resource (`discord_dark.tres`) is patched at runtime by ThemeManager, and 49 components join the `"themed"` group to receive live `_apply_theme()` callbacks when the palette changes.

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/theme_manager.gd` | Central palette manager — 5 presets (37 keys each), get/set_color, apply_preset, export/import theme strings, `apply_font_colors()` tree walker (line 161) |
| `assets/theme/discord_dark.tres` | Global Godot Theme resource — patched at runtime by ThemeManager._apply_to_theme() |
| `project.godot:37` | Registers ThemeManager as autoload; line 55 sets `gui/theme/custom` to `discord_dark.tres` |
| `scenes/user/app_settings.gd` | Builds the Appearance page (lines 416–563): theme dropdown, preview swatches, custom color pickers, sharing buttons, reduce motion, UI scale, emoji skin tone |
| `scenes/user/settings_base.gd` | Shared settings panel base — all colors via ThemeManager (lines 22, 41, 51, 70, 150, 214, 243, 272) |
| `scripts/autoload/config.gd` | Persists theme_preset, custom_palette (lines 543–558), reduced_motion, ui_scale, emoji_skin_tone (lines 521–539) |
| `scripts/autoload/app_state.gd` | Signals: `config_changed` (line 157), `theme_changed` (line 165), `reduce_motion_changed` (line 169) |
| `scripts/autoload/client_models.gd` | `status_color()` (line 67) uses ThemeManager keys: status_online, status_idle, status_dnd, status_offline |
| `scenes/main/main_window.gd` | `_apply_ui_scale()` (line 195), `_on_config_changed()` (line 762) for live scale, `_apply_theme()` (line 789) updates drawer backdrop overlay color |
| `scenes/sidebar/channels/channel_list.gd` | `_apply_theme()` (line 31) updates channel panel bg to `panel_bg`, applies font colors |
| `scenes/sidebar/guild_bar/guild_bar.gd` | `_apply_theme()` (line 28) updates guild bar bg to `input_bg` |
| `scenes/sidebar/voice_bar.gd` | `_apply_theme()` (line 45) updates voice bar bg to `nav_bg`, applies font colors |
| `scenes/sidebar/user_bar.gd` | `_apply_theme()` (line 65) updates user bar bg to `input_bg`, applies font colors |
| `scenes/sidebar/direct/dm_list.gd` | `_apply_theme()` (line 27) updates DM panel bg to `panel_bg` |
| `scenes/messages/composer/composer.gd` | `_apply_theme()` (line 47) updates composer bg to `button_hover`, applies font colors |
| `scenes/messages/thread_panel.gd` | `_apply_theme()` (line 33) updates thread panel bg to `panel_bg`, applies font colors |
| `scenes/messages/voice_text_panel.gd` | `_apply_theme()` (line 33) updates voice text panel bg to `panel_bg` |
| `scenes/messages/message_action_bar.gd` | `_apply_theme()` (line 29) updates action bar bg to `panel_bg` |
| `scenes/video/video_grid.gd` | `_apply_theme()` (line 33) updates video grid bg to `nav_bg` |
| `scenes/video/video_tile.gd` | `_apply_theme()` (line 19) applies font colors; speaking border uses ThemeManager `status_online` |
| `scenes/soundboard/soundboard_panel.gd` | `_apply_theme()` (line 19) updates soundboard bg to `modal_bg` |
| `scenes/common/modal_base.gd` | `_apply_theme()` (line 107) updates modal overlay/panel bg to `overlay`/`modal_bg`, calls `ThemeManager.apply_font_colors(self)` to update all child node font colors |
| `scenes/messages/message_content.gd` | `_detect_theme_string()` (line 183) — detects base64 theme strings in chat, shows "Apply Theme" button |
| `scenes/messages/loading_skeleton.gd` | Reactive reduce_motion via `_on_reduce_motion_changed()` (line 89) |
| `scenes/common/avatar.gd` | `_apply_theme()` (line 35) updates `ring_color` shader uniform on both base material and texture rect material from ThemeManager `status_online` |
| `scenes/main/welcome_screen.gd` | `_apply_shader_accent()` (line 296) sets welcome_bg shader `accent_color`, `bg_navy`, `bg_purple` from ThemeManager |
| `scenes/messages/update_banner.gd` | `_apply_theme()` applies font colors for version/action labels |
| `assets/theme/avatar_circle.gdshader` | Avatar shape shader — `ring_color` uniform set from GDScript |
| `assets/theme/welcome_bg.gdshader` | Welcome gradient shader — `accent_color`, `bg_navy`, `bg_purple` uniforms (lines 6–8) set from GDScript |
| `assets/theme/skeleton_shimmer.gdshader` | Loading placeholder shimmer animation |
