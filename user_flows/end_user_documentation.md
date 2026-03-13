# End-User Documentation

Priority: 56
Depends on: None

## Overview

End-user documentation is a set of Markdown pages in the `docs/` directory that explain daccord to non-technical users. Each page uses YAML front matter for metadata and is organized into seven sections: Getting Started, Messaging, Navigation, Voice & Video, Customization, Administration, and Troubleshooting. The content is designed to be consumed by external static site generators or help portals.

## User Steps

### Reading documentation

1. User visits the hosted documentation site (or reads the Markdown files directly)
2. Home page (`docs/index.md`) shows an overview with links grouped by section
3. User clicks a topic to read the relevant page
4. Cross-links between pages guide the user to related topics

### Contributing documentation

1. Author reads `docs/README.md` for conventions (audience, tone, front matter, linking)
2. Author creates or edits a Markdown file in the appropriate section directory
3. Author adds YAML front matter (`title`, `description`, `order`, `section`)
4. Author uses relative Markdown links for cross-references between pages
5. Author places any images in an `images/` subdirectory next to the page

## Signal Flow

```
Not applicable -- end-user documentation is static content with no runtime signals.
The docs/ directory is consumed by external tooling, not by the Godot application.
```

## Key Files

| File | Role |
|------|------|
| `docs/README.md` | Authoring conventions: audience, tone, front matter fields, image/link rules |
| `docs/index.md` | Documentation home page with section-grouped links to all pages |
| `docs/getting-started/installation.md` | Platform download/install instructions (Linux, Windows, macOS, Android) |
| `docs/getting-started/adding-a-server.md` | Add Server dialog, URL format, multi-server, removing a server |
| `docs/getting-started/creating-an-account.md` | Sign In / Register flow, credential persistence |
| `docs/getting-started/your-first-message.md` | Sending, reading, and replying to a message |
| `docs/messaging/sending-messages.md` | Send, reply, edit, delete, typing indicator |
| `docs/messaging/direct-messages.md` | DM mode, DM list, group DMs, search |
| `docs/messaging/reactions-and-emoji.md` | Emoji picker, reactions, skin tone |
| `docs/messaging/file-sharing.md` | Upload, paste, inline preview |
| `docs/navigation/spaces-and-channels.md` | Space bar, folders, channels, categories, tabs, responsive |
| `docs/voice-and-video/voice-channels.md` | Join, controls, screen share, video, settings |
| `docs/customization/themes.md` | Presets, custom colors, sharing, reduce motion, UI scale |
| `docs/customization/user-settings.md` | Settings pages overview |
| `docs/customization/profiles.md` | Create, switch, password, delete profiles |
| `docs/administration/managing-your-space.md` | Channels, roles, categories, channel permissions |
| `docs/administration/moderation.md` | Kick, ban, timeout, message deletion, audit log |
| `docs/administration/invites.md` | Create, join, manage invites |
| `docs/troubleshooting/common-issues.md` | Connection, sound, messages, app start, error reporting |
| `docs/troubleshooting/keyboard-shortcuts.md` | Messaging and general keyboard shortcuts |

## Implementation Details

### Directory structure

The `docs/` tree is organized by section, each matching a directory name:

```
docs/
  README.md                        # Authoring guide (not published)
  index.md                         # Home page
  getting-started/                 # First-time setup (4 pages)
    installation.md
    adding-a-server.md
    creating-an-account.md
    your-first-message.md
  messaging/                       # Day-to-day messaging (4 pages)
    sending-messages.md
    direct-messages.md
    reactions-and-emoji.md
    file-sharing.md
  navigation/                      # Spaces and channels (1 page)
    spaces-and-channels.md
  voice-and-video/                 # Voice, video, screen share (1 page)
    voice-channels.md
  customization/                   # Personalization (3 pages)
    themes.md
    user-settings.md
    profiles.md
  administration/                  # Admin tasks (3 pages)
    managing-your-space.md
    moderation.md
    invites.md
  troubleshooting/                 # Help (2 pages)
    common-issues.md
    keyboard-shortcuts.md
```

### Front matter convention

Every page starts with YAML front matter:

```yaml
---
title: Page Title          # Used in navigation and <title> tags
description: Short summary # SEO and link previews
order: 1                   # Sort order within section (lower first)
section: getting-started   # Parent section slug (matches directory)
---
```

### Content conventions (from docs/README.md)

- **Audience:** Non-technical end-users. No implementation details, API references, or code.
- **Tone:** Friendly, concise, direct. Second person ("you").
- **Headings:** H1 matches the `title`. H2/H3 for subsections. No H4+.
- **Images:** Placed in `images/` subdirectory next to the page. Relative paths.
- **Links:** Relative Markdown links between pages (e.g., `../messaging/sending-messages.md`).

### Page content plan

Each page maps to implemented features in the codebase. The following summarizes what each page should cover based on the current implementation.

#### Getting Started (complete)

| Page | Content | Source |
|------|---------|--------|
| `installation.md` | Platform downloads, per-OS install steps, auto-updates | `cross_platform_github_releases.md`, `auto_update.md` |
| `adding-a-server.md` | + button, URL format, multi-server, removing a server | `scenes/sidebar/guild_bar/add_server_dialog.gd` |
| `creating-an-account.md` | Sign In / Register toggle, password generation, session persistence | `scenes/sidebar/guild_bar/auth_dialog.gd` |
| `your-first-message.md` | Send with Enter, Shift+Enter newline, reply flow, cozy/collapsed layout | `scenes/messages/composer/composer.gd`, `scenes/messages/message_view.gd` |

#### Messaging (complete)

| Page | Content | Source |
|------|---------|--------|
| `sending-messages.md` | Send, reply, edit (inline, Enter saves, Escape cancels), delete with confirmation, Up Arrow to edit last, markdown formatting, typing indicator | `scenes/messages/message_content.gd`, `scenes/messages/composer/composer.gd` |
| `direct-messages.md` | DM button in space bar, DM list, search, group DMs, sending messages in DMs | `scenes/sidebar/direct/dm_list.gd`, `scenes/sidebar/direct/dm_channel_item.gd` |
| `reactions-and-emoji.md` | Emoji picker (8 categories, search), add/remove reaction, reaction pills, skin tone setting | `scenes/messages/composer/emoji_picker.gd`, `scenes/messages/reaction_bar.gd`, `scenes/messages/reaction_pill.gd` |
| `file-sharing.md` | Upload via attachment button, drag-and-drop, paste images from clipboard, inline image preview, file download links | `scenes/messages/composer/composer.gd`, `scenes/messages/message_content.gd` |

#### Navigation (complete)

| Page | Content | Source |
|------|---------|--------|
| `spaces-and-channels.md` | Space bar icons, space folders (collapsible groups), channel list with categories, four channel types (text/voice/announcement/forum), tabs, responsive drawer | `scenes/sidebar/guild_bar/guild_bar.gd`, `scenes/sidebar/channels/channel_list.gd`, `scenes/sidebar/channels/channel_item.gd` |

#### Voice & Video (complete)

| Page | Content | Source |
|------|---------|--------|
| `voice-channels.md` | Click to join, voice bar (mute/deafen/video/screen share/soundboard/settings/disconnect), screen picker, speaking indicator, voice settings | `scenes/sidebar/voice_bar.gd`, `scenes/main/main_window_voice_view.gd`, `scripts/autoload/client_voice.gd` |

#### Customization (complete)

| Page | Content | Source |
|------|---------|--------|
| `themes.md` | 5 presets (Dark, Light, Nord, Monokai, Solarized), custom color editor, theme sharing (copy/paste/inline apply), reduce motion, UI scale, skin tone | `scripts/autoload/theme_manager.gd` |
| `user-settings.md` | Settings panel pages (My Account, Profile, Voice & Video, Sound, Notifications, Appearance, Change Password, 2FA, Delete Account) | `scenes/user/app_settings.gd` |
| `profiles.md` | Create/switch/delete profiles, password protection, per-profile config, CLI `--profile` flag | `scripts/autoload/config_profiles.gd`, `scenes/user/user_settings_profiles_page.gd` |

#### Administration (complete)

| Page | Content | Source |
|------|---------|--------|
| `managing-your-space.md` | Space settings, channel CRUD, categories, role management, channel permission overrides | `scenes/admin/space_settings_dialog.gd`, `scenes/admin/channel_management_dialog.gd` |
| `moderation.md` | Kick/ban/unban, timeout, mute/deafen, bulk unban, message deletion, audit log | `scenes/admin/moderate_member_dialog.gd`, `scenes/admin/ban_dialog.gd`, `scenes/admin/ban_list_dialog.gd` |
| `invites.md` | Create invite, `daccord://` deep link joining, manage/revoke invites | `scenes/admin/invite_management_dialog.gd`, `scenes/admin/invite_row.gd` |

#### Troubleshooting (complete)

| Page | Content | Source |
|------|---------|--------|
| `common-issues.md` | Connection failures, reconnection, no voice sound, messages not loading, app won't start, error reporting | `user_flows/server_disconnects_timeouts.md`, `user_flows/auto_update.md` |
| `keyboard-shortcuts.md` | Enter/Shift+Enter, Up Arrow edit, Escape cancel, Ctrl+V paste | `scenes/messages/composer/composer.gd`, `scenes/messages/message_content.gd` |

### Relationship to user flows

User flows (`user_flows/`) are developer-facing documents verified against the codebase with signal traces, line references, and implementation gaps. End-user docs (`docs/`) distill those flows into user-friendly language, stripping all code references. When a user flow is updated, the corresponding doc page should be reviewed for accuracy.

| User Flow | Doc Page(s) |
|-----------|-------------|
| `user_onboarding.md` | `getting-started/*` |
| `server_connection.md` | `getting-started/adding-a-server.md`, `getting-started/creating-an-account.md` |
| `messaging.md`, `editing_messages.md` | `messaging/sending-messages.md` |
| `direct_messages.md`, `group_dms.md` | `messaging/direct-messages.md` |
| `emoji_picker.md`, `message_reactions.md` | `messaging/reactions-and-emoji.md` |
| `file_sharing.md` | `messaging/file-sharing.md` |
| `guild_channel_navigation.md`, `channel_categories.md`, `guild_folders.md` | `navigation/spaces-and-channels.md` |
| `voice_channels.md`, `video_chat.md`, `screen_sharing.md` | `voice-and-video/voice-channels.md` |
| `theming.md` | `customization/themes.md` |
| `user_settings.md` | `customization/user-settings.md` |
| `profiles.md` | `customization/profiles.md` |
| `admin_server_management.md` | `administration/managing-your-space.md` |
| `moderation.md`, `admin_user_management.md` | `administration/moderation.md` |
| `admin_server_management.md` (invite section) | `administration/invites.md` |
| `server_disconnects_timeouts.md` | `troubleshooting/common-issues.md` |
| `accessibility.md` | `troubleshooting/keyboard-shortcuts.md` |

## Implementation Status

- [x] `docs/README.md` -- authoring conventions documented
- [x] `docs/index.md` -- home page with full section/page index
- [x] `docs/getting-started/installation.md`
- [x] `docs/getting-started/adding-a-server.md`
- [x] `docs/getting-started/creating-an-account.md`
- [x] `docs/getting-started/your-first-message.md`
- [x] `docs/messaging/sending-messages.md`
- [x] `docs/messaging/direct-messages.md`
- [x] `docs/messaging/reactions-and-emoji.md`
- [x] `docs/messaging/file-sharing.md`
- [x] `docs/navigation/spaces-and-channels.md`
- [x] `docs/voice-and-video/voice-channels.md`
- [x] `docs/customization/themes.md`
- [x] `docs/customization/user-settings.md`
- [x] `docs/customization/profiles.md`
- [x] `docs/administration/managing-your-space.md`
- [x] `docs/administration/moderation.md`
- [x] `docs/administration/invites.md`
- [x] `docs/troubleshooting/common-issues.md`
- [x] `docs/troubleshooting/keyboard-shortcuts.md`

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| `installation.md` lists Windows file as `daccord-windows-installer.exe` | Medium | Actual release artifact is `daccord-windows-x86_64-setup.exe` (release.yml line 635) |
| `installation.md` missing Web platform | Low | Release CI builds `daccord-web.zip` but installation docs don't mention the web export |
| `adding-a-server.md` missing query parameter docs | Medium | Code supports `?token=value` and `?invite=code` in URLs (add_server_dialog.gd line 37) but docs don't mention these |
| `sending-messages.md` missing drafts | Low | Composer auto-saves per-channel draft text (composer.gd lines 414-419) but docs don't mention it |
| `sending-messages.md` missing message queue | Low | Messages queue while disconnected and send on reconnect (composer.gd lines 70-87) -- not documented |
| `direct-messages.md` missing friends tab | Medium | DM panel has Friends vs Messages tabs (dm_list.gd lines 36-45) but docs only describe the DM list |
| `direct-messages.md` missing close DM | Low | Users can close DMs from the list (dm_list.gd lines 67-69) -- not documented |
| `file-sharing.md` missing 25 MB limit | Low | Upload has a 25 MB size limit with error message but docs don't mention the cap |
| `file-sharing.md` missing audio/video attachments | Low | Audio attachments get inline player with progress slider; video gets clickable thumbnail (message_content.gd lines 399-537) -- not documented |
| `user-settings.md` missing Connections page | Low | App settings has a Connections page (app_settings.gd) but docs don't mention it |
| `user-settings.md` missing idle timeout | Low | Auto-idle status after configurable timeout (app_settings.gd lines 759-775) -- not documented |
| `invites.md` missing expiration/max-uses options | Medium | Invite creation supports expiration (30min to never) and max uses (invite_management_dialog.gd lines 37-48) but docs don't mention these options |
| `invites.md` missing temporary member flag | Low | Invites can mark joiners as temporary members who are removed when they leave (invite_management_dialog.gd line 19) -- not documented |
| `keyboard-shortcuts.md` sparse | Medium | Only covers 5 shortcuts; missing thread navigation, tab switching, DM search, and other shortcuts |
| No build pipeline for docs | Low | No static site generator, CI build, or deployment configured. The Markdown is ready for external tooling but nothing consumes it yet |
| No screenshots or images | Medium | README.md specifies an `images/` convention per section but no screenshots exist. Visual guides would significantly help non-technical users |

## Tasks

### DOCS-1: Write messaging section (4 pages)
- **Status:** done
- **Impact:** 3
- **Effort:** 2
- **Tags:** docs

### DOCS-2: Write navigation page
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** docs

### DOCS-3: Write voice & video page
- **Status:** done
- **Impact:** 2
- **Effort:** 1
- **Tags:** docs

### DOCS-4: Write customization section (3 pages)
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** docs

### DOCS-5: Write administration section (3 pages)
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** docs

### DOCS-6: Write troubleshooting section (2 pages)
- **Status:** done
- **Impact:** 2
- **Effort:** 1
- **Tags:** docs

### DOCS-7: No build pipeline for docs
- **Status:** todo
- **Impact:** 1
- **Effort:** 2
- **Tags:** infra
- **Notes:** No static site generator, CI build, or deployment configured. The Markdown is ready for external tooling but nothing consumes it yet. Consider MkDocs, Docusaurus, or similar.

### DOCS-8: No screenshots or images
- **Status:** todo
- **Impact:** 2
- **Effort:** 3
- **Tags:** docs
- **Notes:** README.md specifies an `images/` convention per section but no screenshots exist. Visual guides would significantly help non-technical users understand the UI.

### DOCS-9: Fix inaccuracies in existing pages
- **Status:** todo
- **Impact:** 3
- **Effort:** 1
- **Tags:** docs
- **Notes:** Fix Windows installer filename in `installation.md`, add query parameter docs to `adding-a-server.md`, add friends tab to `direct-messages.md`, add invite options to `invites.md`.
