# Emoji Picker

Last touched: 2026-02-21

## Overview

The emoji picker allows users to browse and insert emoji into their messages as `:name:` shortcodes. It provides a categorized catalog of 190 Twemoji SVGs across 9 categories (including Flags), a search bar for filtering by name, and category tabs for quick navigation. Selected emoji are inserted as `:name:` shortcodes at the cursor position in the composer, and rendered inline as images by `markdown_to_bbcode()`. Emoji are also used in message reactions via a shared `EmojiData` catalog. The picker supports custom server emoji loaded from the CDN, displayed in a dedicated "Custom" category tab.

The picker supports skin tone preferences for 19 hand/gesture emoji in the People category. Users set their preferred skin tone (Default, Light, Medium-Light, Medium, Medium-Dark, Dark) in Settings > Notifications > EMOJI. The preference is applied globally: in the picker grid, in rendered messages, and on reaction pills. Skin tone variant textures (95 SVGs) are lazily loaded on first use to avoid startup overhead.

Custom emoji are stored on the server as image files (uploaded as base64 data URIs via `POST /spaces/{id}/emojis`). The server assigns each emoji a snowflake ID, stores the image to disk, and serves it via CDN at `/emojis/{emoji_id}.{png|gif}`. Emoji CRUD operations broadcast gateway events (`emoji.create`, `emoji.update`, `emoji.delete`) to all members of the space.

## User Steps

### Insert Emoji via Picker

1. User clicks the smiley-face emoji button in the composer toolbar
2. Emoji picker panel appears above the button (352x360px, dark background with rounded corners)
3. Category bar at the top shows tabs; if a guild is selected, the first tab is "Custom" (star icon), followed by the 9 built-in category tabs (including Flags). "Smileys & Emotion" is selected by default
4. User browses the 8x-column grid of emoji for the current category (20 per built-in category, 30 for Flags). Hand/gesture emoji display with the user's preferred skin tone
5. Optionally, user types in the search bar to filter emoji by name across all categories (including cached custom emoji)
6. User clicks an emoji cell
7. The emoji's `:name:` shortcode is inserted at the caret position in the composer TextEdit (both built-in and custom emoji use the same shortcode format)
8. Picker closes automatically after selection
9. Composer TextEdit regains focus

### Custom Emoji Tab

1. User clicks the "Custom" tab (star icon, first tab when a guild is selected)
2. Picker fetches the current guild's custom emoji via `Client.get_emojis(guild_id)`
3. Emoji textures are loaded from the CDN using HTTPRequest and cached
4. Custom emoji appear in the grid with their loaded textures
5. Clicking a custom emoji inserts `:name:` into the composer, or adds it as a reaction

### Change Skin Tone Preference

1. User opens Settings (gear icon in user bar)
2. User navigates to the "Notifications" page
3. Under the "EMOJI" section, user selects a skin tone from the dropdown: Default, Light, Medium-Light, Medium, Medium-Dark, or Dark
4. The preference is saved immediately to the profile config
5. The next time the emoji picker opens, hand/gesture emoji (19 in the People category) display with the selected skin tone
6. Messages containing skin-tone-eligible emoji shortcodes render with the selected tone
7. Reaction pills for skin-tone-eligible emoji also reflect the preference

### Browse Flags Category

1. User opens the emoji picker
2. User clicks the Flags tab (US flag icon, last tab in the category bar)
3. 30 country flag emoji are displayed in the grid
4. User clicks a flag to insert its `:flag_xx:` shortcode
5. The flag renders as an inline image in the message

### Dismiss Picker Without Selecting

1. User clicks the emoji button again (toggles off), or
2. User presses Escape, or
3. User clicks anywhere outside the picker panel

### Emoji in Reactions

1. Message reactions display emoji textures from the same `EmojiData.TEXTURES` dictionary
2. `reaction_pill.gd` looks up emoji by name key to set its texture
3. Toggling a reaction calls `Client.add_reaction()` or `Client.remove_reaction()` (optimistic local update, gateway events are source of truth)
4. Gateway events (`reaction.add`, `reaction.remove`, `reaction.clear`, `reaction.clear_emoji`) update the message cache and trigger re-render

### Add Reaction via Context Menu

1. User right-clicks a message (cozy or collapsed) or long-presses on touch
2. Context menu shows "Reply", "Edit", "Delete", and "Add Reaction"
3. User clicks "Add Reaction"
4. Emoji picker opens near the context menu position
5. User selects an emoji (built-in or custom)
6. `Client.add_reaction()` is called with the channel ID, message ID, and emoji name
7. Picker closes automatically

## Signal Flow

```
User clicks EmojiButton (composer.tscn)
    -> composer._on_emoji_button() (line 68)
        -> Instantiates EmojiPickerScene (lazy, first click only)
        -> Adds to scene tree root
        -> emoji_picker.emoji_picked.connect(composer._on_emoji_picked)
        -> _position_picker() positions above button, right-aligned
        -> emoji_picker.visible = true

User clicks emoji cell in grid
    -> emoji_button_cell._on_pressed()
        -> emoji_selected signal(emoji_name)
    -> emoji_picker._on_emoji_selected(emoji_name)
        -> emoji_picked signal(emoji_name)
    -> composer._on_emoji_picked(emoji_name) (line 93)
        -> For built-in: EmojiData.get_by_name(emoji_name) validates name exists
           -> Inserts ":emoji_name:" shortcode at caret position (line 106)
        -> For custom (prefix "custom:"): Extracts name, inserts ":name:" (line 99)
        -> text_input.grab_focus()
        -> emoji_picker.visible = false

User clicks custom emoji cell
    -> Lambda closure emits emoji_picked("custom:name:id")
    -> composer._on_emoji_picked() detects "custom:" prefix
        -> Inserts ":name:" shortcode at caret position

Message rendering (shortcode -> inline image):
    -> message_content.setup() calls ClientModels.markdown_to_bbcode(raw_text) (line 17)
        -> Regex matches :emoji_name: patterns (client_models.gd line 372)
        -> Replaces with [img=20x20]res://assets/theme/emoji/CODEPOINT.svg[/img] (line 380)

Reaction flow (context menu):
    -> cozy_message/collapsed_message._on_context_menu_id_pressed(3) (line 86/81)
        -> _open_reaction_picker() instantiates EmojiPickerScene (line 97/92)
        -> emoji_picked.connect(_on_reaction_emoji_picked)
    -> _on_reaction_emoji_picked(emoji_name) (line 112/107)
        -> For custom: strips "custom:" prefix (line 119/114)
        -> Client.add_reaction(channel_id, message_id, reaction_key) (line 120/115)
        -> Picker freed (line 121-123/116-118)

Reaction flow (pill toggle):
    -> reaction_pill._on_toggled(toggled_on) (line 29)
        -> Optimistic local count update (lines 31-35)
        -> Client.add_reaction() or Client.remove_reaction() (lines 39-42)

Gateway reaction events:
    -> AccordClient.reaction_add/remove/clear/clear_emoji signals
        -> client_gateway.on_reaction_add/remove/clear/clear_emoji()
            -> Updates message cache reactions array
            -> AppState.messages_updated.emit(channel_id)
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/composer/composer.gd` | Hosts emoji button, instantiates picker, handles `emoji_picked` signal, inserts `:name:` shortcode into TextEdit |
| `scenes/messages/composer/composer.tscn` | Composer layout with EmojiButton (smile.svg icon, 44x44px) |
| `scenes/messages/composer/emoji_picker.gd` | Picker panel: category bar (with Custom tab), search, grid population, custom emoji CDN loading, dismiss logic |
| `scenes/messages/composer/emoji_picker.tscn` | Picker layout: 352x360px PanelContainer, CategoryBar, SearchInput, 8-column EmojiGrid in ScrollContainer |
| `scenes/messages/composer/emoji_button_cell.gd` | Individual emoji button: displays texture, emits `emoji_selected` on click |
| `scenes/messages/composer/emoji_button_cell.tscn` | Cell layout: 36x36px flat Button with hover highlight, centered icon |
| `scripts/emoji_data.gd` | Static catalog: `Category` enum (9 categories), `CATALOG` (190 entries), `TEXTURES` (190 preloaded SVGs), skin tone support (`get_texture()`, `get_codepoint_with_tone()`), multi-codepoint `codepoint_to_char()`, lazy skin tone texture cache |
| `scripts/autoload/client_models.gd` | `markdown_to_bbcode()` renders `:name:` shortcodes as inline `[img]` BBCode tags; `emoji_to_dict()` converts `AccordEmoji` models |
| `scenes/messages/message_content.gd` | Calls `markdown_to_bbcode()` for emoji rendering, passes `channel_id` and `message_id` to reaction bar |
| `scenes/messages/reaction_pill.gd` | Reaction display: looks up emoji textures, calls `Client.add_reaction()`/`Client.remove_reaction()` on toggle |
| `scenes/messages/reaction_bar.gd` | Creates reaction pills, passes `channel_id` and `message_id` through to pills |
| `scenes/messages/cozy_message.gd` | Context menu with "Add Reaction" option, opens emoji picker for reaction selection |
| `scenes/messages/collapsed_message.gd` | Same context menu with "Add Reaction" as cozy_message |
| `scripts/autoload/client.gd` | `add_reaction()` (line 403) and `remove_reaction()` (line 413) mutation methods, gateway signal connections (lines 244-248) |
| `scripts/autoload/client_gateway.gd` | Gateway handlers: `on_reaction_add` (line 290), `on_reaction_remove` (line 320), `on_reaction_clear` (line 344), `on_reaction_clear_emoji` (line 356) |
| `scripts/autoload/app_state.gd` | `emojis_updated` (line 36) and `reactions_updated` (line 38) signals |
| `scripts/autoload/config.gd` | `get_emoji_skin_tone()` / `set_emoji_skin_tone()` for persisting skin tone preference (0=Default, 1-5=tones) |
| `addons/accordkit/models/emoji.gd` | `AccordEmoji` model with `image_url` field parsed from server responses |
| `scenes/user/user_settings.gd` | Skin tone dropdown in Notifications page under "EMOJI" section |
| `scripts/download_emoji.sh` | One-time script to download Twemoji SVGs for skin tone variants (95) and flags (30) |
| `assets/theme/emoji/*.svg` | 285 Twemoji SVG files: 160 base + 95 skin tone variants + 30 flags |
| `theme/icons/smile.svg` | Emoji button icon in composer toolbar |

## Implementation Details

### EmojiData Catalog (emoji_data.gd)

- `Category` enum: `SMILEYS`, `PEOPLE`, `NATURE`, `FOOD`, `ACTIVITIES`, `TRAVEL`, `OBJECTS`, `SYMBOLS`, `FLAGS`
- `CATEGORY_NAMES`: Human-readable names for tooltip text (e.g., "Smileys & Emotion", "People & Body", "Flags")
- `CATEGORY_ICONS`: Maps each category to its representative codepoint (used as the tab icon). FLAGS uses `1f1fa-1f1f8` (US flag)
- `CATALOG`: Dictionary mapping each `Category` to an array of `{name, codepoint}` entries. 20 per built-in category, 30 for FLAGS. Codepoints are hex strings; flags use multi-codepoint format (e.g., `"1f1fa-1f1f8"`)
- `TEXTURES`: Dictionary mapping emoji name to `preload()`ed SVG textures. All 190 base emoji are preloaded at class load time
- `SKIN_TONE_MODIFIERS`: Array of 6 entries (index 0 = empty/default, 1-5 = skin tone hex codepoints `1f3fb`..`1f3ff`)
- `SKIN_TONE_EMOJI`: Array of 19 emoji names in the People category that support skin tone variants (all except `handshake`)
- `_skin_tone_textures` (static var): Lazily-loaded cache of skin tone variant textures (keyed by full codepoint like `"1f44d-1f3fb"`)
- `_name_lookup` (static var): Lazily-built dictionary mapping emoji name to `{name, codepoint}` entry for O(1) lookup
- `get_all_for_category(category)`: Returns the entry array for a category
- `get_by_name(emoji_name)`: Dictionary lookup via `_name_lookup` (lazy-initialized on first call)
- `supports_skin_tone(emoji_name)`: Returns true if the emoji supports skin tone variants
- `get_codepoint_with_tone(emoji_name, tone)`: Returns the codepoint with skin tone modifier appended (e.g., `"1f44d-1f3fb"` for thumbs_up + light tone). Returns base codepoint if tone is 0 or emoji doesn't support tones
- `get_texture(emoji_name, tone)`: Returns the texture for the emoji with the given skin tone. Lazily loads skin tone SVGs on first access. Falls back to base texture if the variant file doesn't exist
- `codepoint_to_char(hex_codepoint)`: Converts hex codepoint string to Unicode character(s). Handles multi-codepoint sequences by splitting on `-` (e.g., `"1f1fa-1f1f8"` produces two regional indicator characters for the US flag)

### Emoji Picker Panel (emoji_picker.gd)

- Extends `PanelContainer`, starts hidden (`visible = false` in .tscn)
- **Custom tab**: If `AppState.current_guild_id` is set (line 28), a "Custom" tab (star icon) is prepended to the category bar. Clicking it loads custom emoji from the server via `Client.get_emojis()` (line 92) and renders them with CDN-loaded textures. Textures are cached in `_custom_emoji_cache` (line 11) to avoid re-fetching
- **Category bar**: `_build_category_bar()` (line 26) creates a flat `Button` (36x36px) per category with the category's representative emoji as icon and category name as tooltip. Active category highlighted white, inactive dimmed to `Color(0.58, 0.608, 0.643)` (line 64)
- **Search**: `_on_search_changed(query)` (line 145) clears grid, then searches both built-in emoji and cached custom emoji by name. Empty query reloads the current category
- **Grid population**: `_load_category(cat)` (line 81) clears grid, then calls `_add_emoji_cell()` for each entry
- **Custom emoji cells**: `_add_custom_emoji_cell(emoji)` (line 99) creates a cell, loads the texture from CDN via HTTPRequest (with PNG loading), and emits `emoji_picked` with `custom:name:id` format on click (line 140)
- **Dismiss**: `_input(event)` (line 185) handles Escape key and clicks outside the picker's global rect, setting `visible = false`
- **Signal**: `emoji_picked(emoji_name: String)` (line 3) emitted when a cell is clicked. For custom emoji, the format is `custom:name:id`

### Emoji Button Cell (emoji_button_cell.gd)

- Extends `Button` (36x36px, flat, centered icon, expand_icon enabled)
- `setup(data)`: Stores `data.name` as `_emoji_name`, sets `icon` via `EmojiData.get_texture()` with the user's skin tone preference, sets tooltip to name with underscores replaced by spaces
- `_on_pressed()`: Emits `emoji_selected(_emoji_name)`
- Hover style: light gray background (`Color(0.25, 0.26, 0.28)`) with 4px corner radius (defined in .tscn)

### Composer Integration (composer.gd)

- `EmojiPickerScene` preloaded (line 3)
- **Lazy instantiation**: `_on_emoji_button()` (line 68) toggles visibility if picker exists; otherwise instantiates, adds to scene tree root, and connects `emoji_picked` signal (line 75)
- **Positioning**: `_position_picker()` (line 79) places the picker above the emoji button, right-aligned. Clamped to viewport bounds with 4px margin (lines 89-90)
- **Insertion**: `_on_emoji_picked(emoji_name)` (line 93) inserts `:name:` shortcodes for both built-in and custom emoji:
  - Custom emoji (`custom:name:id` prefix): extracts name from parts, inserts `:name:` (lines 95-101)
  - Built-in emoji: validates name via `EmojiData.get_by_name()`, inserts `:emoji_name:` (lines 103-106)
  - Text is spliced at the current caret position (lines 107-112)
- **Cleanup**: `_exit_tree()` (line 116) calls `queue_free()` on the picker instance if it exists

### Emoji Rendering in Messages (client_models.gd)

- `markdown_to_bbcode()` (line 324) converts `:emoji_name:` shortcodes to inline images
- Regex pattern `:([a-z0-9_]+):` matches shortcodes (line 372)
- Matches are processed in reverse order to maintain string indices (line 374)
- Each match is looked up via `EmojiData.get_by_name()` (line 377); if found, replaced with `[img=20x20]res://assets/theme/emoji/CODEPOINT.svg[/img]` (line 380)
- Custom emoji shortcodes (`:custom_name:`) are resolved via `ClientModels.custom_emoji_paths` — if the name is found in the custom emoji cache, it renders as `[img=20x20]{cached_path}[/img]`

### Reactions API Integration

- **Client methods**: `Client.add_reaction(channel_id, message_id, emoji_name)` (line 403) calls `AccordClient.reactions.add()`, `Client.remove_reaction()` (line 413) calls `reactions.remove_own()`
- **Reaction pill**: `reaction_pill.gd` receives `channel_id` and `message_id` via `setup()` (line 16). On toggle (line 29), performs optimistic local count update (lines 31-35) then calls `Client.add_reaction()` or `Client.remove_reaction()` (lines 39-42). Active state uses a blue-tinted StyleBoxFlat (line 44)
- **Reaction bar**: `reaction_bar.gd` accepts `channel_id` and `message_id` in `setup()` (line 5) and forwards them to each pill (lines 17-18)
- **Message content**: `message_content.gd` extracts `channel_id` and `id` from message data (lines 23-24) and passes them to `reaction_bar.setup()` (line 25)
- **Context menu**: Both `cozy_message.gd` (line 94) and `collapsed_message.gd` (line 89) have "Add Reaction" (ID 3) in their context menus. This opens an emoji picker (line 97/92) and routes the selection to `Client.add_reaction()` (line 120/115). Custom emoji have the `custom:` prefix stripped before the API call (line 119/114)
- **Gateway handlers**: `client_gateway.gd` handles `reaction_add` (line 290), `reaction_remove` (line 320), `reaction_clear` (line 344), and `reaction_clear_emoji` (line 356) events by updating the message cache and emitting `AppState.messages_updated`

### Visual Style

- Picker background: `Color(0.184, 0.192, 0.212)`, 8px corner radius, 8px padding
- Search input background: `Color(0.118, 0.125, 0.141)`, 4px corner radius
- Grid: 8 columns, 2px horizontal and vertical separation
- Cell hover: `Color(0.25, 0.26, 0.28)` with 4px corner radius
- Reaction pill active state: `Color(0.345, 0.396, 0.949, 0.3)` background with 1px `Color(0.345, 0.396, 0.949)` border, 8px corner radius

## Implementation Status

- [x] Emoji button in composer toolbar (smile.svg icon)
- [x] Emoji picker panel with dark theme styling
- [x] 9 category tabs with icon buttons and active highlighting (including Flags)
- [x] 190 Twemoji SVGs across 9 categories (20 per built-in, 30 flags) + 95 skin tone variants
- [x] Search-by-name filtering across all categories
- [x] Shortcode insertion at caret position (`:name:` format)
- [x] Shortcode rendering as inline images via `markdown_to_bbcode()`
- [x] Picker auto-closes after selection
- [x] Dismiss via Escape key or click-outside
- [x] Lazy instantiation (picker created on first use)
- [x] Viewport-clamped positioning
- [x] Shared `EmojiData.TEXTURES` used by both picker and reaction pills
- [x] Picker cleanup on composer exit
- [x] Reactions call server API (`Client.add_reaction()` / `Client.remove_reaction()`)
- [x] Optimistic local reaction count updates
- [x] Gateway reaction event handlers (add, remove, clear, clear_emoji)
- [x] "Add Reaction" context menu on messages (cozy and collapsed)
- [x] Custom server emoji tab in picker (CDN loading with caching)
- [x] `get_by_name()` optimized with dictionary lookup
- [x] `emoji.create` and `emoji.delete` gateway events handled (real-time sync)
- [x] Custom emoji rendered inline in messages via `markdown_to_bbcode()` (cached to `user://emoji_cache/`)
- [x] Custom emoji displayed on reaction pills (fallback to `ClientModels.custom_emoji_textures`)
- [x] Recently used emoji section (persisted in config, shown as first tab with watch icon)
- [x] Reaction cache double-mutation fixed (gateway events are sole source of truth)
- [x] `AccordEmoji` model `image_url` field parsed from server responses (preferred over manual CDN URL construction)
- [x] Skin tone preference (Default + 5 tones) persisted in config, applied to picker, messages, and reaction pills
- [x] Skin tone settings UI in Notifications page (dropdown under "EMOJI" section)
- [x] Skin tone variant textures lazily loaded (95 SVGs, not preloaded at startup)
- [x] Flags category with 30 country flag emoji (multi-codepoint regional indicator pairs)
- [x] Multi-codepoint `codepoint_to_char()` for flags and ZWJ sequences

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| `reactions_updated` signal declared but unused | Medium | `AppState.reactions_updated` (line 38) is declared but never emitted or connected; gateway handlers emit `messages_updated` instead, causing full message list re-renders for reaction changes |
| Upload button not connected | Low | `composer.tscn` has an UploadButton (plus.svg icon) but it has no `pressed` connection in `composer.gd` |
