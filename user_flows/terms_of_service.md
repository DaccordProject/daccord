# In-App Terms of Service

Priority: 55
Depends on: None

## Overview

Server owners can define custom Terms of Service (ToS) for their instance, or disable ToS entirely. When enabled, users must accept the ToS during registration and when it changes. daccord ships with sensible default ToS text that server owners can use as-is, customize, or replace completely.

Currently, daccord has no ToS display, no acceptance flow, and no complaint process. The data model partially supports a rules channel (`rules_channel_id` on `AccordSpace`), but this is not surfaced in the UI or wired through `ClientModels`.

## Design Principles

1. **Server-owner controlled** -- The ToS is configured per-instance by the server owner (super admin), not hardcoded by daccord.
2. **Opt-out** -- Server owners can disable ToS entirely (e.g. for private friend groups or development instances). When disabled, no acceptance checkbox or interstitial appears.
3. **Good defaults** -- daccord provides a default ToS template covering common-sense rules (no harassment, no illegal content, no spam). Server owners can use the defaults, edit them, or write their own from scratch.
4. **Space-level rules are separate** -- Instance-wide ToS (managed by the server owner) is distinct from per-space rules (managed by space admins via `rules_channel_id`). Both can coexist.

## Server-Side Configuration

The server owner configures ToS via the instance settings API (or a config file on the server):

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `tos_enabled` | `bool` | `true` | Whether ToS is active. When `false`, registration skips ToS and no acceptance is required. |
| `tos_text` | `string` | (default template) | Markdown-formatted ToS body. Server owner can edit or replace entirely. |
| `tos_version` | `int` | `1` | Bumped by the server owner when ToS text changes. Triggers re-acceptance for existing users. |
| `tos_url` | `string?` | `null` | Optional external URL. When set, the client links to this URL instead of displaying `tos_text` inline. |

### Default ToS Template

When a new accordserver instance is created, `tos_text` is populated with a default template:

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

The server owner can edit this text from the instance admin panel or replace it entirely. Setting `tos_enabled = false` hides all ToS UI.

## User Steps

### Accepting ToS during registration (not yet implemented)

1. User opens the auth dialog in Register mode (`auth_dialog.gd`).
2. Client fetches `GET /instance/tos` to check if ToS is enabled.
3. **If ToS is disabled:** No checkbox appears. Registration proceeds normally.
4. **If ToS is enabled:**
   a. A ToS checkbox appears: "I agree to the Terms of Service".
   b. "Terms of Service" is a clickable link that opens a scrollable ToS dialog (rendering `tos_text` as markdown) or opens `tos_url` in the browser.
   c. User checks the box, enabling the Register button.
   d. On registration, the server records the `tos_version` accepted and a timestamp.
   e. The auth token response includes `tos_accepted: true` and `tos_version`.

### Re-accepting ToS after an update (not yet implemented)

1. User logs in or is already connected.
2. Client receives a gateway event or login response indicating `tos_version` has changed since last acceptance.
3. A modal dialog appears: "The Terms of Service have been updated. Please review and accept to continue."
4. The dialog shows the updated `tos_text` (or links to `tos_url`) with an "Accept" button.
5. User clicks "Accept". Client sends `POST /users/@me/tos-accept { version }`.
6. If the user dismisses without accepting, the client remains in a limited state (can view but not send messages) until they accept.

### Viewing space rules (not yet implemented)

1. User joins a space that has a `rules_channel_id` set.
2. Before accessing other channels, a rules interstitial appears showing the content of the rules channel.
3. User clicks "I have read and agree to the rules" to dismiss.
4. The client records acceptance locally (per space, per profile).
5. On subsequent visits, the interstitial is not shown unless the rules channel content has been updated.
6. Users can revisit the rules channel at any time from the channel list (marked with a special icon).

Note: Space rules are managed by space admins independently from the instance-wide ToS. A space can have rules even if the instance has ToS disabled, and vice versa.

### Filing a complaint / appeal (not yet implemented)

1. User right-clicks a message or member and selects "Report" (not yet in context menu).
2. A report dialog opens with category selection and description field.
3. On submission, the client sends `POST /reports` with message/user ID, category, and description.
4. User receives a confirmation toast.
5. For ban appeals, a separate flow:
   - Banned user sees a "You are banned from [space]" screen with an optional "Appeal" button.
   - Appeal form collects a reason text and sends it to space admins.
   - Admins see appeals in the moderation queue alongside reports.

### Server owner configuring ToS (not yet implemented)

1. Server owner opens Instance Settings (super admin panel).
2. A "Terms of Service" section shows:
   - **Enable ToS** toggle (on/off).
   - **ToS Text** -- a multi-line editor pre-populated with the default template. Supports markdown.
   - **External URL** (optional) -- if set, overrides inline text display.
   - **Reset to Default** button -- restores the default template.
3. On save, the server bumps `tos_version` automatically if `tos_text` changed.
4. Connected users who haven't accepted the new version are prompted on their next action.

### Space admin configuring rules channel (not yet implemented)

1. Space owner opens Space Settings (`space_settings_dialog.gd`).
2. A "Rules Channel" dropdown lists all text channels in the space.
3. Admin selects a channel and saves.
4. The server stores `rules_channel_id` on the space object.
5. New members joining the space are shown the rules interstitial.

## Signal Flow

```
Registration with ToS (proposed):
  auth_dialog._on_submit() [Register mode]
    --> Fetch GET /instance/tos
    --> If tos_enabled == false: proceed normally (no checkbox shown)
    --> If tos_enabled == true:
      --> Check _tos_checkbox.button_pressed
      --> If unchecked: show error "You must accept the Terms of Service"
      --> If checked: proceed with auth.register({..., tos_version: <version>})
        --> Server records acceptance

ToS version change (proposed):
  Client receives login response or gateway event with new tos_version
    --> Compare with last accepted version
    --> If different:
      --> Show TosUpdateDialog (modal)
        --> Fetch GET /instance/tos for latest text
        --> User clicks "Accept"
          --> POST /users/@me/tos-accept { version }
          --> Dismiss dialog
        --> User dismisses without accepting
          --> Enter limited mode (read-only)

Space rules interstitial (proposed):
  Client.connect_server() --> space joined
    --> Check rules_channel_id != null
    --> Check local acceptance record (Config)
    --> If not accepted:
      --> Show RulesInterstitialDialog
        --> Fetch messages from rules_channel_id
        --> User clicks "Accept"
          --> Config.set_rules_accepted(space_id, rules_version)
          --> Dismiss interstitial

Report flow (proposed):
  User right-clicks message --> "Report"
    --> ReportDialog._on_submit()
      --> AccordClient sends POST /reports {message_id, category, description}
        --> Server queues report
        --> Toast: "Report submitted"

  Admin opens Moderation Queue
    --> Fetch GET /reports?status=pending
      --> Display reports with action buttons
        --> Admin takes action (delete/warn/timeout/ban/dismiss)
          --> Audit log entry created
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/models/space.gd` | `rules_channel_id` field (line 29), parsed in `from_dict()` (lines 78-81), serialized in `to_dict()` (lines 140-141) |
| `scripts/autoload/client_models.gd` | Converts AccordSpace to UI dictionary -- does NOT pass `rules_channel_id` (line 255 area) |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Registration flow -- no ToS checkbox (lines 83-91 show Register mode setup) |
| `scenes/admin/space_settings_dialog.gd` | Space settings -- has verification_level but no rules_channel_id selector |
| `scenes/messages/message_view_actions.gd` | Message context menu -- no "Report" option (line 25 area) |
| `scenes/members/member_item.gd` | Member context menu -- no "Report" option (lines 82-99) |
| `scenes/main/welcome_screen.gd` | First-run welcome -- no ToS reference |
| `scripts/autoload/config.gd` | Per-profile config -- could store rules acceptance state |
| `addons/accordkit/models/channel.gd` | Channel model with `nsfw` field for content gating |
| `scenes/sidebar/channels/channel_item.gd` | Channel list item -- could show rules channel icon |

## Implementation Details

### Existing data model support

The `AccordSpace` model (`space.gd`, line 29) already has `rules_channel_id` as a nullable field. The server (`accordserver/src/models/space.rs`, line 30) stores it as `Option<String>` and the update endpoint accepts it. However:

- `ClientModels.space_to_dict()` does not include `rules_channel_id` in the UI dictionary shape (line 255 area of `client_models.gd`).
- `space_settings_dialog.gd` does not expose a rules channel selector.
- No code anywhere reads `rules_channel_id` to trigger a rules interstitial or mark the channel specially.

### Instance-level ToS (new)

The accordserver would need:

- A `tos` table or config store with `enabled`, `text`, `version`, and `url` fields.
- `GET /instance/tos` -- public endpoint returning the current ToS (or `{ enabled: false }`).
- `PATCH /instance/tos` -- super admin endpoint to update ToS settings.
- A `tos_acceptances` table tracking `user_id`, `version`, `accepted_at`.
- `POST /users/@me/tos-accept` -- records acceptance of a specific version.
- Registration endpoint checks `tos_enabled` and requires `tos_version` in the request body when enabled.
- Gateway event `TOS_UPDATED` broadcast when ToS version changes.

### Registration flow gap

The auth dialog (`auth_dialog.gd`) handles both sign-in and register modes (line 9). In Register mode (lines 83-91), it shows a display name input and password generator but no ToS checkbox. The `_validate_credentials()` method (lines 143-150) checks for empty username/password and minimum password length, but not ToS acceptance. The dialog would need to fetch `/instance/tos` on open and conditionally show the checkbox.

### Complaint process gap

Neither the message context menu (`message_view_actions.gd`) nor the member context menu (`member_item.gd`) has a "Report" option. There is no `POST /reports` endpoint in AccordKit or accordserver. There is no report model, no moderation queue UI, and no appeal flow. This gap is also documented in `illegal_content_moderation.md` and `moderation.md`.

## Implementation Status

- [x] `rules_channel_id` field in AccordSpace model (data model only)
- [x] `rules_channel_id` stored and updatable on accordserver
- [x] `verification_level` exposed in space settings UI
- [x] Manual moderation tools (ban, kick, timeout, message delete)
- [x] Audit log for moderation accountability
- [x] NSFW channel flag and visual indicator
- [ ] `GET /instance/tos` and `PATCH /instance/tos` endpoints on accordserver
- [ ] `tos_acceptances` table and `POST /users/@me/tos-accept` endpoint
- [ ] Default ToS template seeded on instance creation
- [ ] ToS enable/disable toggle in instance admin panel
- [ ] ToS text editor in instance admin panel
- [ ] ToS acceptance checkbox during registration (conditional on `tos_enabled`)
- [ ] ToS version change detection and re-acceptance dialog
- [ ] `TOS_UPDATED` gateway event
- [ ] Rules channel interstitial for new space members
- [ ] Rules channel selector in space settings
- [ ] `rules_channel_id` passed through ClientModels to UI
- [ ] Rules channel special icon in channel list
- [ ] "Report Message" option in message context menu
- [ ] "Report User" option in member context menu
- [ ] `POST /reports` endpoint and report model
- [ ] Moderation queue / report review panel for admins
- [ ] Ban appeal flow

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No instance-level ToS configuration | High | No `GET /instance/tos` endpoint, no admin UI to edit ToS text, no enable/disable toggle. Server owners cannot set terms for their instance. |
| No ToS acceptance during registration | High | `auth_dialog.gd` Register mode (lines 83-91) has no checkbox. Even when ToS exists, users create accounts with no agreement. |
| No ToS re-acceptance on version change | High | When ToS text is updated, existing users are not prompted to re-accept. No `tos_version` tracking per user. |
| No complaint / report flow | High | No "Report" option in context menus. No `POST /reports` endpoint. No moderation queue. See also `moderation.md` and `illegal_content_moderation.md`. |
| `rules_channel_id` not wired to UI | High | Field exists in data model (`space.gd` line 29) and server but `ClientModels` doesn't pass it through, space settings doesn't expose it, and no interstitial reads it. |
| No rules interstitial for new members | High | When a space has `rules_channel_id` set, new members should see the rules before chatting. No such flow exists. |
| No ban appeal mechanism | Medium | Banned users have no way to appeal. No appeal form, no admin review flow. |
| `verification_level` not enforced | Medium | Space settings exposes the dropdown (`space_settings_dialog.gd` lines 31-34) but the value has no behavioral effect in the client. |
