# End-User Documentation

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

#### Messaging (4 pages to write)

| Page | Content | Source |
|------|---------|--------|
| `sending-messages.md` | Edit (inline, Enter saves, Escape cancels), delete with confirmation, Up Arrow to edit last, drafts per channel, markdown formatting, context menu | `scenes/messages/message_content.gd`, `scenes/messages/message_view_actions.gd`, `scenes/messages/composer/composer.gd` |
| `direct-messages.md` | DM button in space bar, DM list with online status, search, group DMs, close DM, mention/unread badges | `scenes/sidebar/direct/dm_list.gd`, `scenes/sidebar/direct/dm_channel_item.gd` |
| `reactions-and-emoji.md` | Emoji picker (8 categories, search, recently used), add reaction via context menu or picker, reaction pills with count, remove reaction | `scenes/messages/composer/emoji_picker.gd`, `scenes/messages/reaction_bar.gd`, `scenes/messages/reaction_pill.gd` |
| `file-sharing.md` | Upload via file picker, paste images from clipboard, 25 MB limit, inline image preview with lightbox, audio player, video fallback, file size display | `scenes/messages/composer/composer.gd`, `scenes/messages/message_content.gd` |

#### Navigation (1 page to write)

| Page | Content | Source |
|------|---------|--------|
| `spaces-and-channels.md` | Space bar icons, space folders (collapsible groups), channel list with categories, five channel types (text/voice/announcement/forum/category), mention badges, unread indicators, tab management | `scenes/sidebar/guild_bar/guild_bar.gd`, `scenes/sidebar/channels/channel_list.gd`, `scenes/sidebar/channels/channel_item.gd` |

#### Voice & Video (1 page to write)

| Page | Content | Source |
|------|---------|--------|
| `voice-channels.md` | Click to join, voice bar (mute/deafen/video/screen share/disconnect), screen picker, soundboard, voice connection indicator, participant list | `scenes/sidebar/voice_bar.gd`, `scenes/main/main_window_voice_view.gd`, `scripts/autoload/client_voice.gd` |

#### Customization (3 pages to write)

| Page | Content | Source |
|------|---------|--------|
| `themes.md` | 5 presets (Dark, Light, Nord, Monokai, Solarized), custom color editor, base64 theme sharing in chat, live preview | `scripts/autoload/theme_manager.gd` |
| `user-settings.md` | Settings panel pages (Profiles, Voice & Video, Sound, Appearance, Notifications, Updates), device selection, volume sliders | `scenes/user/app_settings.gd` |
| `profiles.md` | Create/switch/rename/delete profiles, password protection, per-profile config, import profiles | `scripts/autoload/config_profiles.gd`, `scenes/user/user_settings_profiles_page.gd` |

#### Administration (3 pages to write)

| Page | Content | Source |
|------|---------|--------|
| `managing-your-space.md` | Space settings (name, description, icon), channel CRUD, category management, role management, channel permissions | `scenes/admin/space_settings_dialog.gd`, `scenes/admin/channel_management_dialog.gd` |
| `moderation.md` | Kick/ban/unban, timeout durations, ban list with reasons, message deletion, permission requirements | `scenes/admin/moderate_member_dialog.gd`, `scenes/admin/ban_dialog.gd`, `scenes/admin/ban_list_dialog.gd` |
| `invites.md` | Create invite with expiration and max uses, temporary invites, invite list, bulk revoke, copy link | `scenes/admin/invite_management_dialog.gd`, `scenes/admin/invite_row.gd` |

#### Troubleshooting (2 pages to write)

| Page | Content | Source |
|------|---------|--------|
| `common-issues.md` | Connection failures, HTTPS issues, token expiry, gateway reconnects, blank UI on startup, update problems | `user_flows/server_disconnects_timeouts.md`, `user_flows/auto_update.md` |
| `keyboard-shortcuts.md` | Enter/Shift+Enter, Up Arrow edit, Escape cancel, Ctrl+V paste, context menu | `scenes/messages/composer/composer.gd`, `scenes/messages/message_content.gd` |

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
- [ ] `docs/messaging/sending-messages.md`
- [ ] `docs/messaging/direct-messages.md`
- [ ] `docs/messaging/reactions-and-emoji.md`
- [ ] `docs/messaging/file-sharing.md`
- [ ] `docs/navigation/spaces-and-channels.md`
- [ ] `docs/voice-and-video/voice-channels.md`
- [ ] `docs/customization/themes.md`
- [ ] `docs/customization/user-settings.md`
- [ ] `docs/customization/profiles.md`
- [ ] `docs/administration/managing-your-space.md`
- [ ] `docs/administration/moderation.md`
- [ ] `docs/administration/invites.md`
- [ ] `docs/troubleshooting/common-issues.md`
- [ ] `docs/troubleshooting/keyboard-shortcuts.md`

## Tasks

### DOCS-1: Write messaging section (4 pages)
- **Status:** todo
- **Impact:** 3
- **Effort:** 2
- **Tags:** docs
- **Notes:** `sending-messages.md` (edit/delete/drafts/markdown), `direct-messages.md` (DM mode/groups/search), `reactions-and-emoji.md` (picker/pills), `file-sharing.md` (upload/paste/inline preview).

### DOCS-2: Write navigation page
- **Status:** todo
- **Impact:** 3
- **Effort:** 1
- **Tags:** docs
- **Notes:** `spaces-and-channels.md` covering space bar, folders, channel categories, five channel types, unread/mention badges, tab management.

### DOCS-3: Write voice & video page
- **Status:** todo
- **Impact:** 2
- **Effort:** 1
- **Tags:** docs
- **Notes:** `voice-channels.md` covering join/leave, mute/deafen, video, screen share, soundboard. Note which features require the godot-livekit addon.

### DOCS-4: Write customization section (3 pages)
- **Status:** todo
- **Impact:** 2
- **Effort:** 2
- **Tags:** docs
- **Notes:** `themes.md` (presets/custom/sharing), `user-settings.md` (settings panel pages), `profiles.md` (create/switch/password/import).

### DOCS-5: Write administration section (3 pages)
- **Status:** todo
- **Impact:** 2
- **Effort:** 2
- **Tags:** docs
- **Notes:** `managing-your-space.md` (space settings/channels/roles), `moderation.md` (kick/ban/timeout), `invites.md` (create/revoke/copy).

### DOCS-6: Write troubleshooting section (2 pages)
- **Status:** todo
- **Impact:** 2
- **Effort:** 1
- **Tags:** docs
- **Notes:** `common-issues.md` (connection/auth/update problems), `keyboard-shortcuts.md` (full shortcut reference).

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
