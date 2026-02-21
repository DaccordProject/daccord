# Localization

Last touched: 2026-02-19

## Overview

daccord currently has no localization (i18n/l10n) infrastructure. All user-facing strings are hardcoded in English across scene files and GDScript code. Godot 4.5 supports PO/POT-based translation via `TranslationServer` and the `tr()` function, but none of this machinery is wired up. This document catalogs the current state and outlines what's needed to add multi-language support.

## User Steps (Target Experience)

1. User opens Settings (or a future Language menu).
2. User selects a language from a dropdown (e.g., English, French, German, Spanish).
3. All UI labels, buttons, placeholders, tooltips, and status messages update to the selected language.
4. The preference persists across sessions via `Config`.
5. On next launch, the client loads the saved locale automatically.

## Signal Flow (Target)

```
User selects language
  -> Config.set_value("app", "locale", locale_code)
  -> TranslationServer.set_locale(locale_code)
  -> All tr() calls automatically resolve to the new locale
  -> UI nodes with auto-translate update immediately
```

## Key Files

| File | Role |
|------|------|
| `project.godot` | No `[locale]` section exists yet; would register `.po` translation files |
| `scripts/autoload/config.gd` | Would persist the user's language preference |
| `addons/accordkit/models/space.gd` | Has `preferred_locale` field (line 24) — server-side setting, not client i18n |
| `scripts/autoload/client_models.gd` | Passes `preferred_locale` through to guild dict (line 253) |
| `user_flows/reducing_build_size.md` | Documents disabled advanced text server (lines 73-76), blocking RTL support |

## Implementation Details

### Current State: Zero i18n Infrastructure

There are no `.po`, `.pot`, `.csv`, or `.translation` files anywhere in the project. No GDScript file calls `tr()` or `TranslationServer`. The `project.godot` file has no `[locale]` section.

### Server-Side Locale Fields (Not Client i18n)

AccordKit models carry locale data from the accordserver API, but these are protocol fields, not client translations:

- `AccordSpace.preferred_locale` — defaults to `"en-US"` (`addons/accordkit/models/space.gd`, line 24). Deserialized from server JSON (line 66), serialized back (line 97). Passed through `ClientModels.space_to_guild_dict()` (line 253 of `client_models.gd`).
- `AccordInteraction.locale` — nullable field on interaction objects (`addons/accordkit/models/interaction.gd`, line 16).

These could inform a future "match server locale" feature but are unrelated to translating the client UI.

### RTL / Complex Script Support Disabled

The custom export template configuration (`user_flows/reducing_build_size.md`, lines 73-76) explicitly disables the advanced text server:

```
module_text_server_adv_enabled = "no"
module_text_server_fb_enabled = "yes"
```

The fallback text server does not support RTL scripts (Arabic, Hebrew) or complex scripts (Devanagari, Thai). Any localization to these languages would require re-enabling `module_text_server_adv_enabled` in the export template, increasing binary size.

### Hardcoded String Inventory

All user-facing strings are hardcoded English literals. The following categories exist:

**Scene files (`.tscn`) — static labels and placeholders:**

| Area | Files | Example Strings |
|------|-------|-----------------|
| Messaging | `message_action_bar.tscn`, `message_view.tscn`, `typing_indicator.tscn` | "Add Reaction", "Reply", "Edit", "Delete", "Loading messages...", "Someone is typing..." |
| Composer | `composer.tscn`, `emoji_picker.tscn`, `message_input.tscn` | "Replying to ...", "Cancel Reply", "Upload", "Emoji", "Send", "Search emoji..." |
| Sidebar | `voice_bar.tscn`, `dm_list.tscn`, `dm_channel_item.tscn`, `channel_list.tscn` | "Voice Connected", "DIRECT MESSAGES", "Close DM", "No channels yet" |
| Dialogs | `add_server_dialog.tscn`, `auth_dialog.tscn` | "Add a Server", "Sign In", "Register", "Apply" |
| User Settings | `user_settings.tscn` | "Voice & Video", "Sound", "Notifications", "Apply" |
| Admin | `space_settings_dialog.tscn`, `channel_management_dialog.tscn`, `role_management_dialog.tscn`, `ban_dialog.tscn`, `invite_management_dialog.tscn`, `confirm_dialog.tscn` | "Space Settings", "Manage Roles", "Ban User", "Are you sure?", "Cancel", "Confirm", "Save", "Delete" |
| Members | `member_list.tscn` | "MEMBERS", "Invite People" |
| Search | `search_panel.tscn` | "Search messages..." |

**Script files (`.gd`) — dynamically set strings:**

| Area | Files | Example Strings |
|------|-------|-----------------|
| Message view | `message_view.gd` | "Welcome to #%s", "No messages yet", "Connection lost. Reconnecting...", "Failed to load messages: %s" |
| Composer | `composer.gd` | "Message #%s", "Replying to %s", "File too large (max 25 MB): %s", "Cannot send messages — disconnected" |
| Message content | `message_content.gd` | "Enter to save \u00b7 Escape to cancel \u00b7 Shift+Enter for newline" |
| Context menus | `cozy_message.gd`, `collapsed_message.gd` | "Reply", "Edit", "Delete" |
| User bar | `user_bar.gd` | "daccord v%s", "What's on your mind?", "Clear Status" |
| User settings | `user_settings.gd`, `user_settings_twofa.gd`, `user_settings_danger.gd` | "My Account", "Change Password", "Delete My Account", "Enable 2FA" |
| Profile | `profile_card.gd`, `profile_edit_dialog.gd` | "ABOUT ME", "ROLES", "Edit Profile", "Upload Avatar" |
| Admin dialogs | `channel_management_dialog.gd`, `role_management_dialog.gd`, `invite_management_dialog.gd`, `ban_dialog.gd`, `space_settings_dialog.gd` | "Creating...", "Saving...", "Delete Selected (%d)" |
| Guild bar | `guild_icon.gd`, `add_server_dialog.gd`, `auth_dialog.gd` | "Folder name", "Checking...", "Connecting..." |
| Voice bar | `voice_bar.gd` | "Mic Off", "Cam On", "Sharing" |
| Soundboard | `soundboard_panel.gd`, `soundboard_management_dialog.gd` | "No sounds available.", "Sound name cannot be empty." |

### Recommended Approach: PO/POT Files

Godot natively supports GNU gettext PO/POT files. The recommended implementation:

1. **Create a POT template** at `i18n/messages.pot` with all extractable strings.
2. **Create PO files** per language (e.g., `i18n/fr.po`, `i18n/de.po`, `i18n/es.po`).
3. **Register translations** in `project.godot` under a `[locale]` section:
   ```ini
   [locale]
   translations=PackedStringArray("res://i18n/fr.po", "res://i18n/de.po", "res://i18n/es.po")
   ```
4. **Wrap all hardcoded strings** with `tr()`:
   ```gdscript
   # Before
   label.text = "Loading messages..."
   # After
   label.text = tr("Loading messages...")
   ```
5. **Handle format strings** with `tr()` + `%`:
   ```gdscript
   # Before
   text_input.placeholder_text = "Message #" + channel_name
   # After
   text_input.placeholder_text = tr("Message #%s") % channel_name
   ```
6. **Scene file strings** — Godot auto-translates `text` properties on Label, Button, etc. when `auto_translate_mode` is enabled (the default). Static `.tscn` strings will translate automatically once PO files are registered. Only dynamically set strings need explicit `tr()` calls.
7. **Persist locale preference** in `Config`:
   ```gdscript
   # In config.gd
   func set_locale(locale: String) -> void:
       config.set_value("app", "locale", locale)
       config.save(CONFIG_PATH)
       TranslationServer.set_locale(locale)

   func get_locale() -> String:
       return config.get_value("app", "locale", "en")
   ```
8. **Apply on startup** in `Client._ready()` or a dedicated autoload:
   ```gdscript
   TranslationServer.set_locale(Config.get_locale())
   ```

### Pluralization

PO files support plural forms natively. Godot's `tr()` does not handle plurals directly, but `TranslationServer` supports `tr_n()` for plural-aware translations:

```gdscript
# Example
label.text = tr_n("%d member", "%d members", count) % count
```

## Implementation Status

- [x] Server-side `preferred_locale` field passed through API models
- [ ] PO/POT translation files
- [ ] `tr()` wrapping on dynamically set strings
- [ ] Locale selection UI (settings menu or language dropdown)
- [ ] Locale preference persistence in Config
- [ ] `TranslationServer.set_locale()` call on startup
- [ ] RTL language support (requires re-enabling advanced text server)
- [ ] Plural-aware translations using `tr_n()`
- [ ] Date/time formatting per locale
- [ ] Number formatting per locale

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No PO/POT files exist | High | No translation infrastructure at all; need to create `i18n/` directory with `.pot` template and per-language `.po` files |
| No `tr()` calls anywhere | High | Every dynamically set string across ~30+ script files needs wrapping; static `.tscn` strings auto-translate once PO files are registered |
| No `[locale]` section in `project.godot` | High | Must register translation files for `TranslationServer` to load them |
| No language selection UI | High | Users have no way to change language; need a dropdown in settings |
| No locale persistence in Config | Medium | `config.gd` has no locale-related keys; need `set_locale()`/`get_locale()` methods |
| Advanced text server disabled | Medium | RTL languages (Arabic, Hebrew) and complex scripts (Devanagari, Thai) cannot render; re-enabling increases binary size (`reducing_build_size.md`, lines 73-76) |
| Format strings use concatenation | Medium | Strings like `"Message #" + channel_name` (`composer.gd`, line 40) need refactoring to `tr("Message #%s") % channel_name` for translator-friendly patterns |
| No date/time locale formatting | Low | Timestamps in messages use hardcoded English formatting; should use locale-aware formatting |
| No plural support | Low | Strings like "Delete Selected (%d)" need `tr_n()` for correct pluralization across languages |
| `preferred_locale` from server unused | Low | `AccordSpace.preferred_locale` (line 24) is stored but never influences client locale; could offer "match server language" option |
