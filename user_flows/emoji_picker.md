# Emoji Picker

Last touched: 2026-03-11
Priority: 12
Depends on: Messaging

## Overview

The emoji picker allows users to browse and insert emoji into their messages as `:name:` shortcodes. It provides a categorized catalog of ~340 Twemoji SVGs across 9 categories (including Flags), a search bar for filtering by name, and category tabs for quick navigation. Selected emoji are inserted as `:name:` shortcodes at the cursor position in the composer, and rendered inline as images by `markdown_to_bbcode()`. Emoji are also used in message reactions via a shared `EmojiData` catalog. The picker supports custom server emoji loaded from the CDN, displayed in a dedicated "Custom" category tab.

The catalog is a curated subset of the full Unicode emoji set (~3600+ emoji). Approximately 340 built-in emoji are included across 9 categories, chosen to cover the most commonly used emoji. Textures are lazy-loaded on first access (not preloaded at startup) to manage memory efficiently.

The picker supports skin tone preferences for 27 hand/gesture emoji in the People category. Users set their preferred skin tone (Default, Light, Medium-Light, Medium, Medium-Dark, Dark) in Settings > Notifications > EMOJI SKIN TONE. The preference is applied globally: in the picker grid, in rendered messages, and on reaction pills. Skin tone variant textures (135 SVGs) are lazily loaded on first use to avoid startup overhead.

Custom emoji are stored on the server as image files (uploaded as base64 data URIs via `POST /spaces/{id}/emojis`). The server assigns each emoji a snowflake ID, stores the image to disk, and serves it via CDN at `/emojis/{emoji_id}.{png|gif}`. Emoji CRUD operations broadcast gateway events (`emoji.create`, `emoji.update`, `emoji.delete`) to all members of the space.

## User Steps

### Insert Emoji via Picker

1. User clicks the smiley-face emoji button in the composer toolbar
2. Emoji picker panel appears above the button (352x360px, dark background with rounded corners)
3. Category bar at the top shows tabs; if recently used emoji exist, "Recently Used" (watch icon) is selected by default; if a space is selected, a "Custom" tab (star icon) appears; followed by 9 built-in category tabs (including Flags)
4. User browses the 8x-column grid of emoji for the current category. Hand/gesture emoji display with the user's preferred skin tone
5. Optionally, user types in the search bar to filter emoji by name across all categories (including cached custom emoji)
6. User clicks an emoji cell
7. The emoji's `:name:` shortcode is inserted at the caret position in the composer TextEdit (both built-in and custom emoji use the same shortcode format)
8. Picker closes automatically after selection
9. Composer TextEdit regains focus

### Custom Emoji Tab

1. User clicks the "Custom" tab (star icon, shown when a space is selected)
2. Picker fetches the current space's custom emoji via `Client.admin.get_emojis(space_id)`
3. Emoji textures are loaded from the CDN using HTTPRequest and cached in `_custom_emoji_cache`
4. Custom emoji appear in the grid with their loaded textures
5. Clicking a custom emoji inserts `:name:` into the composer, or adds it as a reaction

### Change Skin Tone Preference

1. User opens Settings (gear icon in user bar)
2. User navigates to the "Notifications" page
3. Under the "EMOJI SKIN TONE" section, user selects a skin tone from the dropdown: Default, Light, Medium-Light, Medium, Medium-Dark, or Dark
4. The preference is saved immediately to the profile config
5. The next time the emoji picker opens, hand/gesture emoji (27 in the People category) display with the selected skin tone
6. Messages containing skin-tone-eligible emoji shortcodes render with the selected tone
7. Reaction pills for skin-tone-eligible emoji also reflect the preference

### Browse Flags Category

1. User opens the emoji picker
2. User clicks the Flags tab (US flag icon, last tab in the category bar)
3. 50 country flag emoji are displayed in the grid
4. User clicks a flag to insert its `:flag_xx:` shortcode
5. The flag renders as an inline image in the message

### Dismiss Picker Without Selecting

1. User clicks the emoji button again (toggles off), or
2. User presses Escape, or
3. User clicks anywhere outside the picker panel

### Emoji in Reactions

1. Message reactions display emoji textures from `EmojiData.get_texture()` with skin tone support
2. `reaction_pill.gd` looks up emoji by name key to set its texture, falling back to `ClientModels.custom_emoji_textures` for custom emoji
3. Toggling a reaction calls `Client.add_reaction()` or `Client.remove_reaction()` (optimistic local update with rollback on failure via `reaction_failed` signal)
4. Gateway events (`reaction.add`, `reaction.remove`, `reaction.clear`, `reaction.clear_emoji`) update the message cache and trigger re-render

### Add Reaction via Context Menu

1. User right-clicks a message or long-presses on touch
2. Context menu shows "Reply", "Edit", "Delete", "Add Reaction", "Remove All Reactions", and "Start Thread"
3. User clicks "Add Reaction"
4. `reaction_picker.gd` wraps an emoji picker instance, positioned near the context menu
5. User selects an emoji (built-in or custom)
6. `Client.add_reaction()` is called with the channel ID, message ID, and emoji name
7. Picker closes and frees itself automatically

### Add Reaction via Action Bar

1. User hovers over a message; the action bar appears with a reaction button
2. User clicks the reaction button (smiley icon)
3. `message_action_bar.gd` opens a reaction picker (line 96)
4. User selects an emoji
5. `Client.add_reaction()` is called
6. Picker closes automatically

## Signal Flow

```
User clicks EmojiButton (composer.tscn)
    -> composer._on_emoji_button() (line 248)
        -> Instantiates EmojiPickerScene (lazy, first click only)
        -> Adds to scene tree root
        -> emoji_picker.emoji_picked.connect(composer._on_emoji_picked)
        -> _position_picker() positions above button, right-aligned
        -> emoji_picker.visible = true

User clicks emoji cell in grid
    -> emoji_button_cell._on_pressed() (line 16)
        -> emoji_selected signal(emoji_name)
    -> emoji_picker._on_emoji_selected(emoji_name) (line 261)
        -> Config.add_recent_emoji(emoji_name)
        -> emoji_picked signal(emoji_name)
    -> composer._on_emoji_picked(emoji_name) (line 273)
        -> For built-in: EmojiData.get_by_name(emoji_name) validates name exists
           -> Inserts ":emoji_name:" shortcode at caret position (line 286)
        -> For custom (prefix "custom:"): Extracts name, inserts ":name:" (line 279)
        -> text_input.grab_focus()
        -> emoji_picker.visible = false

User clicks custom emoji cell
    -> Lambda closure emits emoji_picked("custom:name:id") (line 209)
    -> composer._on_emoji_picked() detects "custom:" prefix
        -> Inserts ":name:" shortcode at caret position

Message rendering (shortcode -> inline image):
    -> message_content.setup() calls ClientModels.markdown_to_bbcode(raw_text) (line 56)
        -> Delegates to ClientMarkdown.markdown_to_bbcode() (client_markdown.gd line 45)
        -> Regex matches :emoji_name: patterns (line 41, compiled as ":([a-z0-9_]+):")
        -> Matches processed in reverse order (line 89)
        -> Built-in: EmojiData.get_by_name() lookup (line 92), replaced with
           [img=20x20]res://assets/theme/emoji/CODEPOINT.svg[/img] (line 95)
        -> Custom: looked up in ClientModels.custom_emoji_paths (line 97)

Reaction flow (context menu):
    -> message_view_actions.on_context_menu_id_pressed(3) (line 146)
        -> open_reaction_picker(msg_data) (line 160)
        -> Creates ReactionPickerScene, calls open() (line 168)
    -> reaction_picker._on_emoji_picked(emoji_name) (line 26)
        -> Strips "custom:" prefix if present (line 30)
        -> Client.add_reaction(channel_id, message_id, reaction_key) (line 31)
        -> Picker frees itself (line 41)

Reaction flow (action bar):
    -> message_action_bar._on_react_pressed() (line 81)
        -> _open_reaction_picker() (line 96)
        -> Creates ReactionPickerScene, calls open() (line 104)
    -> reaction_picker._on_emoji_picked() -> same flow as above

Reaction flow (pill toggle):
    -> reaction_pill._on_toggled(toggled_on) (line 46)
        -> Optimistic local count update (lines 50-54)
        -> Bounce animation (lines 57-64)
        -> Client.add_reaction() or Client.remove_reaction() (lines 68-71)

Reaction failure rollback:
    -> AppState.reaction_failed signal
        -> reaction_pill._on_reaction_failed() (line 73)
            -> Reverts optimistic count update (lines 77-85)

Gateway reaction events:
    -> AccordClient.reaction_add/remove/clear/clear_emoji signals
        -> client_gateway_reactions.on_reaction_add/remove/clear/clear_emoji()
            -> Updates message cache reactions array
            -> AppState.messages_updated.emit(channel_id)
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/composer/composer.gd` | Hosts emoji button, instantiates picker, handles `emoji_picked` signal, inserts `:name:` shortcode into TextEdit |
| `scenes/messages/composer/composer.tscn` | Composer layout with EmojiButton (smile.svg icon) |
| `scenes/messages/composer/emoji_picker.gd` | Picker panel: category bar (Recently Used, Custom, 9 built-in), search, grid population, custom emoji CDN loading, dismiss logic |
| `scenes/messages/composer/emoji_picker.tscn` | Picker layout: 352x360px PanelContainer, CategoryBar, SearchInput, 8-column EmojiGrid in ScrollContainer |
| `scenes/messages/composer/emoji_button_cell.gd` | Individual emoji button: displays texture with skin tone, emits `emoji_selected` on click |
| `scenes/messages/composer/emoji_button_cell.tscn` | Cell layout: 36x36px flat Button with hover highlight, centered icon |
| `scripts/emoji_data.gd` | Static catalog: `Category` enum (9 categories), `catalog` (~340 entries), lazy-loaded texture cache, skin tone support (`get_texture()`, `get_codepoint_with_tone()`), multi-codepoint `codepoint_to_char()` |
| `scripts/autoload/client_markdown.gd` | `markdown_to_bbcode()` renders `:name:` shortcodes as inline `[img]` BBCode tags (extracted from `client_models.gd`) |
| `scripts/autoload/client_models.gd` | Holds `custom_emoji_paths` and `custom_emoji_textures` static dictionaries; `emoji_to_dict()` converts `AccordEmoji` models |
| `scenes/messages/message_content.gd` | Calls `markdown_to_bbcode()` for emoji rendering, passes `channel_id` and `message_id` to reaction bar |
| `scenes/messages/reaction_pill.gd` | Reaction display: looks up emoji textures with skin tone, optimistic toggle with rollback, calls `Client.add_reaction()`/`Client.remove_reaction()` |
| `scenes/messages/reaction_bar.gd` | Creates reaction pills, passes `channel_id` and `message_id` through to pills |
| `scenes/messages/reaction_picker.gd` | Wraps EmojiPickerScene for reaction context; calls `Client.add_reaction()` on selection, then frees itself |
| `scenes/messages/message_view_actions.gd` | Context menu with "Add Reaction" (ID 3) and "Remove All Reactions" (ID 4), opens reaction picker |
| `scenes/messages/message_action_bar.gd` | Hover action bar with reaction button, opens reaction picker |
| `scripts/autoload/client.gd` | `add_reaction()` (line 516), `remove_reaction()` (line 521), `remove_all_reactions()` (line 526) mutation methods |
| `scripts/autoload/client_gateway_reactions.gd` | Gateway handlers: `on_reaction_add` (line 19), `on_reaction_remove` (line 53), `on_reaction_clear` (line 80), `on_reaction_clear_emoji` (line 92) |
| `scripts/autoload/client_emoji.gd` | Custom emoji downloading and disk caching for Client |
| `scripts/autoload/app_state.gd` | `emojis_updated` (line 44), `reactions_updated` (line 50), `reaction_failed` signals |
| `scripts/autoload/config.gd` | `get_emoji_skin_tone()` (line 497) / `set_emoji_skin_tone()` (line 500), `get_recent_emoji()` (line 494) / `add_recent_emoji()` (line 505) |
| `addons/accordkit/models/emoji.gd` | `AccordEmoji` model with `image_url` field parsed from server responses |
| `scenes/user/app_settings.gd` | Skin tone dropdown in Notifications page under "EMOJI SKIN TONE" section (line 542) |
| `scripts/download_emoji.sh` | One-time script to download Twemoji SVGs for base emoji, skin tone variants, and flags |
| `assets/theme/emoji/*.svg` | ~493 Twemoji SVG files: ~308 base + 135 skin tone variants + 50 flags |

## Implementation Details

### EmojiData Catalog (emoji_data.gd)

- `Category` enum: `SMILEYS`, `PEOPLE`, `NATURE`, `FOOD`, `ACTIVITIES`, `TRAVEL`, `OBJECTS`, `SYMBOLS`, `FLAGS`
- `category_names`: Human-readable names for tooltip text (e.g., "Smileys & Emotion", "People & Body", "Flags")
- `category_icons`: Maps each category to its representative codepoint (used as the tab icon). FLAGS uses `1f1fa-1f1f8` (US flag)
- `catalog`: Dictionary mapping each `Category` to an array of `{name, codepoint}` entries. ~56 smileys, ~28 people, ~40 nature, ~40 food, ~36 activities, ~35 travel, ~39 objects, ~34 symbols, ~50 flags (~340 total). This is a curated subset of the ~3600+ Unicode emoji set
- `_texture_cache` (static var): Lazily-loaded cache of base emoji textures (keyed by emoji name). Textures are loaded on first access via `get_texture()` instead of preloading all at startup
- `skin_tone_modifiers`: Array of 6 entries (index 0 = empty/default, 1-5 = skin tone hex codepoints `1f3fb`..`1f3ff`)
- `skin_tone_emoji`: Array of 27 emoji names in the People category that support skin tone variants (all except `handshake`)
- `_skin_tone_textures` (static var): Lazily-loaded cache of skin tone variant textures (keyed by full codepoint like `"1f44d-1f3fb"`)
- `_name_lookup` (static var): Lazily-built dictionary mapping emoji name to `{name, codepoint}` entry for O(1) lookup
- `get_texture(emoji_name, tone)`: Returns the texture for the emoji with optional skin tone. Lazy-loads from `res://assets/theme/emoji/` on first access and caches in `_texture_cache` or `_skin_tone_textures`. Returns `null` if the SVG doesn't exist
- `get_all_for_category(category)`: Returns the entry array for a category
- `get_by_name(emoji_name)`: Dictionary lookup via `_name_lookup` (lazy-initialized on first call)
- `supports_skin_tone(emoji_name)`: Returns true if the emoji supports skin tone variants
- `get_codepoint_with_tone(emoji_name, tone)`: Returns the codepoint with skin tone modifier appended (e.g., `"1f44d-1f3fb"` for thumbs_up + light tone). Returns base codepoint if tone is 0 or emoji doesn't support tones
- `get_texture(emoji_name, tone)`: Returns the texture for the emoji with the given skin tone. All textures (base and skin tone) are lazily loaded on first access and cached. Falls back to base texture if the variant file doesn't exist
- `codepoint_to_char(hex_codepoint)`: Converts hex codepoint string to Unicode character(s). Handles multi-codepoint sequences by splitting on `-` (e.g., `"1f1fa-1f1f8"` produces two regional indicator characters for the US flag)

### Emoji Picker Panel (emoji_picker.gd)

- Extends `PanelContainer`, starts hidden (`visible = false` in .tscn)
- **Recently Used tab**: Always shown as first tab (watch icon). On open, if `Config.get_recent_emoji()` has entries, defaults to showing recently used. `_load_recent_category()` (line 135) iterates recent names, looks up built-in via `EmojiData.get_by_name()`, falls back to `ClientModels.custom_emoji_textures` for custom emoji
- **Custom tab**: If `AppState.current_space_id` is non-empty (line 52), a "Custom" tab (star icon) is added. Clicking it loads custom emoji from the server via `Client.admin.get_emojis()` (line 128) and renders them with CDN-loaded textures. Textures are cached in `_custom_emoji_cache` (line 13) to avoid re-fetching
- **Category bar**: `_build_category_bar()` (line 40) creates a flat `Button` (36x36px) per category with the category's representative emoji as icon and category name as tooltip. Active category highlighted via `ThemeManager.get_color("icon_active")`, inactive dimmed to `ThemeManager.get_color("text_muted")` (line 83)
- **Search**: `_on_search_changed(query)` (line 224) clears grid, then searches both built-in emoji and cached custom emoji by name. Empty query reloads the current category/tab
- **Grid population**: `_load_category(cat)` (line 117) clears grid, then calls `_add_emoji_cell()` for each entry
- **Custom emoji cells**: `_add_custom_emoji_cell(emoji)` (line 155) creates a cell, loads the texture from CDN via HTTPRequest (with PNG loading), and emits `emoji_picked` with `custom:name:id` format on click (line 209)
- **Gateway sync**: `_on_emojis_updated(space_id)` (line 214) invalidates cache and refreshes if viewing custom tab
- **Dismiss**: `_input(event)` (line 269) handles Escape key and clicks outside the picker's global rect, setting `visible = false`
- **Signal**: `emoji_picked(emoji_name: String)` (line 3) emitted when a cell is clicked. For custom emoji, the format is `custom:name:id`

### Emoji Button Cell (emoji_button_cell.gd)

- Extends `Button` (36x36px, flat, centered icon, expand_icon enabled)
- `setup(data)`: Stores `data.name` as `_emoji_name`, sets `icon` via `EmojiData.get_texture()` with the user's skin tone preference (line 10), sets tooltip to name with underscores replaced by spaces
- `_on_pressed()`: Emits `emoji_selected(_emoji_name)` (line 17)
- Hover style: light gray background with 4px corner radius (defined in .tscn)

### Composer Integration (composer.gd)

- `EmojiPickerScene` preloaded (line 3)
- **Lazy instantiation**: `_on_emoji_button()` (line 248) toggles visibility if picker exists; otherwise instantiates, adds to scene tree root, and connects `emoji_picked` signal (line 255)
- **Positioning**: `_position_picker()` (line 259) places the picker above the emoji button, right-aligned. Clamped to viewport bounds with 4px margin (lines 269-270)
- **Insertion**: `_on_emoji_picked(emoji_name)` (line 273) inserts `:name:` shortcodes for both built-in and custom emoji:
  - Custom emoji (`custom:name:id` prefix): extracts name from parts, inserts `:name:` (lines 275-281)
  - Built-in emoji: validates name via `EmojiData.get_by_name()`, inserts `:emoji_name:` (lines 283-286)
  - Text is spliced at the current caret position (lines 287-292)
- **Cleanup**: `_exit_tree()` (line 401) calls `queue_free()` on the picker instance if it exists

### Emoji Rendering in Messages (client_markdown.gd)

- `markdown_to_bbcode()` (line 45) converts `:emoji_name:` shortcodes to inline images
- Regex pattern `:([a-z0-9_]+):` matches shortcodes (line 41)
- Matches are processed in reverse order to maintain string indices (line 89)
- Each match is looked up via `EmojiData.get_by_name()` (line 92); if found, skin tone is applied via `get_codepoint_with_tone()` (line 94), replaced with `[img=20x20]res://assets/theme/emoji/CODEPOINT.svg[/img]` (line 95)
- Custom emoji shortcodes (`:custom_name:`) are resolved via `ClientModels.custom_emoji_paths` (line 97) — if the name is found in the custom emoji cache, it renders as `[img=20x20]{cached_path}[/img]` with path sanitization (line 100-105)

### Reactions

- **Reaction picker**: `reaction_picker.gd` wraps an `EmojiPickerScene` instance. `open()` (line 12) positions the picker and connects `emoji_picked`. On selection (line 26), strips `custom:` prefix and calls `Client.add_reaction()`. Auto-frees via `_close()` (line 39)
- **Client methods**: `Client.add_reaction(cid, mid, emoji)` (line 516) delegates to mutations, `Client.remove_reaction()` (line 521) same pattern, `Client.remove_all_reactions()` (line 526)
- **Reaction pill**: `reaction_pill.gd` receives `channel_id` and `message_id` via `setup()` (line 26). On toggle (line 46), performs optimistic local count update (lines 50-54) with bounce animation (lines 57-64), then calls `Client.add_reaction()` or `Client.remove_reaction()` (lines 68-71). On `reaction_failed` signal (line 73), reverts the optimistic update
- **Reaction bar**: `reaction_bar.gd` accepts `channel_id` and `message_id` in `setup()` (line 5) and forwards them to each pill (lines 17-19)
- **Message content**: `message_content.gd` passes `channel_id` and `message_id` to `reaction_bar.setup()` (line 154)
- **Context menu**: `message_view_actions.gd` has "Add Reaction" (ID 3, line 26) and "Remove All Reactions" (ID 4, line 27). Add Reaction opens a reaction picker (line 160). Remove All calls `Client.remove_all_reactions()` (line 153)
- **Action bar**: `message_action_bar.gd` has a react button (line 81) that opens a reaction picker (line 96)
- **Gateway handlers**: `client_gateway_reactions.gd` handles `on_reaction_add` (line 19), `on_reaction_remove` (line 53), `on_reaction_clear` (line 80), and `on_reaction_clear_emoji` (line 92) by updating the message cache and emitting `AppState.messages_updated`

### Visual Style

- Picker background: themed via `ThemeManager`, 8px corner radius, 8px padding
- Search input: themed background, 4px corner radius
- Grid: 8 columns, 2px horizontal and vertical separation
- Cell hover: light gray background with 4px corner radius
- Reaction pill active state: accent color at 0.3 alpha background with 1px accent border, 8px corner radius (line 100)
- Reaction pill inactive state: modal background with dim border (line 113)
- Reaction pill bounce animation on toggle (0.15s, ease-out back transition, line 63)

## Implementation Status

- [x] Emoji button in composer toolbar (smile.svg icon)
- [x] Emoji picker panel with dark theme styling
- [x] 9 category tabs with icon buttons and active highlighting (including Flags)
- [x] ~340 Twemoji SVGs across 9 categories + 135 skin tone variants (lazy-loaded)
- [x] Search-by-name filtering across all categories
- [x] Shortcode insertion at caret position (`:name:` format)
- [x] Shortcode rendering as inline images via `markdown_to_bbcode()`
- [x] Picker auto-closes after selection
- [x] Dismiss via Escape key or click-outside
- [x] Lazy instantiation (picker created on first use)
- [x] Viewport-clamped positioning
- [x] Shared `EmojiData.get_texture()` used by both picker and reaction pills
- [x] Picker cleanup on composer exit
- [x] Reactions call server API (`Client.add_reaction()` / `Client.remove_reaction()`)
- [x] Optimistic local reaction count updates with rollback on failure
- [x] Gateway reaction event handlers (add, remove, clear, clear_emoji)
- [x] "Add Reaction" context menu on messages
- [x] "Remove All Reactions" context menu option (permission-gated)
- [x] Reaction picker as standalone wrapper (`reaction_picker.gd`)
- [x] Action bar reaction button
- [x] Custom server emoji tab in picker (CDN loading with caching)
- [x] `get_by_name()` optimized with dictionary lookup
- [x] `emoji.create` and `emoji.delete` gateway events handled (real-time sync)
- [x] Custom emoji rendered inline in messages via `markdown_to_bbcode()` (cached to `user://emoji_cache/`)
- [x] Custom emoji displayed on reaction pills (fallback to `ClientModels.custom_emoji_textures`)
- [x] Recently used emoji section (persisted in config, shown as first tab with watch icon)
- [x] Reaction cache double-mutation fixed (gateway events are sole source of truth)
- [x] `AccordEmoji` model `image_url` field parsed from server responses (preferred over manual CDN URL construction)
- [x] Skin tone preference (Default + 5 tones) persisted in config, applied to picker, messages, and reaction pills
- [x] Skin tone settings UI in Notifications page (dropdown under "EMOJI SKIN TONE" section)
- [x] All textures lazy-loaded on first access (not preloaded at startup)
- [x] Skin tone variant textures lazily loaded (135 SVGs for 27 hand/gesture emoji)
- [x] Flags category with 50 country flag emoji (multi-codepoint regional indicator pairs)
- [x] Multi-codepoint `codepoint_to_char()` for flags and ZWJ sequences
- [x] Reaction pill bounce animation on toggle
- [x] Reaction failure rollback via `reaction_failed` signal
- [x] Expanded emoji catalog (~340 emoji, up from 190)

## Tasks

### EMOJI-1: `reactions_updated` signal declared but unused
- **Status:** done
- **Impact:** 3
- **Effort:** 3
- **Tags:** emoji, gateway
- **Notes:** Resolved: `AppState.reactions_updated` is now emitted by all four gateway reaction handlers (`on_reaction_add`, `on_reaction_remove`, `on_reaction_clear`, `on_reaction_clear_emoji`) in `client_gateway_reactions.gd` and connected in `message_view.gd` for targeted reaction bar updates.

### EMOJI-2: Upload button not connected
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** ui
- **Notes:** Resolved: `composer.tscn` UploadButton is connected to `_on_upload_button()` for file attachments.

### EMOJI-3: Expand built-in emoji catalog
- **Status:** done
- **Impact:** 4
- **Effort:** 4
- **Tags:** emoji, content
- **Notes:** Expanded from 190 to ~340 emoji across all categories. Added smileys (skull, nerd, clown, monocle, etc.), people (vulcan, middle finger, writing hand, etc.), nature (penguin, shark, butterfly, etc.), food (sushi, ramen, ice cream, etc.), activities (guitar, jigsaw, etc.), travel (bicycle, volcano, tent, etc.), objects (camera, crown, gem, etc.), symbols (sparkles, warning, infinity, etc.), and flags (50 countries, up from 30). Switched from `preload()` TEXTURES const to lazy-loaded `_texture_cache` to manage the increased resource count. Skin tone emoji expanded from 19 to 27. Download script updated to fetch all new SVGs.
