# Theming

Priority: 32
Depends on: None

## Overview

daccord uses a centralized `ThemeManager` autoload that holds a semantic color palette with 37 keys. Five built-in presets (Dark, Light, Nord, Monokai, Solarized) and a Custom mode with per-color pickers are available from the Appearance settings page. Theme sharing works via base64-encoded JSON strings that can be copied/pasted or detected inline in chat messages. The global Godot Theme resource (`discord_dark.tres`) is patched at runtime by ThemeManager, and 49 components join the `"themed"` group to receive live `_apply_theme()` callbacks when the palette changes. All panel backgrounds, font colors, and shader uniforms update via `_apply_theme()` so theme changes propagate to every surface. Font colors in `.tscn` files use `metadata/theme_font_color` annotations that `ThemeManager.apply_font_colors()` resolves at runtime, while `text_body`-colored labels inherit from the project theme directly.

## User Steps

### Selecting a Theme Preset

1. Open App Settings (gear icon in user bar, or user bar menu > "App Settings")
2. Click "Appearance" in the left nav (page index 3)
3. Choose a preset from the THEME dropdown: Dark, Light, Nord, Monokai, Solarized
4. The theme applies instantly — preview swatches update below the dropdown showing accent, text, panel, nav, input, error, and success colors
5. To customize individual colors, select "Custom" from the dropdown and use the 8 color pickers (Accent, Text, Muted Text, Error/Danger, Success, Panel Background, Navigation Background, Input Background)

### Sharing a Custom Theme

1. Select "Custom" in the theme dropdown (or modify any preset colors)
2. Click "Copy Theme" — the palette is serialized to JSON, base64-encoded, and copied to clipboard
3. Share the base64 string in chat or any text channel
4. Recipient can either:
   - Open Appearance settings, click "Paste Theme" — imports from clipboard
   - Paste the theme string in chat — the client detects it and shows an "Apply Theme" button inline

### Adjusting Other Appearance Settings

1. Toggle "Reduce motion" to disable animations across 26+ consuming components
2. Drag the UI Scale slider (50%–200%) — applies live without restart
3. Choose an emoji skin tone from the dropdown

## Signal Flow

```
User selects theme preset / edits custom color
    │
    ▼
app_settings.gd ─► ThemeManager.apply_preset(name)
                    ThemeManager.apply_custom_color(key, color)
                          │
                          ├── Config.set_theme_preset(name) ──► Config._save()
                          ├── Config.set_custom_palette(dict)
                          ├── _apply_to_theme()  ──► patches discord_dark.tres StyleBoxes/colors
                          └── _notify_theme_changed()
                                    │
                                    ├── AppState.theme_changed.emit()
                                    └── get_tree().call_group("themed", "_apply_theme")
                                                │
                                                ▼
                                    49 components update inline overrides
                                    (panel backgrounds, font colors, shader uniforms)
                                                │
                                    ModalBase._apply_theme() calls
                                    ThemeManager.apply_font_colors(self)
                                                │
                                                ▼
                                    Recursive tree walk reads metadata/theme_font_color
                                    on child nodes and applies ThemeManager colors
                                    (90 annotated labels across 42 .tscn files)

User toggles Reduce Motion
    │
    ▼
app_settings.gd ─► Config.set_reduced_motion(enabled)
                          │
                          ├── Config._save()
                          ├── AppState.config_changed.emit("accessibility", "reduced_motion")
                          └── AppState.reduce_motion_changed.emit(enabled)
                                    │
                                    ▼
                          4 reactive listeners: loading_skeleton, welcome_screen,
                          voice_bar, add_server_button
                          22+ components poll Config.get_reduced_motion() at animation time

User drags UI Scale slider
    │
    ▼
app_settings.gd ─► Config._set_ui_scale(val)
                          │
                          └── AppState.config_changed.emit("accessibility", "ui_scale")
                                    │
                                    ▼
                          main_window.gd._on_config_changed() ─► _apply_ui_scale()
                          (live — sets content_scale_factor, resizes and re-centres window)
```

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

## Implementation Details

### ThemeManager (`theme_manager.gd`)

The centralized palette manager (autoload registered at `project.godot:37`). On `_ready()` (line 10): calls `_init_presets()` to build 5 preset palettes, `_load_palette()` to restore the saved preset/custom colors from Config, and `_apply_to_theme()` to patch the global Theme resource.

**Palette keys (37 per preset):**
- **Interaction:** `accent`, `accent_hover`, `accent_pressed`, `secondary_button`, `secondary_button_hover`, `secondary_button_pressed`
- **Text:** `text_body`, `text_muted`, `text_white`
- **Status:** `error`, `error_hover`, `error_pressed`, `success`, `warning`, `link`
- **Presence:** `status_online`, `status_idle`, `status_dnd`, `status_offline`
- **Surfaces:** `panel_bg`, `nav_bg`, `input_bg`, `modal_bg`, `settings_bg`, `popup_bg`, `content_bg`
- **UI:** `button_hover`, `button_pressed`, `scrollbar`, `scrollbar_hover`, `image_error_bg`, `reaction_border`
- **Icons:** `icon_default`, `icon_hover`, `icon_active`
- **Special:** `overlay`, `mention_bg`

The `content_bg` key is used for the main message view area, which is visually lighter than `panel_bg` (used for sidebar panels like channel list and DM list). The surface keys map to the UI hierarchy: `input_bg` (darkest, guild bar / user bar) → `nav_bg` (voice bar, video grid) → `panel_bg` (channel list, DM list, thread/voice-text panels, action bar) → `content_bg` (message area) → `modal_bg` (modals, emoji picker, embeds, soundboard).

**Public API:**
- `get_color(key) -> Color` (line 18) — returns palette color or MAGENTA with warning for unknown keys
- `get_palette() -> Dictionary` (line 25) — returns a copy of the full palette
- `apply_preset(name)` (line 35) — switches to a named preset, saves to Config, patches theme, notifies
- `apply_custom_color(key, color)` (line 45) — overrides one key, switches to "custom" preset, saves
- `get_preset_names() -> Array` (line 55) — `["dark", "light", "nord", "monokai", "solarized"]`
- `export_theme_string() -> String` (line 59) — serializes palette to JSON, base64-encodes
- `import_theme_string(base64) -> bool` (line 67) — decodes, validates, applies as custom preset
- `apply_font_colors(root) -> void` (line 161) — recursively walks child nodes; any Control with `metadata/theme_font_color` gets its `font_color` override set from ThemeManager

**Theme resource patching** (`_apply_to_theme()`, line 112): reads `ThemeDB.get_project_theme()` and sets `bg_color` on StyleBoxFlat resources for PanelContainer, PopupPanel, Button hover/pressed, LineEdit/TextEdit normal, ScrollBar grabber. Also sets font colors on Label, Button, LineEdit, TextEdit, RichTextLabel.

**Notification** (`_notify_theme_changed()`, line 92): emits `AppState.theme_changed` and calls `get_tree().call_group("themed", "_apply_theme")` — 49 components in the themed group receive the callback.

### Metadata-Based Font Color System

`.tscn` files annotate nodes with `metadata/theme_font_color = "key"` (e.g., `"text_muted"`, `"accent"`, `"error"`, `"warning"`, `"status_online"`, `"text_white"`). `ThemeManager.apply_font_colors(root)` (line 161) recursively walks all child Controls, reads this metadata, and calls `add_theme_color_override("font_color", get_color(key))`. This is called from:
- `ModalBase._apply_theme()` (line 109) — covers all dialog subclasses and their dynamically added child rows
- Individual themed components' `_apply_theme()` — covers non-modal scenes (message_view, composer, voice_bar, user_bar, channel_list, welcome_screen, thread_panel, voice_channel_item, dm_channel_item, update_banner, video_tile)
- Row item `_ready()` methods — covers dynamically instantiated rows (audit_log_row, ban_row, channel_row, emoji_cell, invite_row, role_row, sound_row, imposter_banner) that are added after their parent modal's initial `_apply_theme()` call

Labels colored as `text_body` (previously Color(0.7, 0.7, 0.7) in .tscn files) have their overrides removed entirely — they inherit from the project theme's Label `font_color`, which ThemeManager patches to `text_body` (line 126).

**Color key mapping (90 annotations across 42 .tscn files):**
- `"text_muted"` — muted descriptions, timestamps, info text
- `"accent"` — interactive links, load-more buttons, version labels
- `"error"` — delete buttons, error labels, danger actions
- `"text_white"` — high-contrast text on dark backgrounds (connection banner, topic bar)
- `"status_online"` — voice bar channel label, user bar voice indicator
- `"warning"` — imposter banner role label and exit button

### Appearance Page (`app_settings.gd`)

`_build_appearance_page()` (line 416) builds six sections:

1. **Theme preset** (line 420) — OptionButton populated from `ThemeManager.get_preset_names()` plus "Custom". Selecting a preset calls `ThemeManager.apply_preset()` (line 569). Selecting "Custom" shows color pickers and saves the current palette as a starting point.

2. **Theme preview swatches** (line 440) — HBoxContainer with 8 colored rectangles (28x28) showing Accent, Text, Muted, Panel, Nav, Input, Error, Success. Rebuilt via `_update_theme_preview()` (line 594) on every preset change or color edit.

3. **Custom color pickers** (line 446) — GridContainer with 8 `ColorPickerButton` widgets for editable keys: accent, text_body, text_muted, error, success, panel_bg, nav_bg, input_bg. Only visible when "Custom" is selected.

4. **Theme sharing** (line 483) — "Copy Theme" button calls `ThemeManager.export_theme_string()` and copies to clipboard. "Paste Theme" reads clipboard, calls `import_theme_string()`, and refreshes pickers. "Reset to Preset" reverts to dark.

5. **Reduce Motion** (line 517) — CheckBox bound to `Config.get/set_reduced_motion()`.

6. **UI Scale** (line 527) — HSlider range 50%–200% in 10% steps. Bound to `Config._set_ui_scale()`. Changes apply live via `main_window._on_config_changed()` (line 762).

7. **Emoji Skin Tone** (line 548) — OptionButton with 6 options (Default through Dark).

### Live UI Scale (`main_window.gd`)

`_apply_ui_scale()` (line 195) reads Config, auto-detects DPI if scale is 0 via `_auto_ui_scale()` (line 215), sets `get_window().content_scale_factor`, resizes the window to compensate, and re-centres on screen. `_on_config_changed()` (line 762) listens for `AppState.config_changed` and re-calls `_apply_ui_scale()` when `section == "accessibility" and key == "ui_scale"`.

### Themed Components (49 files)

Each component calls `add_to_group("themed")` in `_ready()` and implements `func _apply_theme() -> void` to refresh its inline color overrides from `ThemeManager.get_color()`. Components fall into two categories:

**Panel background updaters** — modify their `theme_override_styles/panel` StyleBoxFlat `bg_color` at runtime so `.tscn` hardcoded colors are overridden by the active palette. Each reads its existing stylebox override and mutates `bg_color` in place, preserving content margins and corner radii:
- `message_view.gd` — `content_bg` (main message area)
- `channel_list.gd`, `dm_list.gd`, `thread_panel.gd`, `voice_text_panel.gd`, `message_action_bar.gd` — `panel_bg`
- `guild_bar.gd`, `user_bar.gd` — `input_bg`
- `voice_bar.gd`, `video_grid.gd` — `nav_bg`
- `composer.gd` — `button_hover`
- `emoji_picker.gd`, `embed.gd`, `soundboard_panel.gd` — `modal_bg`
- `modal_base.gd` — `modal_bg` (for scene-based modals via `_bind_modal_nodes` and code-built modals via `_setup_modal`)

**Color/shader updaters** — update font colors, icon tints, and shader uniforms:
- `cozy_message.gd` (line 37) — updates timestamp and reply preview muted color
- `message_content.gd` (line 33) — re-renders text with current text_muted and link colors
- `settings_base.gd` — rebuilds all StyleBoxFlat backgrounds for action/secondary/danger buttons
- `welcome_screen.gd` (line 311) — calls `_apply_shader_accent()` to update welcome_bg shader colors
- `main_window.gd` (line 789) — updates drawer backdrop overlay, topic bar, update indicator colors
- `avatar.gd` (line 35) — updates ring_color shader uniform on both base and texture rect materials
- `video_tile.gd` (line 19) — applies metadata-based font colors to child nodes

### Theme String Detection (`message_content.gd`)

`_detect_theme_string()` (line 183) runs during `setup()` on every message. It:
1. Checks if the raw text is 20–2000 characters and matches a base64 pattern
2. Strips whitespace, decodes via `Marshalls.base64_to_utf8()`
3. Parses as JSON, verifies it contains known palette keys (`accent` or `text_body`)
4. If valid, adds an "Apply Theme" button below the message text
5. Clicking the button calls `ThemeManager.import_theme_string()` and disables itself

### Shader Color Parameterization

**`welcome_bg.gdshader`** — Has three uniforms: `accent_color` (line 6, vec4), `bg_navy` (line 7, vec3), `bg_purple` (line 8, vec3). `welcome_screen.gd._apply_shader_accent()` (line 296) sets `accent_color` from `ThemeManager.get_color("accent")`, `bg_navy` from `input_bg`, and `bg_purple` from `nav_bg`. The gradient colors now adapt to the active theme.

**`avatar_circle.gdshader`** — Has a `uniform vec4 ring_color` (line 5) defaulting to green. `avatar.gd._apply_theme()` (line 35) sets this to `ThemeManager.get_color("status_online")` on both the base material and the texture rect material, updating live on theme change.

**`skeleton_shimmer.gdshader`** — Pure white shimmer effect, no color uniforms to theme.

### Reduce Motion Reactivity

4 components connect to `AppState.reduce_motion_changed` for live response:
- `loading_skeleton.gd` (line 56) — stops/resumes shimmer processing immediately
- `welcome_screen.gd` (line 80) — stops/resumes background shader animation
- `voice_bar.gd` (line 42) — stops pulse animation on status dot
- `add_server_button.gd` (line 16) — stops glow pulse animation

22+ other components poll `Config.get_reduced_motion()` at animation time (before starting tweens, on hover, etc.). This is by design — one-shot animations (avatar radius tweens, reaction pill bounces, message action bar fades) only need a guard before starting. Only looping/long-running animations need reactive signal listeners to stop mid-animation, and those 4 cases are already covered.

### Status Colors (`client_models.gd`)

`status_color()` (line 67) maps `UserStatus` enum values to palette keys:
- `ONLINE` → `ThemeManager.get_color("status_online")`
- `IDLE` → `ThemeManager.get_color("status_idle")`
- `DND` → `ThemeManager.get_color("status_dnd")`
- `OFFLINE` → `ThemeManager.get_color("status_offline")`

### Folder Colors

Space folders support per-folder color customization stored in Config:
- `Config.get_folder_color(name) / set_folder_color(name, color)` (lines 380–386)
- `Config.get_space_folder_color(id) / set_space_folder_color(id, color)` (lines 373–378)

The color picker is surfaced in the space folder context menu. `guild_folder.gd:setup()` (line 56) defaults to `ThemeManager.get_color("secondary_button")` when no explicit folder color is provided.

### Config Persistence

Theme settings are stored in the encrypted per-profile config:
- `get_theme_preset() / set_theme_preset()` (lines 543–549) — stores "dark", "light", "nord", "monokai", "solarized", or "custom"
- `get_custom_palette() / set_custom_palette()` (lines 551–558) — stores a Dictionary of hex color strings keyed by palette name

## Implementation Status

- [x] Global theme resource (`discord_dark.tres`) applied project-wide and patched at runtime
- [x] ThemeManager centralized palette with 37 semantic color keys
- [x] Five built-in theme presets (Dark, Light, Nord, Monokai, Solarized)
- [x] Custom color palette with 8 editable keys and color pickers
- [x] Theme preview swatches showing current palette colors
- [x] Base64 theme export (JSON → base64 → clipboard)
- [x] Base64 theme import (clipboard/paste → base64 → JSON → apply)
- [x] Theme string detection in chat messages with "Apply Theme" button
- [x] Live theme switching via `AppState.theme_changed` + "themed" group (49 components)
- [x] All panel backgrounds (channel list, message view, guild bar, voice bar, composer, etc.) update via `_apply_theme()` — no hardcoded colors survive a theme change
- [x] Modal overlays and panel backgrounds update on theme change via `modal_base.gd`
- [x] All font colors in .tscn files update on theme change — 90 metadata-annotated labels across 42 files resolved by `ThemeManager.apply_font_colors()`, ~45 text_body labels inherit from the project theme directly
- [x] GDScript Color() literals use ThemeManager — video_tile speaking border (`status_online`), guild_folder default color (`secondary_button`); member_item flash tween uses additive white intentionally
- [x] Avatar ring_color updates live on theme change via `_apply_theme()` callback
- [x] Welcome background shader fully themeable — `bg_navy`/`bg_purple` uniforms driven by `input_bg`/`nav_bg`
- [x] Live UI scale without restart via `config_changed` listener
- [x] Reduce motion toggle (26+ consuming components; 4 reactive for looping animations, 22+ polling for one-shot animations — by design)
- [x] Emoji skin tone selector
- [x] Per-folder color customization
- [x] Shader color parameterization (welcome_bg accent/navy/purple, avatar ring_color)
- [x] Status colors in palette (online, idle, dnd, offline)
- [x] Settings panel colors via ThemeManager (settings_base.gd)
