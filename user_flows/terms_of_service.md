# In-App Terms of Service

Priority: 55
Depends on: None

## Overview

Server owners can define custom Terms of Service (ToS) for their instance, or disable ToS entirely. When enabled, users must accept the ToS during registration and when it changes. daccord ships with sensible default ToS text that server owners can use as-is, customize, or replace completely.

The instance-level ToS is stored in the `server_settings` table (`tos_enabled`, `tos_text`, `tos_version`, `tos_url`), exposed via the public `GET /settings` endpoint, and editable by admins via `PATCH /admin/settings`. The client fetches settings during registration to conditionally show a ToS checkbox. Space-level rules use `rules_channel_id` with a separate interstitial and local acceptance tracking.

## Design Principles

1. **Server-owner controlled** -- The ToS is configured per-instance by the server owner (super admin), not hardcoded by daccord.
2. **Opt-out** -- Server owners can disable ToS entirely (e.g. for private friend groups or development instances). When disabled, no acceptance checkbox or interstitial appears.
3. **Good defaults** -- daccord provides a default ToS template covering common-sense rules (no harassment, no illegal content, no spam). Server owners can use the defaults, edit them, or write their own from scratch.
4. **Space-level rules are separate** -- Instance-wide ToS (managed by the server owner) is distinct from per-space rules (managed by space admins via `rules_channel_id`). Both can coexist.

## Server-Side Configuration

ToS settings are stored in the `server_settings` table alongside other instance config. The migration `020_tos.sql` adds the columns and seeds the default template.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `tos_enabled` | `bool` | `true` | Whether ToS is active. When `false`, registration skips ToS and no acceptance is required. |
| `tos_text` | `string` | (default template) | Markdown-formatted ToS body. Server owner can edit or replace entirely. |
| `tos_version` | `int` | `1` | Auto-bumped when `tos_text` changes. Triggers re-acceptance for existing users. |
| `tos_url` | `string?` | `null` | Optional external URL. When set, the client links to this URL instead of displaying `tos_text` inline. |

### Default ToS Template

When a new accordserver instance is created, `tos_text` is populated with a default template via `020_tos.sql`:

```markdown
# Terms of Service

By using this server, you agree to the following:

## Respectful Conduct
- Treat all members with respect. Harassment, bullying, hate speech, and discrimination are not tolerated.
- Do not impersonate other users, staff, or public figures.

## Content Rules
- Do not share illegal content of any kind.
- Do not post spam, unsolicited advertising, or phishing links.
- NSFW content is only permitted in channels explicitly marked as NSFW.
- Do not share others' private information (doxxing).

## Moderation
- Moderators may delete messages, timeout, kick, or ban members who violate these terms.
- Moderation actions are logged for accountability.
- If you believe an action was taken in error, contact a server administrator.

## Privacy
- This server may log messages and activity for moderation purposes.
- Your data is handled according to the server operator's privacy practices.

## Changes
- These terms may be updated at any time. Continued use after changes constitutes acceptance.
```

The server owner can edit this text from the admin panel Settings tab or replace it entirely. Setting `tos_enabled = false` hides all ToS UI.

## User Steps

### Accepting ToS during registration

1. User opens the auth dialog in Register mode (`auth_dialog.gd`).
2. When switching to Register mode, the client fetches `GET /settings` to check `tos_enabled` (line 93 area).
3. **If ToS is disabled** (`tos_enabled == false`): No checkbox appears. Registration proceeds normally.
4. **If ToS is enabled:**
   a. A ToS checkbox row appears: "I agree to the _Terms of Service_" (lines 55-72).
   b. "Terms of Service" is a clickable link button that opens an inline dialog (rendering `tos_text`) or opens `tos_url` in the browser (lines 349-364).
   c. User checks the box. The Register button remains enabled but validation enforces the checkbox.
   d. `_validate_credentials()` checks `_tos_checkbox.button_pressed` and shows "You must accept the Terms of Service." if unchecked (line 152).

### Re-accepting ToS after an update (not yet implemented)

1. User logs in or is already connected.
2. Client receives a gateway event or login response indicating `tos_version` has changed since last acceptance.
3. A modal dialog appears: "The Terms of Service have been updated. Please review and accept to continue."
4. The dialog shows the updated `tos_text` (or links to `tos_url`) with an "Accept" button.
5. User clicks "Accept". Client sends `POST /users/@me/tos-accept { version }`.
6. If the user dismisses without accepting, the client remains in a limited state (can view but not send messages) until they accept.

### Viewing space rules

1. User selects a space that has a `rules_channel_id` set.
2. `main_window._on_space_selected()` checks `Config.has_rules_accepted(space_id)` (line 516 area).
3. If not accepted, a `rules_interstitial_dialog` modal appears showing the content of the rules channel.
4. The dialog fetches messages from the rules channel via REST and renders them as BBCode (lines 57-98).
5. User clicks "I have read and agree to the rules" to dismiss.
6. `Config.set_rules_accepted(space_id)` stores the acknowledgement locally (per space, per profile).
7. On subsequent visits, the interstitial is not shown.
8. The rules channel is marked with a green icon tint and "RULES" badge in the channel list.

Note: Space rules are managed by space admins independently from the instance-wide ToS. A space can have rules even if the instance has ToS disabled, and vice versa.

### Filing a complaint / report

1. User right-clicks a message and selects "Report" (`message_view_actions.gd`, line 32).
   - Disabled for the user's own messages (line 119).
2. Or user right-clicks a member and selects "Report" (`member_item.gd`, line 113).
3. A report dialog opens (`report_dialog.gd`) with 7 category options (CSAM, Terrorism, Fraud, Hate, Violence, Self-harm, Other) and an optional description field.
4. On submission, the client sends `POST /spaces/{id}/reports` via `Client.admin.create_report()`.
5. User receives a confirmation message: "Report submitted. Thank you." The dialog auto-closes after 1.5s.
6. Admins can review reports in the Reports tab of the Server Management Panel (`server_management_reports.gd`), with filtering by status (All, Pending, Actioned, Dismissed).
7. Admins can mark reports as "Actioned" or "Dismissed" via `PATCH /spaces/{id}/reports/{rid}`.

### Server owner configuring ToS

1. Server owner opens Instance Settings (Server Management Panel > Settings tab).
2. A "Terms of Service" section shows (lines 590-620 of `server_management_panel.gd`):
   - **Enable ToS** checkbox ("Require ToS acceptance during registration").
   - **Current version** label showing the `tos_version` number.
   - **ToS Text** -- a multi-line editor pre-populated with the current/default template. Supports markdown.
   - **External URL** (optional) -- if set, overrides inline text display.
3. On save, all ToS fields are sent via `PATCH /admin/settings`. The server auto-bumps `tos_version` when `tos_text` changes (`db/settings.rs` auto-increment logic).
4. Connected users who haven't accepted the new version would be prompted on their next action (not yet implemented).

### Space admin configuring rules channel

1. Space admin opens Space Settings (`space_settings_dialog.gd`).
2. A "Rules Channel" dropdown lists all text channels in the space, plus "None" (built programmatically in `_ready()`).
3. Admin selects a channel and saves.
4. The server stores `rules_channel_id` on the space object.
5. New members selecting the space are shown the rules interstitial.

## Signal Flow

```
Registration with ToS:
  auth_dialog._set_mode(Mode.REGISTER)
    --> _fetch_tos_settings()
      --> GET /settings (public endpoint)
      --> If tos_enabled: show ToS checkbox row
  auth_dialog._on_submit() [Register mode]
    --> _validate_credentials()
      --> If _tos_enabled and not _tos_checkbox.button_pressed:
        --> "You must accept the Terms of Service."
      --> If checked: proceed with auth.register()

ToS link clicked:
  auth_dialog._on_tos_link_pressed()
    --> If _tos_url is set: OS.shell_open(_tos_url)
    --> Else: Show AcceptDialog with _tos_text as inline markdown

ToS version change (proposed):
  Client receives login response or gateway event with new tos_version
    --> Compare with last accepted version
    --> If different:
      --> Show TosUpdateDialog (modal)
        --> Fetch GET /settings for latest text
        --> User clicks "Accept"
          --> POST /users/@me/tos-accept { version }
          --> Dismiss dialog
        --> User dismisses without accepting
          --> Enter limited mode (read-only)

Space rules interstitial:
  main_window._on_space_selected(space_id)
    --> _check_rules_interstitial(space_id)
      --> Config.has_rules_accepted(space_id)? --> skip
      --> Client.get_space_by_id(space_id).rules_channel_id empty? --> skip
      --> Show rules_interstitial_dialog
        --> _fetch_rules(): REST list messages from rules_channel_id
        --> _render_messages(): markdown_to_bbcode into RichTextLabel
        --> User clicks "I have read and agree to the rules"
          --> Config.set_rules_accepted(space_id)
          --> Dismiss dialog

Report flow:
  User right-clicks message/member --> "Report"
    --> ReportDialog._on_submit()
      --> Client.admin.create_report(space_id, data)
        --> POST /spaces/{id}/reports
        --> "Report submitted. Thank you."

  Admin opens Server Management Panel > Reports tab
    --> Fetch GET /spaces/{id}/reports?status=pending
      --> Display reports with "Action" / "Dismiss" buttons
        --> PATCH /spaces/{id}/reports/{rid}
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/models/space.gd` | `rules_channel_id` field (line 29), parsed in `from_dict()` (lines 78-81), serialized in `to_dict()` (lines 140-141) |
| `scripts/autoload/client_models.gd` | `space_to_dict()` includes `rules_channel_id` in output (line 320) |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | ToS checkbox in Register mode (lines 55-72), settings fetch (lines 335-349), validation (line 152), inline viewer (lines 349-364) |
| `scenes/admin/space_settings_dialog.gd` | Rules channel dropdown selector (built in `_ready()`, populated in `setup()`, saved in `_on_save()`) |
| `scenes/admin/rules_interstitial_dialog.gd` | Code-built modal that fetches and displays rules channel messages, stores acceptance in Config |
| `scenes/main/main_window.gd` | `_check_rules_interstitial()` called on `space_selected` signal (line 516 area) |
| `scenes/sidebar/channels/channel_item.gd` | Rules channel green icon tint and "RULES" badge (lines 106-120) |
| `scenes/sidebar/channels/channel_item.tscn` | `RulesBadge` Label node (after NsfwBadge) |
| `scripts/autoload/config.gd` | `has_rules_accepted()` / `set_rules_accepted()` for per-space acceptance (after line 677) |
| `scenes/admin/server_management_panel.gd` | ToS admin settings in Settings tab: enable toggle, text editor, URL field, version display (lines 590-620) |
| `scenes/admin/report_dialog.gd` | Report submission dialog with 7 categories |
| `scenes/admin/report_list_dialog.gd` | Report review panel for admins |
| `scenes/messages/message_view_actions.gd` | "Report" option in message context menu (line 32) |
| `scenes/members/member_item.gd` | "Report" option in member context menu (line 113) |
| `addons/accordkit/rest/endpoints/reports_api.gd` | REST endpoints for report CRUD |
| `scripts/autoload/client_admin.gd` | `create_report()`, `get_reports()`, `resolve_report()` delegation (lines 528-558) |
| `../accordserver/migrations/020_tos.sql` | Migration adding `tos_enabled`, `tos_text`, `tos_version`, `tos_url` to `server_settings` |
| `../accordserver/src/models/settings.rs` | `ServerSettings` struct with ToS fields |
| `../accordserver/src/db/settings.rs` | SELECT/UPDATE queries including ToS columns, auto-bump `tos_version` on text change |
| `../accordserver/src/routes/settings.rs` | `get_public_settings` includes ToS fields for unauthenticated fetch |

## Implementation Details

### Data model support

The `AccordSpace` model (`space.gd`, line 29) has `rules_channel_id` as a nullable field. The server (`accordserver/src/models/space.rs`, line 30) stores it as `Option<String>` and the update endpoint accepts it. `ClientModels.space_to_dict()` now includes `rules_channel_id` in the UI dictionary shape (line 320).

### Instance-level ToS

The `server_settings` table in accordserver stores ToS configuration via columns added by migration `020_tos.sql`:
- `tos_enabled` (INTEGER/BOOLEAN, default true)
- `tos_text` (TEXT, seeded with default template)
- `tos_version` (INTEGER, default 1, auto-incremented when text changes)
- `tos_url` (TEXT, nullable)

The public `GET /settings` endpoint (`routes/settings.rs`) includes all four fields so unauthenticated clients can check ToS during registration. The admin `PATCH /admin/settings` endpoint accepts optional updates to all four fields.

### Registration ToS flow

The auth dialog (`auth_dialog.gd`) fetches `GET /settings` when switching to Register mode. If `tos_enabled` is true, a checkbox row appears before the submit button with a "Terms of Service" link that either opens an external URL or shows the ToS text in an inline dialog. `_validate_credentials()` enforces the checkbox before allowing registration.

### Rules channel UI

Space settings dialog dynamically builds a rules channel dropdown listing all text channels. The channel list shows a green "RULES" badge and green-tinted icon for the designated rules channel. When the user selects a space with a rules channel, `main_window._check_rules_interstitial()` checks `Config.has_rules_accepted()` and shows the `rules_interstitial_dialog` if not accepted. The dialog fetches messages from the rules channel and renders them as BBCode.

### Report system

The full complaint/report pipeline is implemented end-to-end:
- Client: `ReportDialog` (7 categories), context menu integration in message and member views
- API: `ReportsApi` with create/list/fetch/resolve endpoints
- Server: `reports` table with status tracking, permission-gated admin routes
- Admin UI: Reports tab in Server Management Panel with status filtering and action/dismiss buttons

## Implementation Status

- [x] `rules_channel_id` field in AccordSpace model (data model only)
- [x] `rules_channel_id` stored and updatable on accordserver
- [x] `rules_channel_id` passed through ClientModels to UI
- [x] Rules channel selector in space settings
- [x] Rules channel special icon (green tint) and "RULES" badge in channel list
- [x] Rules channel interstitial for new space members
- [x] Rules acceptance stored locally per space (`Config.has_rules_accepted`)
- [x] `verification_level` exposed in space settings UI
- [x] Manual moderation tools (ban, kick, timeout, message delete)
- [x] Audit log for moderation accountability
- [x] NSFW channel flag and visual indicator
- [x] ToS settings stored on accordserver (`tos_enabled`, `tos_text`, `tos_version`, `tos_url`)
- [x] Default ToS template seeded on instance creation (`020_tos.sql`)
- [x] ToS fields exposed in public settings endpoint (`GET /settings`)
- [x] ToS enable/disable toggle in instance admin panel (Settings tab)
- [x] ToS text editor in instance admin panel
- [x] ToS external URL field in admin panel
- [x] ToS version display in admin panel
- [x] Auto-bump `tos_version` when `tos_text` changes (server-side)
- [x] ToS acceptance checkbox during registration (conditional on `tos_enabled`)
- [x] ToS inline text viewer / external URL link in auth dialog
- [x] "Report Message" option in message context menu
- [x] "Report User" option in member context menu
- [x] `POST /reports` endpoint and report model
- [x] Moderation queue / report review panel for admins
- [ ] ToS version change detection and re-acceptance dialog for existing users
- [ ] `TOS_UPDATED` gateway event
- [ ] `tos_acceptances` server-side table for per-user version tracking
- [ ] `POST /users/@me/tos-accept` endpoint
- [ ] Rules interstitial re-shown when rules channel content changes
- [ ] Ban appeal flow
- [ ] `verification_level` behavioral enforcement in client

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No ToS re-acceptance on version change | High | When ToS text is updated, existing users are not prompted to re-accept. Requires `tos_acceptances` table, `POST /users/@me/tos-accept`, and a gateway event or login-time check. |
| No `TOS_UPDATED` gateway event | Medium | When admin updates ToS, connected clients are not notified. They only see changes on next registration or login. |
| No server-side ToS acceptance tracking | Medium | Server does not record which `tos_version` each user accepted. Acceptance is only tracked client-side (registration checkbox). Needs `tos_acceptances` table. |
| Rules interstitial not re-shown on content change | Medium | `Config.has_rules_accepted()` is a simple boolean per space. If the rules channel content changes, the interstitial is not re-shown. Could version-track with a hash of last-seen content. |
| No ban appeal mechanism | Medium | Banned users have no way to appeal. No appeal form, no admin review flow. |
| `verification_level` not enforced | Medium | Space settings exposes the dropdown but the value has no behavioral effect in the client. |
| ToS viewer is basic AcceptDialog | Low | The inline ToS viewer uses a plain `AcceptDialog` instead of a styled modal with markdown rendering. |
| No "Reset to Default" button for ToS | Low | Admin panel lacks a button to restore the default ToS template. Admin must manually clear and re-paste. |
