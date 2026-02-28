# Theming

## Overview

daccord uses a single global Godot `Theme` resource (`discord_dark.tres`) applied at the project level. The Appearance settings page offers reduce-motion, UI scale, and emoji skin tone controls, but there is no support for custom color schemes, light mode, or theme sharing. 202 hardcoded `Color()` values are scattered across 60 GDScript files as inline overrides, making a future theme system non-trivial.

## User Steps

### Current: Adjusting Appearance Settings

1. Open App Settings (gear icon in user bar, or user bar menu > "App Settings")
2. Click "Appearance" in the left nav (page index 3)
3. Toggle "Reduce motion" to disable animations across 17 components
4. Drag the UI Scale slider (50%–200%) — takes effect on next launch
5. Choose an emoji skin tone from the dropdown

### Future: Sharing a Custom Theme (not yet implemented)

1. User opens Appearance settings
2. User adjusts color values (accent, background, text, muted, error, etc.)
3. User clicks "Export Theme" — client serializes the color palette to JSON, base64-encodes it, and copies the string to clipboard
4. User shares the base64 string (e.g. in a chat message or forum post)
5. Recipient copies the string, opens Appearance settings, clicks "Import Theme"
6. Client decodes the base64 string, validates the JSON, and applies the color overrides

## Signal Flow

```
User changes Appearance setting
    │
    ▼
app_settings.gd ── Config.set_reduced_motion() ──► Config._save()
                    Config._set_ui_scale()              │
                    Config.set_emoji_skin_tone()         ▼
                                                   AppState.config_changed
                                                   .emit(section, key)
                                                         │
                           ┌─────────────────────────────┘
                           ▼
                    (no listeners react to appearance changes at runtime —
                     reduce_motion is polled; ui_scale requires restart)
```

## Key Files

| File | Role |
|------|------|
| `assets/theme/discord_dark.tres` | Global Godot Theme resource — colors, fonts, styleboxes for all widgets |
| `project.godot:55` | Sets `gui/theme/custom` to `discord_dark.tres` |
| `scenes/user/app_settings.gd` | Builds the Appearance page (lines 193–243) |
| `scenes/user/settings_base.gd` | Shared settings panel base — hardcoded panel/nav colors (lines 16, 28, 54, 151, 167) |
| `scripts/autoload/config.gd` | Persists `reduced_motion`, `ui_scale`, `emoji_skin_tone` (lines 485–502) |
| `scripts/autoload/app_state.gd:145` | `config_changed(section, key)` signal declaration |
| `scenes/main/main_window.gd:168` | `_apply_ui_scale()` — reads scale from Config, applies to window |
| `assets/theme/avatar_circle.gdshader` | Avatar shape shader (circle/rounded-square morph, speaking ring) |
| `assets/theme/welcome_bg.gdshader` | Welcome screen animated gradient with bokeh particles |
| `assets/theme/skeleton_shimmer.gdshader` | Loading placeholder shimmer animation |

## Implementation Details

### Global Theme Resource

`discord_dark.tres` is a Godot `Theme` resource loaded at the project level (`project.godot:55`). It defines styles for 12 widget types (Button, CheckBox, Label, LineEdit, etc.) using 13 sub-resources (StyleBoxFlat/Empty). Key color tokens:

| Token | Value | Usage |
|-------|-------|-------|
| Background | `Color(0.212, 0.224, 0.247)` | Button normal bg, tab selected bg |
| Accent (blurple) | `Color(0.345, 0.396, 0.949)` | Tab selected underline border |
| Body text | `Color(0.863, 0.867, 0.871)` | Label, Button, LineEdit, RichTextLabel font |
| Muted text | `Color(0.58, 0.608, 0.643)` | Placeholder text, unselected tab text |
| Input bg | `Color(0.125, 0.133, 0.145)` | LineEdit background, scrollbar grabber |
| Hover | `Color(0.24, 0.25, 0.27)` | Button hover, tab hovered |
| Pressed | `Color(0.2, 0.21, 0.23)` | Button pressed state |

The theme applies automatically to every Control node; no `set_theme()` calls exist in GDScript.

### Inline Color Overrides

180 calls to `add_theme_color_override` / `add_theme_stylebox_override` across 48 files provide per-component styling that is **not** driven by the `.tres` theme. These use a consistent hardcoded palette:

- **Muted**: `Color(0.58, 0.608, 0.643)` — section labels, timestamps, secondary text
- **Blurple**: `Color(0.345, 0.396, 0.949)` — links, mentions, update version labels
- **Error red**: `Color(0.929, 0.259, 0.271)` — error labels, danger buttons
- **Panel dark**: `Color(0.153, 0.161, 0.176)` — nav panel background in settings
- **Settings bg**: `Color(0.188, 0.196, 0.212)` — settings panel ColorRect

A custom theme system would need to replace all of these with lookups from a shared palette.

### Appearance Page (`app_settings.gd`)

`_build_appearance_page()` (line 193) builds three sections:

1. **Reduce Motion** (line 197) — CheckBox bound to `Config.get/set_reduced_motion()`. Toggling emits `AppState.config_changed("accessibility", "reduced_motion")`. Each of the 17 consuming components polls `Config.get_reduced_motion()` before starting animations; none listen to the signal for live updates.

2. **UI Scale** (line 207) — HSlider range 50%–200% in 10% steps. Bound to `Config._set_ui_scale()` (note: underscore prefix — semi-private). The scale is applied once in `main_window.gd:168` during `_ready()` via `get_window().content_scale_factor`. Changing the slider emits `config_changed` but nothing re-applies the scale at runtime — a restart is required.

3. **Emoji Skin Tone** (line 229) — OptionButton with 6 options (Default through Dark). Bound to `Config.get/set_emoji_skin_tone()`. The emoji picker reads this value when rendering emoji.

### UI Scale Application

`_apply_ui_scale()` (line 168 of `main_window.gd`) implements HiDPI awareness:

```
1. Read Config.get_ui_scale() → 0.0 means "auto"
2. If auto: query DisplayServer.screen_get_scale(), clamp to [1.0, 2.0]
3. If scale <= 1.0: do nothing (Godot handles 1x natively)
4. Otherwise: set get_window().content_scale_factor = scale
```

### Shaders

Three `.gdshader` files complement the visual theme:

- **`avatar_circle.gdshader`** — uniforms `radius` (0.5=circle, 0.3=rounded-square), `ring_opacity`, `ring_color`. The avatar component tweens `radius` on hover and `ring_opacity` when a user is speaking.
- **`welcome_bg.gdshader`** — uses blurple `vec3(0.345, 0.396, 0.949)` for a gradient with animated bokeh particles and sparkle dots.
- **`skeleton_shimmer.gdshader`** — `shimmer_offset` uniform drives the loading shimmer; `corner_radius` controls shape.

All three contain hardcoded color values that would need to be parameterized for custom themes.

### Folder Colors

Space folders support per-folder color customization stored in Config:

- `Config.get_folder_color(name) / set_folder_color(name, color)` (lines 351–356)
- `Config.get_space_folder_color(id) / set_space_folder_color(id, color)` (lines 344–349)

These are the only user-customizable colors in the current app. The color picker is surfaced in the space folder context menu.

## Base64 Theme Sharing (Proposed Design)

The theme sharing flow would use base64-encoded JSON to let users copy-paste themes:

### Theme Palette Schema

```json
{
  "v": 1,
  "name": "My Custom Theme",
  "colors": {
    "background":       "#363a3f",
    "background_dark":  "#272a2e",
    "background_input": "#202225",
    "accent":           "#5865f2",
    "text":             "#dcddde",
    "text_muted":       "#949ba4",
    "error":            "#ed4245",
    "success":          "#3ba55c",
    "panel":            "#2f3136",
    "nav":              "#272a2e",
    "hover":            "#3d4043",
    "pressed":          "#333638",
    "separator":        "#40444b",
    "mention_bg":       "#5865f233",
    "link":             "#00aff4"
  }
}
```

### Export Flow

```
1. Serialize palette → JSON string
2. Marshalls.utf8_to_base64(json_string)  → base64 string
3. DisplayServer.clipboard_set(base64_string)
4. Show "Copied to clipboard" toast
```

### Import Flow

```
1. Read clipboard or paste into text field
2. Marshalls.base64_to_utf8(input) → JSON string
3. JSON.parse(json_string) → validate against schema
4. For each key: store in Config under "theme/colors/<key>"
5. Apply overrides: rebuild theme resource or call _apply_theme()
6. Emit AppState.config_changed("theme", "colors")
```

### Sharing Format

A shared theme would look like:

```
eyJ2IjoxLCJuYW1lIjoiTW9ub2thaS
IsImNvbG9ycyI6eyJiYWNrZ3JvdW5k
IjoiIzI3MmEyZSIsImFjY2VudCI6Ii
M1ODY1ZjIiLCJ0ZXh0IjoiI2RjZGRk
ZSJ9fQ==
```

Users would paste this string into the Import dialog, or the client could detect and offer to apply theme strings pasted into chat.

## Implementation Status

- [x] Global theme resource (`discord_dark.tres`) applied project-wide
- [x] Reduce motion toggle (17 consuming components)
- [x] UI Scale slider with HiDPI auto-detection
- [x] Emoji skin tone selector
- [x] Per-folder color customization
- [x] Three complementary shaders (avatar, welcome, skeleton)
- [ ] Custom color palette selection
- [ ] Light / dark mode toggle
- [ ] Theme preview before applying
- [ ] Base64 theme export (JSON → base64 → clipboard)
- [ ] Base64 theme import (clipboard/paste → base64 → JSON → apply)
- [ ] Theme string detection in chat messages
- [ ] Built-in theme presets (Monokai, Solarized, Nord, etc.)
- [ ] Live-apply UI scale without restart
- [ ] Centralized color constants replacing 202 hardcoded Color() values
- [ ] Shader color parameterization (blurple in welcome_bg, ring color in avatar)

## Tasks

### THEME-1: No custom color scheme UI
- **Status:** open
- **Impact:** 4
- **Effort:** 2
- **Tags:** ui
- **Notes:** Appearance page (line 193) only has reduce motion, UI scale, and skin tone — no color pickers or theme selector

### THEME-2: 202 hardcoded Color() across 60 files
- **Status:** open
- **Impact:** 4
- **Effort:** 2
- **Tags:** ui
- **Notes:** All inline overrides use literal Color values; a theme system needs a shared palette lookup (e.g. `ThemeColors.ACCENT`) that every component reads

### THEME-3: No base64 theme export/import
- **Status:** open
- **Impact:** 4
- **Effort:** 2
- **Tags:** ci, emoji, ui
- **Notes:** `Marshalls.raw_to_base64()` is only used for avatar/emoji upload; no theme serialization exists

### THEME-4: UI scale requires restart
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** api, config, ui
- **Notes:** `_apply_ui_scale()` (line 168) runs once in `_ready()`; `config_changed` is emitted but nothing re-applies `content_scale_factor` at runtime

### THEME-5: Shader colors are hardcoded
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** ci
- **Notes:** `welcome_bg.gdshader` has blurple `vec3(0.345, 0.396, 0.949)` baked in; `avatar_circle.gdshader` defaults ring color to green — would need uniform overrides from GDScript

### THEME-6: Settings panel colors bypass theme
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** config, ui
- **Notes:** `settings_base.gd` sets panel bg `Color(0.188, 0.196, 0.212)` and nav bg `Color(0.153, 0.161, 0.176)` as literals (lines 16, 28) rather than reading from the theme resource

### THEME-7: No light mode
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** ui
- **Notes:** Only `discord_dark.tres` exists; a light theme would need a second `.tres` plus all inline overrides swapped

### THEME-8: reduce_motion is polled, not reactive
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** config
- **Notes:** Components check `Config.get_reduced_motion()` at animation time; toggling the checkbox doesn't retroactively stop in-progress animations
