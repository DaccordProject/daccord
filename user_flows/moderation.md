# Moderation

Priority: 51
Depends on: Role-Based Permissions, Administrative User Management

## Overview

Moderation covers the full set of tools available to space admins and moderators for managing disruptive members: kicking, banning (with reasons and confirmation), unbanning (single and bulk), timeouts (communication_disabled_until), server mute/deafen, nickname editing, message deletion, audit log review, and user/message reporting. Entry points include the member list context menu, the message context menu, and the admin menus on the space banner and space icon.

User reporting is implemented on both client and server. Any space member can report a message or user via context menu, selecting a category (CSAM, terrorism, fraud, hate, violence, self-harm, other) and optional description. Reports are submitted to `POST /spaces/{id}/reports` and stored server-side. Moderators can view and resolve reports via the "Reports" admin dialog.

This document also covers illegal content moderation: server-side detection and enforcement for CSAM, terrorism/extremism propaganda, fraud/scams, hate crimes, threats of violence, and content encouraging suicide or self-harm. The server (accordserver) is responsible for scanning, classifying, and acting on illegal content. Currently, automated content scanning, automod rule engine, and NSFW age-gate are not yet implemented. The codebase has manual moderation tools, an NSFW channel flag, and user reporting.

## User Steps

### Kicking a Member
1. Right-click a member in the member list (context menu is suppressed for self, `member_item.gd` line 71).
2. "Kick" appears if the user has `kick_members` permission (line 85).
3. Click "Kick" -- a ConfirmDialog opens with danger styling: "Are you sure you want to kick [name] from this server?" (lines 148-167).
4. On confirm, `Client.admin.kick_member()` sends `DELETE /spaces/{id}/members/{uid}` (`client_admin.gd` line 215).
5. On success, member cache refreshes and gateway broadcasts `member_leave`.

### Banning a Member
1. Right-click a member in the member list.
2. "Ban" appears if the user has `ban_members` permission (line 89).
3. Click "Ban" -- a BanDialog opens with a reason input field (`ban_dialog.gd` line 12).
4. First click on "Ban" shows a summary and changes the button to "Confirm Ban" (two-step confirmation, lines 30-43).
5. Second click executes `Client.admin.ban_member()` which sends `PUT /spaces/{id}/bans/{uid}` with optional `{"reason": "..."}` (`client_admin.gd` line 228).
6. On success, member cache refreshes and `AppState.bans_updated` emits (line 233); the dialog closes and `ban_confirmed` signal fires (line 69).
7. On failure, the error is shown in-dialog and confirmation state resets (lines 56-67).

### Moderating a Member (Timeout / Mute / Deafen)
1. Right-click a member in the member list.
2. "Moderate" appears if the user has `moderate_members` permission (line 93).
3. Click "Moderate" -- a ModerateMemberDialog opens (`moderate_member_dialog.gd`).
4. The dialog shows:
   - **Duration dropdown** with preset timeout durations: 60s, 5m, 10m, 1h, 1d, 1w (lines 4-8).
   - **Mute/Deafen checkboxes** pre-filled from current member state (lines 46-47).
   - **Remove Timeout button** (visible only if user is currently timed out, line 49).
5. Clicking "Apply" sends `PATCH /spaces/{id}/members/{uid}` with `mute`, `deaf`, and optionally `communication_disabled_until` (ISO 8601 timestamp, lines 56-77).
6. Clicking "Remove Timeout" sends the same PATCH with an empty `communication_disabled_until` (lines 90-109).

### Editing a Member's Nickname
1. Right-click a member in the member list.
2. "Edit Nickname" appears if the user has `manage_nicknames` permission (line 97).
3. Click "Edit Nickname" -- a NicknameDialog opens (`nickname_dialog.gd`).
4. Enter a new nickname and click "Save", or click "Reset" to clear the nickname (lines 39-64).
5. Sends `PATCH /spaces/{id}/members/{uid}` with `{"nick": "..."}`.

### Deleting Another User's Message
1. Right-click a message in the message view.
2. "Edit" and "Delete" are enabled if the user owns the message OR has `manage_messages` permission (`message_view_actions.gd` lines 92-99).
3. Click "Delete" -- a ConfirmationDialog asks "Are you sure you want to delete this message?" (lines 61-68).
4. On confirm, `AppState.delete_message()` is called, which sends `DELETE /channels/{id}/messages/{mid}`.

### Removing All Reactions
1. Right-click a message in the message view.
2. "Remove All Reactions" is enabled if the user has `manage_messages` permission AND the message has reactions (lines 105-109).
3. Click "Remove All Reactions" -- calls `Client.remove_all_reactions()` immediately with no confirmation (lines 148-153).

### Viewing and Managing Bans
1. Open the ban list via:
   - Space icon right-click > Admin > "Bans" (requires `ban_members`, `guild_icon.gd` line 180).
   - Channel banner dropdown > "Bans" (`banner.gd` line 73).
2. BanListDialog loads bans via `Client.admin.get_bans()` with cursor-based pagination (25 per page, `ban_list_dialog.gd` lines 51-83).
3. Each ban row shows the username, reason (if any), a selection checkbox, and an "Unban" button (`ban_row.gd`).
4. Search/filter bans by username (line 114).
5. Unban a single user via the "Unban" button -- shows ConfirmDialog, then calls `Client.admin.unban_member()` (lines 174-185).
6. Select multiple bans via checkboxes, optionally "Select All" (line 132), then "Unban Selected (N)" for bulk unban with confirmation (lines 149-172).
7. `AppState.bans_updated` triggers a full ban list reload (line 194).

### Viewing the Audit Log
1. Open the audit log via space icon right-click > Admin > "Audit Log" (requires `view_audit_log`) or channel banner dropdown > "Audit Log".
2. AuditLogDialog loads entries via `Client.admin.get_audit_log()`.
3. Each row shows an action icon, performing user, action type (e.g., "Member Kick", "Member Ban Add"), target, and relative timestamp (`audit_log_row.gd`).
4. Filter by action type via dropdown: `member_kick`, `member_ban_add`, `member_ban_remove`, `member_update`, etc. (`audit_log_dialog.gd` line 111).
5. Client-side search filters rows by user name or action text.
6. Pagination loads 25 entries per page with a "Load More" button.

### Reporting a Message
1. User right-clicks a message (or long-presses on mobile).
2. "Report" appears in the context menu (index 6, `message_view_actions.gd` line 32). Disabled for own messages (line 109).
3. Click "Report" -- a ReportDialog opens (`report_dialog.gd`) with `setup_message(space_id, channel_id, message_id)` (line 33).
4. Dialog shows a category dropdown (`CATEGORIES` array, lines 8-16) with 7 options:
   - CSAM / Child exploitation
   - Terrorism / Extremism
   - Fraud / Scam
   - Hate crime / Hate speech
   - Threats of violence
   - Encouraging suicide / Self-harm
   - Other illegal content
5. User selects a category and optionally enters a description in a TextEdit field.
6. Click "Submit Report" -- `_on_submit()` (line 48) validates category selection, builds a data dictionary with `target_type: "message"`, `target_id`, `channel_id`, `category`, and optional `description`.
7. Calls `Client.admin.create_report()` which sends `POST /spaces/{id}/reports` (`client_admin.gd` line 528).
8. Server validates the category and target_type, verifies the user is a member, creates the report with a snowflake ID, and broadcasts a `report.create` gateway event with "moderation" intent (`routes/reports.rs` lines 43-96).
9. On success, dialog shows "Report submitted. Thank you." and auto-closes after 1.5 seconds (lines 81-87).
10. On failure, error message is shown and the submit button re-enables (lines 89-93).

### Reporting a User
1. Right-click a member in the member list.
2. "Report" appears in the context menu (available to all members, no permission required, `member_item.gd` line 86).
3. Click "Report" -- a ReportDialog opens with `setup_user(space_id, user_id, display_name)` (line 41 of `report_dialog.gd`).
4. Same category selection and submission flow as message reporting, but with `target_type: "user"` and no `channel_id`.

### Admin Reviewing Reports (Space-level)
1. Open the report list via:
   - Space icon right-click > Admin > "Reports" (requires `moderate_members`, `guild_icon.gd` line 194).
   - Channel banner dropdown > "Reports" (`banner.gd` line 91).
2. ReportListDialog loads reports via `Client.admin.get_reports()` with cursor-based pagination (25 per page, `report_list_dialog.gd`).
3. Filter by status: All, Pending, Actioned, Dismissed.
4. Each report row (`report_row.gd`) shows:
   - Category label (CSAM, Terrorism, etc.)
   - Target with resolved display: username for user reports, message preview with author for message reports (falls back to raw ID if not cached).
   - Reporter identity ("Reported by [username]") when `reporter_id` is present in the API response.
   - Status (color-coded: yellow=pending, green=actioned, grey=dismissed), relative timestamp, and optional description.
5. Pending reports show "Action" and "Dismiss" buttons.
6. "Action" opens a popup menu with inline moderation options:
   - **Mark Reviewed** -- resolves the report as actioned with no further action.
   - **Delete Message** -- deletes the reported message and resolves the report (message reports only).
   - **Kick User** -- kicks the reported user (or message author) with a confirmation dialog, then resolves the report.
   - **Ban User** -- bans the reported user (or message author) with a confirmation dialog, then resolves the report.
7. "Dismiss" resolves with `status: "dismissed"`.
8. `AppState.reports_updated` triggers a full report list reload.

### Server-wide Report Review (Server Admin)
1. Open via:
   - Space icon right-click > "Server Reports" (requires `is_admin`).
   - Server Management Panel > Reports tab > "Open Server-wide Reports".
2. ReportListDialog opens in server-wide mode (`setup_server_wide()`), fetching reports from all spaces the server manages.
3. Reports are sorted by `created_at` descending (newest first) across all spaces.
4. Same filtering, inline moderation, and action/dismiss flow as space-level reports.
5. Each report row's tooltip shows the originating space name.

### Automated Content Scanning (not yet implemented -- server-side)
1. User sends a message or uploads an attachment.
2. Server intercepts the content before (or immediately after) persistence.
3. Server runs content through scanning pipeline:
   - **CSAM detection**: Perceptual hash (PhotoDNA or open-source pHash/PDQ) matching against NCMEC/IWF hash databases.
   - **Terrorism content**: Keyword/regex filters + GIFCT shared hash database for known terrorist media.
   - **Fraud/scams**: URL reputation checking (Google Safe Browsing, PhishTank), known phishing pattern matching.
   - **Hate speech**: Keyword filter lists with context-aware scoring to reduce false positives.
   - **Threats of violence**: NLP classifier or keyword patterns for direct threats.
   - **Suicide/self-harm encouragement**: Keyword patterns + contextual analysis to distinguish encouragement from support/resources.
4. If content matches a rule:
   - **Auto-block**: Message is rejected before delivery (CSAM, known terrorist media).
   - **Auto-flag**: Message is delivered but flagged for moderator review (borderline cases).
   - **Auto-delete + notify**: Message is deleted and the author receives a warning.
   - **Auto-escalate**: For CSAM, server generates a CyberTipline report to NCMEC (legal obligation in many jurisdictions).
5. Server emits a gateway event (`AUTOMOD_ACTION_EXECUTED`) so connected admin clients see real-time moderation activity.

### Automod Configuration (not yet implemented)
1. Admin opens Server Settings > "AutoMod" (requires `MANAGE_SPACE` or a new `MANAGE_AUTOMOD` permission).
2. Admin enables/disables scanning categories independently.
3. Admin configures action thresholds per category (block, flag, delete, warn).
4. Admin manages custom keyword lists (allowlists, blocklists).
5. Admin configures URL allowlists for fraud/scam scanning.
6. Configuration is stored server-side per space.

## Signal Flow

```
Member list right-click
  --> member_item._show_context_menu()
        |
        +--> "Kick" --> ConfirmDialog.confirmed
        |                --> Client.admin.kick_member()
        |                     --> DELETE /spaces/{id}/members/{uid}
        |                     --> fetch_members() --> AppState.members_updated
        |
        +--> "Ban"  --> BanDialog._on_ban_pressed() (two-step)
        |                --> Client.admin.ban_member()
        |                     --> PUT /spaces/{id}/bans/{uid}
        |                     --> fetch_members() --> AppState.members_updated
        |                     --> AppState.bans_updated
        |
        +--> "Moderate" --> ModerateMemberDialog._on_apply()
        |                    --> Client.admin.update_member()
        |                         --> PATCH /spaces/{id}/members/{uid}
        |                         --> fetch_members() --> AppState.members_updated
        |
        +--> "Edit Nickname" --> NicknameDialog._on_save()
                                  --> Client.admin.update_member()
                                       --> PATCH /spaces/{id}/members/{uid}
                                       --> fetch_members() --> AppState.members_updated

Gateway events (inbound):
  ban_create   --> ClientGatewayEvents.on_ban_create()  --> AppState.bans_updated
  ban_delete   --> ClientGatewayEvents.on_ban_delete()  --> AppState.bans_updated
  member_leave --> ClientGatewayMembers.on_member_leave() --> AppState.member_left + members_updated
  member_update --> ClientGatewayMembers.on_member_update() --> AppState.members_updated

Message right-click
  --> message_view_actions.on_context_menu_requested()
        +--> "Delete" (own or manage_messages) --> ConfirmationDialog
        |      --> AppState.delete_message() --> DELETE /channels/{id}/messages/{mid}
        +--> "Remove All Reactions" (manage_messages + has reactions)
        |      --> Client.remove_all_reactions()
        +--> "Report" (disabled for own messages)
               --> ReportDialog.setup_message(space_id, channel_id, message_id)
                 --> _on_submit()
                   --> Client.admin.create_report()
                     --> POST /spaces/{id}/reports
                       --> Server creates report + broadcasts report.create (moderation intent)
                         --> Dialog: "Report submitted. Thank you."

Member list right-click --> "Report" (all members, no permission required)
  --> ReportDialog.setup_user(space_id, user_id, display_name)
    --> _on_submit()
      --> Client.admin.create_report()
        --> POST /spaces/{id}/reports

Admin menu --> "Reports" (moderate_members)
  --> ReportListDialog.setup(space_id)
    --> Client.admin.get_reports() --> GET /spaces/{id}/reports
      --> report_row "Action" / "Dismiss"
        --> Client.admin.resolve_report()
          --> PATCH /spaces/{id}/reports/{rid}
            --> AppState.reports_updated

Future (automod):
  User sends message
    --> AccordClient.messages.create() --> POST /channels/{id}/messages
      --> Server content scanner middleware
        --> Match found
          --> Auto-action (block / delete / flag)
          --> Audit log entry (action_type: "automod_block" / "automod_delete" / "automod_flag")
          --> Gateway: AUTOMOD_ACTION_EXECUTED
            --> ClientGatewayEvents.on_automod_action()
              --> AppState.automod_action.emit(data)
                --> Admin notification UI

Future (CSAM escalation):
  Server CSAM scanner detects match
    --> Content blocked (never delivered to any client)
    --> Account suspended
    --> Evidence preserved (message content, attachments, metadata, IP)
    --> CyberTipline report generated --> NCMEC API
    --> Audit log entry (action_type: "automod_csam_report")
```

## Key Files

| File | Role |
|------|------|
| `scenes/members/member_item.gd` | Member list right-click context menu with Kick/Ban/Moderate/Nickname/Role actions |
| `scenes/admin/ban_dialog.gd` | Two-step ban confirmation dialog with reason input |
| `scenes/admin/ban_list_dialog.gd` | Paginated ban list with search, single/bulk unban |
| `scenes/admin/ban_row.gd` | Individual ban row with checkbox, username, reason, unban button |
| `scenes/admin/moderate_member_dialog.gd` | Timeout duration, mute/deafen, remove timeout |
| `scenes/admin/nickname_dialog.gd` | Edit/reset member nickname |
| `scenes/admin/confirm_dialog.gd` | Reusable confirmation dialog with optional danger styling |
| `scenes/admin/audit_log_dialog.gd` | Paginated audit log viewer with action type filter |
| `scenes/admin/audit_log_row.gd` | Individual audit log entry with icon, user, action, target, time |
| `scenes/admin/channel_edit_dialog.gd` | NSFW toggle for channel editing (line 13) |
| `scenes/messages/message_view_actions.gd` | Message context menu with Delete, Remove All Reactions, and Report |
| `scenes/admin/report_dialog.gd` | Report submission dialog with category dropdown and description input |
| `scenes/admin/report_list_dialog.gd` | Paginated report list for admins with status filter and action/dismiss |
| `scenes/admin/report_row.gd` | Individual report row with category, target, status, and action buttons |
| `scenes/sidebar/channels/channel_item.gd` | NSFW visual indicator -- red tint on icon (line 74) |
| `scripts/autoload/client_admin.gd` | Admin API delegation layer: kick, ban, unban, update member, audit log, reports |
| `scripts/autoload/client_gateway_events.gd` | Gateway handlers for ban_create, ban_delete |
| `scripts/autoload/client_gateway_members.gd` | Gateway handlers for member_join, member_leave, member_update |
| `scripts/autoload/app_state.gd` | Signal bus: bans_updated, members_updated, reports_updated, member_joined, member_left |
| `addons/accordkit/models/permission.gd` | Permission constants: KICK_MEMBERS, BAN_MEMBERS, MODERATE_MEMBERS, MANAGE_MESSAGES, MANAGE_NICKNAMES |
| `addons/accordkit/models/channel.gd` | `nsfw` boolean field (line 13) |
| `addons/accordkit/rest/endpoints/bans_api.gd` | REST endpoints: list, fetch, create, remove bans |
| `addons/accordkit/rest/endpoints/reports_api.gd` | REST endpoints: create, list, fetch, resolve reports |
| `addons/accordkit/rest/endpoints/members_api.gd` | REST endpoints: list, fetch, update, kick, role management |
| `addons/accordkit/gateway/gateway_intents.gd` | `MODERATION` intent (line 4) -- no automod events defined yet |
| `scenes/sidebar/channels/banner.gd` | Channel banner admin menu entry for Bans, Audit Log, and Reports |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Space icon context menu with admin submenu for Bans, Audit Log, and Reports |

## Implementation Details

### Permission Gating

All moderation actions are permission-gated on the client side before showing menu items (`member_item.gd` lines 89-103):

- **kick_members** -- Shows "Kick" in member context menu
- **ban_members** -- Shows "Ban" in member context menu; shows "Bans" in admin menus
- **moderate_members** -- Shows "Moderate" in member context menu; shows "Reports" in admin menus
- **manage_nicknames** -- Shows "Edit Nickname" in member context menu
- **manage_messages** -- Enables Edit/Delete on other users' messages; enables "Remove All Reactions"
- **manage_roles** -- Shows role checkboxes in member context menu
- **view_audit_log** -- Shows "Audit Log" in admin menus
- *(no permission)* -- "Report" in member context menu and message context menu is available to all members

The `AccordPermission.has()` helper (line 91 of `permission.gd`) grants all permissions when `administrator` is present.

### Ban Dialog Two-Step Confirmation

The BanDialog uses a two-step confirmation pattern (`ban_dialog.gd` lines 30-43):
1. First press: locks the reason input, changes button text to "Confirm Ban", and shows a summary.
2. Second press: executes the ban API call.

On failure, the dialog resets to step 1 so the user can retry (lines 62-67).

### Timeout Calculation

The ModerateMemberDialog computes `communication_disabled_until` as an ISO 8601 UTC timestamp by adding the selected duration (from `DURATIONS` array) to the current system time (`moderate_member_dialog.gd` lines 62-73). The timestamp format is `YYYY-MM-DDTHH:MM:SSZ`.

### Ban List Pagination

The BanListDialog uses cursor-based pagination with `PAGE_SIZE = 25` (`ban_list_dialog.gd` line 6). The `_last_ban_id` tracks the cursor position (line 78), and `_has_more` controls "Load More" visibility (line 80). The server-side API accepts `limit` and `after` query parameters (`bans_api.gd` line 17).

### Bulk Unban

The bulk unban feature (`ban_list_dialog.gd` lines 149-172) iterates through selected user IDs sequentially, calling `Client.admin.unban_member()` for each. A failure counter tracks how many unbans failed and shows an error if any did. The bulk UI bar shows a "Select All" checkbox and an "Unban Selected (N)" button with count.

### Gateway Sync

Moderation actions trigger real-time updates via gateway events:
- **ban_create / ban_delete**: Handled by `ClientGatewayEvents` (lines 14-24), emit `AppState.bans_updated` so the ban list reloads.
- **member_leave**: Handled by `ClientGatewayMembers.on_member_leave()` (lines 75-96), removes the member from cache and emits `member_left` + `members_updated`.
- **member_update**: Handled by `ClientGatewayMembers.on_member_update()` (lines 98-113), updates the member cache entry and emits `members_updated`.

### Audit Log Actions

The audit log recognizes these moderation-related action types (`audit_log_row.gd` lines 3-18):
- `member_kick` -- displayed with door icon
- `member_ban_add` -- displayed with hammer icon
- `member_ban_remove` -- displayed with unlock icon
- `member_update` -- displayed with person icon
- `member_role_update` -- displayed with person icon
- `message_delete` -- displayed with speech bubble icon

### Role Hierarchy Enforcement

The member context menu disables role checkboxes for roles at or above the current user's highest role position (`member_item.gd` lines 118-123). This prevents moderators from assigning roles they shouldn't control. The `@everyone` role (position 0) is always skipped (line 110).

### Message Moderation

The message context menu (`message_view_actions.gd`) uses `Client.has_channel_permission()` with `AccordPermission.MANAGE_MESSAGES` to determine whether Edit/Delete are enabled for messages not authored by the current user (lines 92-99). This respects per-channel permission overwrites.

### Existing NSFW Infrastructure

Channels have an `nsfw` boolean field (`channel.gd`, line 13). Admins can toggle it via the channel edit dialog (`channel_edit_dialog.gd`, line 13). NSFW channels display a red-tinted icon (`channel_item.gd`, line 74). However, there is no age-gate or content warning interstitial -- users enter NSFW channels with no confirmation.

### Server-Side Scanning Architecture (proposed)

The content moderation pipeline should operate as middleware in accordserver's message handling:

1. **Pre-publish hook**: Before a message is persisted/broadcast, run it through the scanning pipeline.
2. **Attachment scanning**: For uploaded files (images, videos), compute perceptual hashes and check against known-illegal hash databases.
3. **Text analysis**: Pattern matching and optional ML classification for text content.
4. **Action dispatch**: Based on match confidence and category, execute the configured action (block, flag, delete, escalate).
5. **Gateway notification**: Emit `AUTOMOD_ACTION_EXECUTED` to admins subscribed to the `MODERATION` intent.

#### CSAM Detection

- **Legal obligation**: Many jurisdictions require platforms to detect and report CSAM. US law (18 U.S.C. 2258A) requires electronic service providers to report known CSAM to NCMEC via CyberTipline.
- **Hash matching**: Microsoft PhotoDNA (licensed) or open-source perceptual hashing (pHash, PDQ from Meta) to match against NCMEC's hash database.
- **Zero tolerance**: CSAM matches must result in immediate content blocking, account suspension, evidence preservation (message content, attachments, metadata, IP address, timestamps), and a CyberTipline report.
- **No client-side exposure**: All scanning happens server-side. The client never receives CSAM content if pre-publish blocking is active.
- **Retention**: Evidence must be preserved for law enforcement even if the account is deleted (override normal GDPR erasure for legal compliance).

#### Terrorism / Extremism Content

- **GIFCT Hash-Sharing Database**: The Global Internet Forum to Counter Terrorism maintains shared hashes of known terrorist content (images, videos).
- **Keyword lists**: Curated keyword/phrase lists for recruitment language, propaganda slogans, extremist manifestos.
- **Action**: Auto-delete + admin notification. Repeat offenders auto-banned.

#### Fraud / Scams

- **URL reputation**: Check message URLs against phishing databases (Google Safe Browsing API, PhishTank).
- **Pattern matching**: Known scam patterns (fake giveaways, credential harvesting, cryptocurrency scams, impersonation).
- **Action**: Auto-flag for review, optionally auto-delete with warning to author.

#### Hate Speech / Hate Crimes

- **Keyword filters**: Slur lists with context weighting to reduce false positives (gaming terms, reclaimed language).
- **Escalation**: Hate crime threats (combining hate speech with threats of violence) treated as high severity.
- **Action**: Auto-flag for moderator review. Clear violations auto-deleted with warning.

#### Threats of Violence

- **Pattern matching**: Direct threat patterns ("I will kill", "going to shoot", etc.).
- **Context analysis**: Distinguish hyperbole/gaming context from genuine threats.
- **Action**: Auto-flag for immediate moderator review. Credible threats may warrant law enforcement referral.

#### Suicide / Self-Harm Encouragement

- **Distinction**: Must differentiate between *encouraging* self-harm (illegal/policy violation) and *discussing* mental health or *offering support* (allowed).
- **Keyword + context**: Trigger words combined with imperative/encouraging language patterns.
- **Action**: Auto-flag for review. Optionally auto-post crisis resources (e.g., 988 Suicide & Crisis Lifeline in the US, Samaritans 116 123 in the UK).

### Report Dialog

The ReportDialog (`report_dialog.gd`) extends ModalBase and has two setup methods: `setup_message()` (line 33) for message reports and `setup_user()` (line 41) for user reports. Categories are defined as a const array of `[api_key, display_label]` pairs (lines 8-16). On submit (line 48), the dialog validates category selection, builds the request data, and calls `Client.admin.create_report()`. On success, it shows a success message and auto-closes after 1.5s (lines 81-87). On failure, the error is displayed and the button re-enables (lines 89-93).

### Report List Dialog

The ReportListDialog (`report_list_dialog.gd`) extends ModalBase and follows the same paginated list pattern as `audit_log_dialog.gd` and `ban_list_dialog.gd`. Uses cursor-based pagination with `PAGE_SIZE = 25` (line 5). Status filter dropdown with All/Pending/Actioned/Dismissed (lines 25-28). Each row connects `actioned` and `dismissed` signals (lines 95-96) which call `Client.admin.resolve_report()` (lines 115-128). Listens to `AppState.reports_updated` for real-time refresh (line 32).

### Report Row

Each report row (`report_row.gd`) shows category label (from `CATEGORY_LABELS` dict, lines 6-14), target type+ID, color-coded status (yellow=pending, green=actioned, grey=dismissed, lines 45-56), relative timestamp, and optional description. Pending reports display Action and Dismiss buttons (line 67). Emits `actioned` and `dismissed` signals (lines 3-4).

### Server-Side Reports API

The server stores reports in a `reports` table (`015_reports.sql`) with snowflake IDs, space scope, reporter/target tracking, category validation, and status lifecycle (pending -> actioned/dismissed). Four endpoints: `POST /spaces/{id}/reports` (any member), `GET /spaces/{id}/reports` (moderate_members), `GET /spaces/{id}/reports/{rid}` (moderate_members), `PATCH /spaces/{id}/reports/{rid}` (moderate_members). New reports broadcast a `report.create` gateway event with "moderation" intent.

### Client-Side Additions Still Needed

**Automod configuration panel**: New admin settings page for enabling/disabling scanning categories, configuring action thresholds, managing keyword lists.

**NSFW age-gate**: Implemented. `nsfw_gate_dialog.gd` shows a consent interstitial when first entering an NSFW channel or space. Per-server acknowledgement stored in `Config` (`[nsfw_ack]` section).

**Automod notifications**: Handle `AUTOMOD_ACTION_EXECUTED` gateway event in `client_gateway_events.gd`. Emit a new `AppState.automod_action` signal. Display a notification to online admins.

**New audit log action types**: Add icons and labels for `automod_block`, `automod_delete`, `automod_flag`, `automod_csam_report` in `audit_log_row.gd`.

**New permission**: Add `MANAGE_AUTOMOD` to `permission.gd` for configuring automod rules.

## Implementation Status

### Manual Moderation (implemented)
- [x] Kick member with confirmation dialog
- [x] Ban member with reason and two-step confirmation
- [x] Ban list with search, pagination, single unban
- [x] Bulk unban with select-all and count
- [x] Timeout member with preset durations
- [x] Remove active timeout
- [x] Server mute/deafen via moderate dialog
- [x] Edit member nickname
- [x] Delete other users' messages (with manage_messages permission)
- [x] Remove all reactions (with manage_messages permission)
- [x] Role assignment via member context menu
- [x] Role hierarchy enforcement (disable roles above own)
- [x] Audit log viewer with action type filter
- [x] Gateway sync for ban/unban/member leave/member update
- [x] Permission gating on all moderation actions
- [x] NSFW channel flag and visual indicator (red icon tint)
- [x] NSFW toggle in channel edit dialog
- [x] `MODERATION` gateway intent defined

### Reporting (implemented)
- [x] "Report Message" context menu option and dialog
- [x] "Report User" context menu option and dialog
- [x] Report submission REST endpoint (`POST /spaces/{id}/reports`)
- [x] Report list/review panel with status filter and action/dismiss
- [x] Server-side reports table with snowflake IDs, categories, and status lifecycle
- [x] Gateway broadcast of `report.create` events with moderation intent
- [x] `reports_updated` signal and real-time report list refresh
- [x] "Reports" entry in admin menus (guild icon + channel banner, requires `moderate_members`)

### Automod (not yet implemented)
- [ ] Server-side CSAM hash scanning (PhotoDNA/pHash/PDQ + NCMEC hash DB)
- [ ] NCMEC CyberTipline integration for CSAM reports
- [ ] Server-side terrorism content scanning (GIFCT hash database)
- [ ] Server-side fraud/scam URL reputation checking
- [ ] Server-side hate speech keyword filtering
- [ ] Server-side threat-of-violence detection
- [ ] Server-side suicide/self-harm encouragement detection
- [ ] Automod rule engine (server-side)
- [ ] Automod configuration UI (client-side)
- [ ] `AUTOMOD_ACTION_EXECUTED` gateway event
- [ ] Automod action notifications for admins
- [x] NSFW channel age-gate interstitial
- [ ] Crisis resource auto-response for self-harm content
- [ ] Law enforcement referral workflow for credible threats
- [ ] Automod audit log action types
- [ ] `MANAGE_AUTOMOD` permission
- [ ] Temporary ban with auto-expiry
- [ ] Message purge on ban (delete_message_seconds)
- [ ] Slow mode / rate limiting per channel
- [ ] Auto-moderation (word filters, spam detection)
- [ ] Moderation log DM notifications to actioned users
- [ ] Warning/strike system

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No server-side content scanning | High | accordserver has no scanning pipeline. All moderation is manual (reporting is manual user-initiated). |
| No NCMEC/CyberTipline integration | High | Legal requirement in the US for electronic service providers who become aware of CSAM (18 U.S.C. 2258A). Must be implemented server-side with evidence preservation. |
| No automod rule engine | High | No configurable rules for automatic content actions. Server needs a rule engine with per-space configuration. |
| Report action/dismiss has no inline moderation | Medium | The report list "Action" button marks the report as actioned but does not directly trigger a moderation action (ban, kick, delete message). Moderators must take action separately. |
| Report rows show raw IDs instead of names | Medium | `report_row.gd` displays target_id and reporter_id as raw snowflake IDs (lines 38-41). Should resolve to usernames/message previews. |
| No message purge on ban | Medium | The BanDialog sends `{"reason": "..."}` but not `delete_message_seconds`. The `bans_api.gd` create endpoint documents the parameter (line 29) but the dialog doesn't expose it. |
| No temporary ban with expiry | Medium | Bans are permanent only. No duration selector or auto-expiry mechanism exists on client or server. |
| No slow mode | Medium | No per-channel rate limiting UI or `rate_limit_per_user` field in channel settings. Server support status unknown. |
| No `AUTOMOD_ACTION_EXECUTED` gateway event | Medium | `gateway_intents.gd` defines `MODERATION` intent (line 4) but no automod-specific events exist in the gateway protocol. |
| ~~No NSFW age-gate~~ | ~~Medium~~ | Implemented. `nsfw_gate_dialog` consent interstitial gates NSFW channels and spaces. Per-server ack cached in `Config`. |
| No fraud/scam URL checking | Medium | Messages with URLs are not checked against phishing/malware databases. |
| Audit log missing automod action types | Medium | `audit_log_row.gd` action icons (lines 3-19) only cover manual actions. No `automod_block`, `automod_delete`, `automod_flag`, or `automod_csam_report` types. |
| No `MANAGE_AUTOMOD` permission | Medium | `permission.gd` has no automod-specific permission. Automod config would fall under `MANAGE_SPACE` or `ADMINISTRATOR`, which is too coarse. |
| No gateway handling for report.create on client | Medium | Server broadcasts `report.create` gateway events but the client does not yet handle them to show real-time notifications to admins. |
| No mod action DM notifications | Low | When a user is kicked/banned/timed out, they receive no DM notification explaining why. Server-side feature gap. |
| No warning/strike system | Low | No way to issue formal warnings that accumulate toward automatic action. Would need new server model and client UI. |
| Bulk unban is sequential | Low | `ban_list_dialog.gd` lines 163-166 issue unban requests one at a time. Could be parallelized for large selections, but current approach prevents overwhelming the server. |
| Remove All Reactions has no confirmation | Low | `message_view_actions.gd` line 158 executes immediately without a confirmation dialog, unlike all other destructive actions. |
| No crisis resource auto-response | Low | When self-harm content is detected, the system could auto-post crisis hotline information (988, Samaritans). |
| No transparency report tooling | Low | No mechanism for generating aggregate moderation statistics for platform transparency reports. |
| No evidence preservation override for GDPR erasure | Low | Account deletion (`DELETE /users/@me`) should not erase evidence related to pending CSAM/legal investigations. No such carve-out exists. |
| Moderate dialog uses local system time | Low | Timeout timestamp computed from `Time.get_unix_time_from_system()` (line 64 of `moderate_member_dialog.gd`). Clock skew between client and server could cause incorrect timeout durations. |
