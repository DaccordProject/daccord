# Accessibility

Last touched: 2026-02-19

## Overview

daccord has limited accessibility support. Tooltips are provided on most interactive buttons, keyboard shortcuts exist for core messaging actions (Enter to send, Escape to cancel), and the responsive layout supports touch gestures. However, focus indicators are deliberately suppressed, no screen reader metadata is set, there is no high-contrast or reduced-motion mode, and keyboard-only navigation is not fully supported.

## User Steps

1. User navigates the application using mouse, keyboard, or touch
2. User hovers over buttons to see tooltip descriptions
3. User presses Enter to send messages, Escape to close dialogs/cancel edits
4. User presses Up arrow in an empty composer to edit their last message
5. User swipes from left edge on touch devices to open the sidebar drawer
6. User views avatar initials with auto-contrasted text color

## Signal Flow

```
User hover → Button.tooltip_text → Godot tooltip display
User keyboard → _input()/_gui_input() → KEY_ENTER/KEY_ESCAPE → action
User swipe  → _input() edge detection → AppState.toggle_sidebar_drawer()
Window resize → main_window._on_resized() → AppState.layout_mode_changed
```

## Key Files

| File | Role |
|------|------|
| `theme/discord_dark.tres` | Global theme; defines `no_focus` empty StyleBox, font sizes, colors |
| `scenes/main/main_window.gd` | Responsive layout breakpoints, edge-swipe gesture handling, drawer animations |
| `scenes/main/main_window.tscn` | Tooltip text on header buttons (hamburger, sidebar toggle, search, member list) |
| `scenes/messages/composer/composer.gd` | Enter-to-send, Up-to-edit keyboard handling, focus management |
| `scenes/messages/composer/composer.tscn` | Tooltips on Cancel Reply, Upload, Emoji, and Send buttons |
| `scenes/messages/composer/message_input.gd` | Overrides focus style to `StyleBoxEmpty` |
| `scenes/messages/message_content.gd` | Edit mode keyboard shortcuts (Enter/Escape), keyboard hint label |
| `scenes/messages/message_action_bar.tscn` | Tooltips on Add Reaction, Reply, Edit, Delete buttons |
| `scenes/messages/composer/emoji_picker.gd` | Escape-to-close, emoji cell tooltips with human-readable names |
| `scenes/common/avatar.gd` | Luminance-based text contrast for avatar initials |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Dynamic tooltip set to guild name, muted state indicator |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Tab-to-next-field focus flow (username → password → submit) |
| `scenes/search/search_panel.gd` | Escape-to-close, auto-focus on search input |
| `scenes/sidebar/voice_bar.tscn` | Tooltips on Soundboard and Voice Settings buttons |
| `scenes/sidebar/direct/dm_channel_item.tscn` | Tooltip on Close DM button |
| `scripts/autoload/config.gd` | Sound/notification preferences (could support accessibility prefs) |
| `scripts/autoload/app_state.gd` | `layout_mode_changed` signal, `LayoutMode` enum |

## Implementation Details

### Tooltips

Tooltips are set on interactive buttons across 10 `.tscn` files and assigned dynamically in 3 `.gd` files. Coverage includes:

**Header bar** (`main_window.tscn`, lines 47-77): "Open sidebar", "Toggle channel list", "Search messages", "Toggle member list" -- all buttons use `custom_minimum_size = Vector2(44, 44)` ensuring adequate touch targets.

**Composer** (`composer.tscn`, lines 44-85): "Cancel Reply", "Upload", "Emoji", "Send".

**Message actions** (`message_action_bar.tscn`, lines 39-63): "Add Reaction", "Reply", "Edit", "Delete".

**Voice bar** (`voice_bar.tscn`): "Soundboard", "Voice Settings".

**Guild icons** (`guild_icon.gd`, line 57): Tooltip dynamically set to guild name. Updated to include "(Muted)" suffix when server is muted (line 278).

**Emoji picker** (`emoji_picker.gd`, lines 42-225): Category buttons get category name tooltips. Individual emoji cells show human-readable names with underscores replaced by spaces (line 144).

**Admin dialogs** (various): Settings tooltips explain verification levels, notification defaults, discoverability, role display, mentionability, invite behavior, and NSFW flags.

### Keyboard Navigation

**Composer** (`composer.gd`, lines 55-62):
- `KEY_ENTER` (no Shift): Sends the current message
- `KEY_UP` (empty input): Enters edit mode for the user's last sent message
- Shift+Enter: Inserts newline (handled natively by TextEdit)
- Focus auto-grabbed when reply is initiated (line 71) or attachment added (line 259)

**Message editing** (`message_content.gd`, lines 205-221):
- `KEY_ENTER` (no Shift): Saves the edit
- `KEY_ESCAPE`: Cancels the edit
- Keyboard hint displayed below edit input: "Enter to save · Escape to cancel · Shift+Enter for newline" (line 173) in 11px muted gray

**Emoji picker** (`emoji_picker.gd`, lines 247-252):
- `KEY_ESCAPE`: Closes the picker
- Click outside bounds: Also closes the picker

**Search panel** (`search_panel.gd`, lines 67-74):
- `KEY_ESCAPE`: Closes the search panel
- Search input auto-focused on open (line 79)

**Auth dialog** (`auth_dialog.gd`, lines 33-39):
- Username field auto-focused on open (line 39)
- `text_submitted` on username field moves focus to password field (line 33)
- `text_submitted` on password field triggers submit (line 34)

**All admin dialogs** (13 files): Handle `ui_cancel` (Escape) to close the dialog.

### Focus Management

Focus is managed through `grab_focus()` calls in 6 files:

| Location | Trigger |
|----------|---------|
| `composer.gd:71` | Reply initiated |
| `composer.gd:259` | Attachment added |
| `message_content.gd:179` | Edit mode entered |
| `search_panel.gd:79` | Search panel activated |
| `auth_dialog.gd:39` | Auth dialog opened |
| `guild_folder.gd:194` | Folder rename started |

No `focus_mode` properties are configured in any `.tscn` file. No `focus_neighbor_*` properties are set anywhere. Tab order relies entirely on scene tree order.

### Focus Indicators (Suppressed)

The global theme (`discord_dark.tres`, line 2) defines `no_focus` as a `StyleBoxEmpty`. This is applied to 10 widget types (lines 111-140):

- `Button/styles/focus`
- `CheckBox/styles/focus`
- `CheckButton/styles/focus`
- `LineEdit/styles/focus`
- `MenuButton/styles/focus`
- `OptionButton/styles/focus`
- `RichTextLabel/styles/focus`
- `SpinBox/styles/focus`
- `TabBar/styles/tab_focus`
- `TextEdit/styles/focus`

Additionally, `message_input.gd` (line 9) overrides its own focus style to `StyleBoxEmpty`.

This means keyboard users have **no visual indication** of which element is focused.

### Color Contrast

**Avatar text contrast** (`avatar.gd`, lines 33-34): Uses the ITU-R BT.601 luminance formula (`0.299R + 0.587G + 0.114B`) to choose black or white text against the avatar background color. This ensures readable initials regardless of avatar color.

**Theme colors** (`discord_dark.tres`):
- Main text: `Color(0.863, 0.867, 0.871)` (~#DCDDDE) on dark backgrounds (~#202225 to #2F3136)
- Placeholder text: `Color(0.58, 0.608, 0.643)` (~#949BA4) -- lower contrast for secondary text
- Default font size: 14px (line 107)

### Responsive Layout & Touch

**Layout breakpoints** (`main_window.gd`):
- COMPACT: <500px -- sidebar becomes drawer overlay with hamburger button
- MEDIUM: 500-768px
- FULL: >=768px

**Touch gestures** (`main_window.gd`, lines 80-103):
- Edge swipe from left (within 20px zone): Opens sidebar drawer after 80px threshold
- Drawer backdrop tap: Closes drawer (lines 295-299)
- Both touch and mouse input supported for desktop testing

**Minimum tap target**: All header buttons enforce `custom_minimum_size = Vector2(44, 44)`, meeting the 44x44px WCAG guideline for touch targets.

### Animations

All animations use Tween-based interpolation with no option to disable:

- **Drawer slide** (`main_window.gd`, lines 307-333): 0.2s cubic ease in/out
- **Avatar radius morph** (`avatar.gd`, lines 105-110): 0.15s default, circle ↔ rounded square
- **Guild icon hover** (`guild_icon.gd`, lines 95-106): Avatar radius animation on hover/press
- **Typing indicator**: Sine wave animation
- **Guild pill selection**: Height transition

No `prefers-reduced-motion` detection or animation toggle exists.

### Sound Accessibility

Sound effects are configurable per-event through `Config` (lines 267-283) with a global volume slider. Users can disable individual sounds (message received, sent, mentions, voice events) via the Sound Settings dialog. This benefits users who are sensitive to auditory stimulation.

## Implementation Status

- [x] Tooltips on interactive buttons (header, composer, message actions, voice bar, DM close)
- [x] Dynamic tooltips on guild icons and emoji cells
- [x] Keyboard shortcuts for core messaging (Enter/Escape/Up/Shift+Enter)
- [x] Escape to close dialogs, emoji picker, and search
- [x] Focus auto-grab on reply, edit, search, and auth flows
- [x] Auth dialog tab-between-fields flow
- [x] Avatar text luminance contrast
- [x] 44px minimum touch targets on header buttons
- [x] Responsive layout with touch gesture support
- [x] Edit mode keyboard hint label
- [x] Configurable sound effects with per-event toggles
- [ ] Visible focus indicators for keyboard navigation
- [ ] Focus order / tab navigation through UI regions
- [ ] Screen reader metadata (accessible names/descriptions)
- [ ] High-contrast theme option
- [ ] Reduced motion mode
- [ ] Font size scaling
- [ ] Color blindness accommodations
- [ ] Keyboard shortcut reference panel
- [ ] Voice/video captions or transcription

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Focus indicators suppressed globally | High | `no_focus` StyleBoxEmpty applied to all 10 widget types in `discord_dark.tres` (line 2). Keyboard-only users cannot see which element is focused. Need a visible focus ring style, ideally toggled when keyboard navigation is detected. |
| No focus order defined | High | Zero `focus_mode` or `focus_neighbor_*` properties set in any `.tscn` file. Tab key navigation follows scene tree order which may not match visual layout. Need explicit focus chains for sidebar → channels → messages → composer flow. |
| No screen reader support | High | No `accessible_name` or `accessible_description` properties set on any node. Messages, channels, and guilds lack semantic labels. Godot 4.x has limited screen reader support, but accessible names on key elements would help. |
| No high-contrast theme | Medium | Single dark theme (`discord_dark.tres`) with no alternative. Placeholder text color `#949BA4` on `#2F3136` may not meet WCAG AA 4.5:1 contrast ratio for small text. Need at least a high-contrast dark variant. |
| No reduced motion option | Medium | All animations (drawer 0.2s, avatar morph 0.15s, typing sine wave) always run. No `prefers-reduced-motion` detection or user setting. Add a config toggle that sets tween durations to 0. |
| No font size scaling | Medium | Default font size hardcoded to 14px (`discord_dark.tres`, line 107). Individual overrides (e.g., edit hint at 11px on `message_content.gd:174`) are also fixed. Need a font scale multiplier in Config. |
| Status indicators rely on color alone | Medium | Connection status dots, online/offline presence, and unread indicators use color as the sole differentiator. Color-blind users may not distinguish states. Add icons or patterns alongside color. |
| No keyboard shortcut reference | Low | Keyboard shortcuts (Enter, Escape, Up, Shift+Enter) exist but are only documented in the edit hint label. No discoverable shortcut panel or help dialog. |
| No voice/video captions | Low | Voice channels and video chat have no captioning or transcription support. Would require server-side speech-to-text integration. |
| Missing tooltips on some interactive elements | Low | Channel items, category headers, member list items, and context menu entries lack tooltips. Guild folder collapse/expand has no tooltip. |
