# Emoji Picker

Priority: 12
Depends on: Messaging
Status: Complete

The emoji picker allows users to browse and insert emoji into their messages as `:name:` shortcodes. It provides a categorized catalog of ~340 Twemoji SVGs across 9 categories (including Flags), a search bar for filtering by name, and category tabs for quick navigation. Selected emoji are inserted as `:name:` shortcodes at the cursor position in the composer, and rendered inline as images by `markdown_to_bbcode()`. Emoji are also used in message reactions via a shared `EmojiData` catalog. The picker supports custom server emoji loaded from the CDN, displayed in a dedicated "Custom" category tab.

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
