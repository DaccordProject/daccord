# Localization

Last touched: 2026-03-17
Priority: 34
Depends on: None

## Overview

daccord now has full i18n infrastructure using Godot's PO/POT translation system. All 806+ user-facing strings across 92 GDScript files are wrapped with `tr()` calls. A POT template, 9 stub PO language files, locale persistence in Config, startup locale application via TranslationServer, and a language selection UI in App Settings are all implemented.

## User Steps

1. User opens App Settings → Appearance page.
2. User scrolls to the LANGUAGE section and selects a language from the dropdown (English, Français, Deutsch, Español, Português, 日本語, 中文, 한국어, العربية, Русский).
3. All dynamically set UI labels, buttons, placeholders, tooltips, and status messages update to the selected language via `tr()`.
4. Static `.tscn` text properties auto-translate via Godot's `auto_translate_mode`.
5. The preference persists across sessions via `Config.set_locale()`.
6. On next launch, Config._ready() calls `TranslationServer.set_locale()` with the saved locale.

## Signal Flow

```
User selects language in App Settings dropdown
  -> Config.set_locale(locale_code)
     -> _config.set_value("app", "locale", locale_code)
     -> _save() (encrypted ConfigFile)
     -> TranslationServer.set_locale(locale_code)
     -> AppState.config_changed.emit("app", "locale")
  -> All tr() calls automatically resolve to the new locale
  -> Scene nodes with auto_translate_mode update static text

On startup:
  Config._ready() (line 77)
    -> TranslationServer.set_locale(get_locale())
    -> Defaults to "en" if no saved preference
```

## Key Files

| File | Role |
|------|------|
| `project.godot` | `[locale]` section registers 9 PO translation files and locale filter |
| `i18n/messages.pot` | POT template with 806 translatable string entries |
| `i18n/fr.po` | French stub PO file (+ de, es, pt, ja, zh, ko, ar, ru) |
| `scripts/autoload/config.gd:565-573` | `get_locale()` / `set_locale()` — persists locale in encrypted config, calls TranslationServer |
| `scripts/autoload/config.gd:77` | Applies saved locale on startup in `_ready()` |
| `scenes/user/app_settings.gd:587-603` | Language dropdown UI in Appearance page |
| `scenes/messages/composer/composer.gd` | 20 tr()-wrapped strings (messages, errors, placeholders) |
| `scenes/messages/message_view.gd` | 10 tr()-wrapped strings (loading, empty states, errors) |
| `scenes/admin/server_management_panel.gd` | 66 tr()-wrapped strings (admin labels, settings) |
| `scenes/sidebar/user_bar.gd` | 39 tr()-wrapped strings (status, menus, dialogs) |

## Implementation Details

### Translation Infrastructure

**POT template** (`i18n/messages.pot`, 2435 lines): Standard GNU gettext format with all 806 unique translatable strings extracted from the codebase. Created 2026-03-17.

**PO language files** (`i18n/{fr,de,es,pt,ja,zh,ko,ar,ru}.po`): Stub files with headers only — ready for translators to populate with `msgstr` entries. Each follows standard PO format with charset UTF-8 and plural forms.

**project.godot registration** (`[locale]` section, line 63-67):
- `translations` — PackedStringArray listing all 9 PO files
- `locale_filter_mode=1` — whitelist mode
- `locale_filter` — restricts to the 10 supported locales (en + 9 translations)

### Locale Persistence (Config)

`Config.get_locale()` (line 565) reads from `_config.get_value("app", "locale", "en")` — defaults to English.

`Config.set_locale()` (line 568) writes the locale code, saves encrypted config, calls `TranslationServer.set_locale()`, and emits `AppState.config_changed("app", "locale")`.

On startup, `Config._ready()` (line 77) calls `TranslationServer.set_locale(get_locale())` before any UI is constructed, ensuring the correct locale is active from the start.

### Language Selection UI

Added to `app_settings.gd` in the Appearance page after the Emoji Skin Tone section (lines 587-603):
- LANGUAGE section label
- `OptionButton` with 10 locales: en, fr, de, es, pt, ja, zh, ko, ar, ru
- Display names in native script (e.g., "Français", "日本語", "العربية")
- Reads current locale from `Config.get_locale()`
- On selection, calls `Config.set_locale()` which triggers immediate TranslationServer update

### String Wrapping (tr() calls)

All 806+ user-facing strings across 92 files are wrapped with `tr()`:

**Pattern 1 — Direct assignments** (most common):
```gdscript
# Before:  label.text = "Loading messages..."
# After:   label.text = tr("Loading messages...")
```

**Pattern 2 — Format strings** (concatenation eliminated):
```gdscript
# Before:  placeholder_text = "Message #" + channel_name
# After:   placeholder_text = tr("Message #%s") % channel_name
```

**Pattern 3 — Static methods** (use TranslationServer directly):
```gdscript
# In static functions where tr() is unavailable:
TranslationServer.translate("%.1f MB")
```

**Pattern 4 — Dropdown/menu items**:
```gdscript
# Before:  dropdown.add_item("30 minutes")
# After:   dropdown.add_item(tr("30 minutes"))
```

**Pattern 5 — Const-to-property conversion** (for arrays with translatable labels):
```gdscript
# Before:  const LABELS := ["Online", "Idle"]
# After:   var LABELS: Array: get: return [tr("Online"), tr("Idle")]
```

### Categories of Wrapped Strings

| Category | Count | Examples |
|----------|-------|---------|
| Button/action labels | ~120 | "Save", "Cancel", "Delete", "Create", "Apply" |
| Status/loading messages | ~80 | "Loading...", "Saving...", "Connecting...", "Syncing..." |
| Error messages | ~100 | "Failed to load messages: %s", "Password is required." |
| Dialog titles/confirmations | ~90 | "Delete Channel", "Are you sure you want to...?" |
| Section headers | ~60 | "INPUT DEVICE", "THEME", "EMOJI SKIN TONE" |
| Menu/dropdown items | ~80 | "All Messages", "Only Mentions", "30 minutes" |
| Empty state messages | ~40 | "No messages yet", "No friends online." |
| Tooltips | ~40 | "Mute", "Deafen", "Add a Server", "Edit Channel" |
| Placeholder text | ~30 | "Search messages...", "Search emoji...", "My Space" |
| Context menu items | ~50 | "Reply", "Edit", "Delete", "Report", "Block" |
| Miscellaneous labels | ~120 | "ABOUT ME", "ROLES", "Unknown", activity prefixes |

### RTL / Complex Script Support

The custom export template (`reducing_build_size.md`) disables the advanced text server:
```
module_text_server_adv_enabled = "no"
module_text_server_fb_enabled = "yes"
```
The fallback text server does not support RTL scripts (Arabic, Hebrew) or complex scripts (Devanagari, Thai). The Arabic PO file (`ar.po`) is included as a stub, but full RTL rendering requires re-enabling `module_text_server_adv_enabled`, which increases binary size.

### Server-Side Locale Fields

`AccordSpace.preferred_locale` (`addons/accordkit/models/space.gd`, line 24) defaults to `"en-US"`. This is a protocol field from the server, not client i18n. It could be used for a future "match server language" feature but is currently not connected to the client locale system.

## Implementation Status

- [x] PO/POT translation files (`i18n/messages.pot` + 9 language stubs)
- [x] `tr()` wrapping on dynamically set strings (806+ strings across 92 files)
- [x] `[locale]` section in `project.godot` registering translations
- [x] Locale selection UI (Language dropdown in App Settings → Appearance)
- [x] Locale preference persistence in Config (`get_locale()` / `set_locale()`)
- [x] `TranslationServer.set_locale()` call on startup (`Config._ready()`)
- [x] Server-side `preferred_locale` field passed through API models
- [ ] Actual translations in PO files (stubs only — need translators)
- [ ] RTL language support (requires re-enabling advanced text server)
- [ ] Plural-aware translations using `tr_n()`
- [ ] Date/time formatting per locale
- [ ] Number formatting per locale
- [ ] `preferred_locale` from server influencing client locale

## Tasks

### L10N-1: No PO/POT files exist
- **Status:** done
- **Impact:** 4
- **Effort:** 3
- **Tags:** l10n
- **Notes:** Created `i18n/messages.pot` (806 entries, 2435 lines) and 9 stub PO files (fr, de, es, pt, ja, zh, ko, ar, ru)

### L10N-2: No `tr()` calls anywhere
- **Status:** done
- **Impact:** 4
- **Effort:** 2
- **Tags:** l10n
- **Notes:** Wrapped 806+ strings across 92 GDScript files; static `.tscn` strings auto-translate via Godot's `auto_translate_mode`

### L10N-3: No `[locale]` section in `project.godot`
- **Status:** done
- **Impact:** 4
- **Effort:** 1
- **Tags:** l10n
- **Notes:** Added `[locale]` section with translations array, locale filter whitelist for 10 locales

### L10N-4: No language selection UI
- **Status:** done
- **Impact:** 4
- **Effort:** 3
- **Tags:** config, ui
- **Notes:** Added Language dropdown to App Settings → Appearance page with 10 locales using native display names

### L10N-5: No locale persistence in Config
- **Status:** done
- **Impact:** 3
- **Effort:** 2
- **Tags:** config
- **Notes:** Added `get_locale()` / `set_locale()` to `config.gd` (lines 565-573); persists to encrypted ConfigFile, calls TranslationServer, emits config_changed

### L10N-6: Advanced text server disabled
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** ci
- **Notes:** RTL languages (Arabic, Hebrew) and complex scripts (Devanagari, Thai) cannot render; re-enabling increases binary size (`reducing_build_size.md`). Arabic stub PO is included but rendering will be broken without the advanced text server.

### L10N-7: Format strings use concatenation
- **Status:** done
- **Impact:** 3
- **Effort:** 4
- **Tags:** l10n
- **Notes:** All concatenation patterns like `"Message #" + name` refactored to `tr("Message #%s") % name` across all files

### L10N-8: No date/time locale formatting
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** Timestamps in messages use hardcoded English formatting; Godot's Time class doesn't have built-in locale-aware formatting — would need a custom formatter

### L10N-9: No plural support
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** Strings like "%d replies" need `tr_n()` for correct pluralization; PO plural forms are defined in headers but no `tr_n()` calls exist yet

### L10N-10: `preferred_locale` from server unused
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** `AccordSpace.preferred_locale` (line 24) is stored but never influences client locale; could offer "match server language" option in space settings

### L10N-11: PO files need actual translations
- **Status:** open
- **Impact:** 4
- **Effort:** 5
- **Tags:** l10n
- **Notes:** All 9 PO language files are stubs with empty `msgstr` entries. Need translators or a translation service to populate the 806 strings per language.

### L10N-12: `TranslationServer.set_locale()` on startup
- **Status:** done
- **Impact:** 4
- **Effort:** 1
- **Tags:** l10n
- **Notes:** `Config._ready()` (line 77) calls `TranslationServer.set_locale(get_locale())` on startup

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| PO files are empty stubs | High | 806 strings × 9 languages need translation; infrastructure is ready but no actual translations exist yet |
| RTL text server disabled | Medium | Arabic PO stub exists but rendering will break without `module_text_server_adv_enabled`; re-enabling increases binary ~2MB |
| No `tr_n()` plural support | Medium | Strings like "%d replies", "%d members", "%d player(s) joined" use hardcoded plural forms instead of PO-based pluralization |
| No locale-aware date/time | Low | Message timestamps use English formatting (e.g., "just now", "%dm ago"); would need custom locale-aware formatter |
| No locale-aware number formatting | Low | Number display uses Western Arabic numerals; some locales expect different separators or digit systems |
| Server `preferred_locale` unused | Low | Could auto-suggest matching client locale when joining a server with a different `preferred_locale` |
