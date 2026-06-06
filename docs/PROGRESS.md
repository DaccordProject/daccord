# Daccord Port — Progress

> **⚠️ Deprecated — remaining work now lives in GitHub issues.**
> As of 2026-06-06 the forward-looking backlog has been migrated to
> [DaccordProject/daccord-app issues](https://github.com/DaccordProject/daccord-app/issues).
> That issue tracker is the source of truth for **what's left**. This file is
> retained only as a historical record of **what's done** (the migration
> narrative below); it is no longer updated for new work. The 2026-06-06 UI
> parity audit that seeded the issue backlog is preserved in
> [Parity audit](#parity-audit-2026-06-06) for reference.
>
> Companion docs: [`technical-spec.md`](./technical-spec.md) (the plan) and the
> root [`CLAUDE.md`](../CLAUDE.md).

## Strategy recap

Port, not rewrite: keep Bonfire's Flutter UI / Riverpod / routing / theming and
swap the `firebridge` (Discord) networking layer for
[`accordkit`](https://github.com/DaccordProject/accordkit-dart). Work proceeds
**additively** — new Accord code lands alongside firebridge and must keep the
app compiling; Discord code is removed only once its Accord equivalent works.

**The bar is feature parity with the Godot reference client** at
[`../daccord`](https://github.com/DaccordProject/daccord) (see `CLAUDE.md`). The
status below is measured against that client's actual surface — which is wider
than space-messaging alone (it also ships DMs/friends, replies/threads, forum
channels, an invite/admin/discovery surface, and a plugin system). Steps 1–6
cover the core space-messaging spine; the parity gap lives in step 7, broken out
in detail below so it isn't under-counted.

## Status at a glance

| # | Migration step | Status |
|---|----------------|--------|
| 1 | Rebrand & scaffolding | 🟢 Done (names/IDs, Firebase removal, README, CI, icons) |
| 2 | Server config + auth | 🟢 Done (login/register/token/guest + MFA + forced password change + ToS + multi-account switcher; `Bearer` token-type fix) |
| 3 | Connection / event layer | 🟢 Done (spaces + channels + messages + members + reactions + typing + presence) |
| 4 | Read path (spaces → channels → messages) | 🟢 Done (read UI `/spaces`: resolved authors incl. on-demand `users.fetch`, CDN icons/avatars/images, markdown + embeds, mention highlight) |
| 5 | Write path (send/edit/delete, attachments, reactions, typing) | 🟢 Done |
| 6 | Members & roles, moderation | 🟡 Roster + presence sectioning/dots, tappable profile popout, per-member avatar overrides, moderation (kick/ban/timeout), role assignment, full role CRUD + permission grid + reorder, and space banners — all permission-gated. **Gap: no ban-list view / unban UI** (see audit) |
| 7 | **Feature parity passes** — the remaining reference-client surface (see breakdown below) | 🟡 Most sub-areas implemented; a tail of verified parity gaps remains (see [Parity audit](#parity-audit-2026-06-06)) |
| 7a | · Messaging extras — replies, threads, pinned messages, spoiler markup, media players, image lightbox | 🟡 Replies, pinned messages, spoiler markup, inline audio/video players, image lightbox, and threads done. **Gaps: no message pagination / "load older", no @mention autocomplete, no consecutive-message grouping** |
| 7b | · DMs & friends — 1:1 DMs, group DMs, friend requests/list | 🟡 1:1 DM panel (list + conversation) and friends tab (incoming/outgoing/friends, accept/decline/remove, add-friend search) done. **Gap: no group DMs** (create / add-recipient / group titles) |
| 7c | · Forum & announcement channels — forum post list/compose/view; announcement channels | 🟢 Done — forum post list/compose/view and announcement channel rendering |
| 7d | · Channel management — create/edit/delete channels, categories, per-channel permission overwrites | 🟢 Done — create/edit/delete + category grouping (manage_channels-gated) and per-channel permission overwrites (tri-state role editor) |
| 7e | · Invites — create + manage space/channel invites | 🟢 Done — space invites: create (with expiry presets), list, revoke, copy link (create_invites-gated) |
| 7f | · Admin & discovery — audit logs, user reports, transfer ownership, NSFW gate, rules interstitial, discovery panel | 🟢 Done — audit log viewer, user reports (report dialog + moderator panel), transfer ownership, NSFW gate, rules interstitial, and discovery panel all done |
| 7g | · Search — message search, user search | 🟢 Done — space-scoped message + member search dialog (debounced, tabbed); tapping a message result jumps to its channel |
| 7h | · Emoji & soundboard — full emoji picker + custom space emoji; soundboard | 🟡 Full picker (search, categories, recents), custom space emoji in reactions, and soundboard (grid play/add/delete) done. **Gap: no custom-emoji management** (admin upload / rename / delete) |
| 7i | · Settings — app settings, per-space settings, 2FA setup, self presence/status, per-channel/thread notification levels | 🟡 App settings, self presence/status picker, account settings (password change + 2FA enable/verify/disable), and per-channel mute done. **Gaps: no own-profile editing** (avatar/bio/display name), **no per-space notification levels** (all/mentions/none) |
| 7j | · Notifications — local/in-app notifications | 🟢 Done — local mention notifications via `flutter_local_notifications` |
| 8 | Retire firebridge | 🟢 Done (firebridge + firebridge_extensions deleted, legacy Discord auth/nav/voice tree removed, router stripped to Accord routes, no `discord.com`/CORS code remains) |
| – | Plugins / Lua activities (reference client feature) | ❓ Scope undecided — defer like voice, or in-scope? Needs a decision |
| 9 | Voice / video / GDExtension | ⛔ Deferred (out of scope) |

Legend: ✅ done · 🟢 complete step · 🟡 in progress · ⚪ not started · ❓ scope TBD · ⛔ deferred

---

## Parity audit (2026-06-06)

A side-by-side UI comparison of the Flutter app against the Godot reference
client (`../daccord`, `scenes/`). The core spine and most of step 7 hold up — the
items previously flagged as suspect (2FA, `||spoiler||` reveal, the self-status
presence picker) **are** actually implemented in code, so those stay 🟢. But the
audit surfaced a tail of reference-client features with **no Accord equivalent**.
Verified against the source (not just the tracker):

**Real gaps — present in the reference client, absent in the Accord UI:**

1. **Message pagination / "load older messages"** (7a) — highest impact.
   `accord_messages.dart` loads only the latest 50 (`messages.list … limit: 50`)
   with no scroll-up-to-load-more; long channels are silently truncated. The
   reference client has an older-messages loader with skeleton placeholders.
2. **@mention autocomplete** (7a) — no suggestion popup when typing `@` in the
   composer. The reference has a searchable user/role autocomplete.
3. **Consecutive-message grouping** (7a) — the reference collapses consecutive
   same-author messages (cozy/compact); the Accord `_MessageRow` renders each
   message with a full header. (Confirm before building.)
4. **Ban list view + unban** (step 6) — you can ban a member, but there's no UI
   to list existing bans or unban (`bans.list` / unban unused).
5. **Group DMs** (7b) — 1:1 DMs + friends are done; group create / add-recipient
   / group titles are not. (Already noted as deferred in 7b; re-confirmed.)
6. **Custom-emoji management** (7h) — the picker can *use* space emoji, but there
   is no admin upload / rename / delete UI (`emojis.create` / `delete` unused).
7. **Own-profile editing** (7i) — no avatar / bio / display-name editing for the
   logged-in user (`users.updateMe` unused). The reference has an editable
   profile card.
8. **Per-space notification levels** (7i) — only a per-channel mute toggle
   exists; the reference also offers space-level all/mentions/none modes.

**Reference-only admin extras (low priority, not yet triaged):** impersonation
("imposter") banner + picker, admin-driven password reset (generate reset link),
compact-vs-cozy layout toggle, guild folders, channel notification-level submenu.

**Confirmed deferred (not gaps to close now):** voice/video (step 9 ⛔, voice
channels render greyed-out + inert) and plugins / Lua activities (❓ scope still
undecided).

Suggested priority to close real gaps: (1) message pagination, (2) @mention
autocomplete, (3) ban list / unban, (4) custom-emoji management, (5) own-profile
editing. Pagination is the one users hit immediately.

---

## Stubs & placeholders in shipped Accord UI

Things a developer running the app **today** will actually encounter as
visibly-incomplete — distinct from the "not started" backlog below (which is
absent UI). Each is intentional and cross-referenced to its backlog item.

- **Voice channels — rendered but disabled.** The channel list
  (`accord_home.dart`, `_ChannelTile._glyph` / `enabled`, ~L383–405) shows voice
  channels with a `volume_up` icon but greys them out and sets `onTap: null`
  (only `text` + `forum` are tappable). Voice is deferred (step 9 ⛔); the row is
  shown-but-inert rather than hidden, so the channel list still matches the
  server's structure.
- **Forum channels — implemented (step 7c 🟢).** Forum channels render a post
  list / compose / view (`messaging/components/forum_view.dart`) rather than the
  plain text message pane.
- **DMs — implemented (step 7b 🟢).** A DM + friends panel
  (`showAccordDirectMessages`) is reachable from the space rail; `spaceId`
  remains `null` inside DM contexts (space-only permission gating is skipped
  there, as expected).
- **Mentions — body text is rendered verbatim (by design, not a stub).**
  `accord_markdown_box.dart` deliberately omits Discord's `<@id>`/`<#id>` mention
  extensions because Accord carries mentions as `AccordMessage.mentions` /
  `mentionRoles` / `mentionEveryone` **metadata**, not inline markup. Messages
  that mention you are highlighted (step 4); rendering a mention *chip* inline is
  a possible future enhancement, but there is nothing in the body to substitute.

Note: `lib/features/channels/controllers/channel.dart` and
`lib/features/events/utils/event_handler.dart` contain `TODO`s, but those are
**legacy firebridge/Discord files** (the Accord equivalents are
`accord_channels.dart` / `accord_event_handler.dart`); they retire with step 8.
The new Accord UI files have no empty `onTap`/`onPressed` handlers.

---

## What's left to do

Consolidated, prioritized backlog. (Detailed record of finished work is in
[**What's done**](#whats-done) below.)

### Step 1 — Rebrand & scaffolding 🟢
Done:
- **App display name** → "Daccord" across all platforms (Android `android:label`,
  iOS `CFBundleDisplayName`/`CFBundleName`, macOS `PRODUCT_NAME`, web
  manifest/index, Linux GTK window title + `BINARY_NAME`, Windows window title +
  `Runner.rc` version strings + `BINARY_NAME`).
- **Bundle identifiers** → `com.daccord-projects.daccord` (iOS/macOS) and
  `com.daccord_projects.daccord` (Android `applicationId`/`namespace` + moved
  `MainActivity.kt`; Linux GTK app id). Matches the reference `daccord` client.
- **Firebase push removed** — dropped `firebase_messaging`/`firebase_core` deps,
  deleted `lib/firebase_options.dart`, `notifications/controllers/firebase.dart`,
  `android/app/google-services.json`, the gradle google-services plugin (app +
  settings), the AndroidManifest firebase meta-data, and the Android push block
  in `main.dart`. `flutter_local_notifications` kept (in-app notifications,
  step 7). `notifications/controllers/notification.dart` retained but currently
  unreferenced.
- **README** rewritten for Daccord (GPLv3, port status, build steps).
- **CI** (`.github/workflows/build.yml`) — removed the OpenBonfire gh-pages
  deploy + `app.openbonfire.dev` CNAME; web now builds as an artifact; artifacts
  renamed `daccord-*`; `checkout@v2`→`v4`.
- **pubspec** `description` no longer references Discord.
- **Icons** — all launcher/app icons regenerated from the reference `daccord`
  client's 1024px master (`../daccord/assets/icons/icon_1024x1024.png`):
  `assets/images/icon.png` (launcher-icons source), Android mipmaps
  (`ic_launcher`/`launcher_icon`, all densities), iOS `AppIcon.appiconset`
  (all sizes, alpha stripped to opaque per App Store rules), macOS
  `AppIcon.appiconset` (16→1024), web `icons/` (192/512 + maskable) + `favicon`,
  and Windows `app_icon.ico` (multi-size). Splash/launch screens were unbranded
  Flutter defaults (blank), so there was nothing to replace.

Carried forward (not blocking step 1):
- **Internal Dart package name** is intentionally left as `bonfire`
  (`package:bonfire/...`, 471 imports across 133 files). Renaming is high-churn,
  unverifiable here (flutter not on PATH), and never user-visible. Revisit only
  if a full source rename is wanted.
- Regenerate platform plugin registrants (`flutter pub get` / `pod install`) so
  the stale firebase entries in generated `GeneratedPluginRegistrant.*` /
  `Podfile.lock` / `Package.resolved` are dropped. These are generated files; a
  single `flutter pub get` on the user's machine refreshes them.

### Step 2 — Auth 🟢
Login UI + router wired (credentials → MFA → connect, with restore-on-launch),
plus:
- **Register** — `AccordAuth.registerWithCredentials` (`auth.register`) behind a
  Sign In / Register toggle on the login form, with an optional display-name
  field (defaults to the username).
- **Forced password change** — when `login`/`register`/MFA returns
  `force_password_reset`, auth pauses in a new `AccordAuthPasswordResetRequired`
  state and the form shows an old/new/confirm change-password step
  (`auth.changePassword`, same token reused on success). Mirrors the reference
  client's `change_password_dialog`.
- **Token login** — "Log in with a token" toggle on the form drives the existing
  `loginWithToken` provider method.
- **Multi-account switcher** — sessions are persisted as a keyed map
  (`accounts` key in the `accord-session` box) alongside the active `session`;
  `AccountSwitcherScreen` (`/switcher`) lists saved accounts and supports switch
  (`switchTo`), add (→ `/login`, restore-on-launch is skipped while logged in),
  and remove (`removeAccount`). Reachable from the login form ("Switch account",
  shown when accounts exist) and the home rail (switch-account icon).
- **Guest browsing** — `AccordAuth.loginAsGuest` (`auth.guest` → `users.getMe`
  for the synthetic guest user → connect) behind a "Browse without account"
  button. Guest sessions are **not** persisted (transient token); guest-token
  refresh and guest-mode permission restrictions are a connection-layer
  follow-up (step 3+), matching the reference client's split.
- **Terms of Service** — on entering the Register tab the form fetches the
  server's public `/settings` (`fetchServerSettings`); when `tos_enabled`, a
  required checkbox + ToS link (URL via `url_launcher`, else inline text dialog)
  gates registration. Mirrors the reference `auth_dialog` ToS flow.
- **Password generator** — register-mode password field has a dice button
  (CSPRNG `Random.secure()`, 16 chars) plus a show/hide toggle.

**Critical correctness fix:** session `tokenType` was `'User'`, producing
`Authorization: User <token>` (and the same in the gateway IDENTIFY) — which a
real Accord server rejects. accordkit-dart interpolates `'<tokenType> <token>'`
and documents `'Bot'`/`'Bearer'`; the reference client uses `'Bearer'`
everywhere for human/guest auth. All human/guest/token sessions now mint
`'Bearer'` (`AccordSession.tokenType` default + `fromJson` fallback +
`_completeLogin`/`loginWithToken`/`loginAsGuest`/`_restClientFor`). NOTE:
`CLAUDE.md`'s AccordKit example still shows `tokenType: 'User'` — that example is
stale vs. the actual SDK; left unedited (don't modify CLAUDE.md unprompted), but
flag it.

Note: Accord has no "forgot password" / email-reset endpoint, so password reset
is the server-driven `force_password_reset` flow only. "Remove Discord auth host
& CORS proxy" (listed under step 2 in technical-spec §11) stays deferred to
step 8 — those live inside `packages/firebridge`, which is still referenced, so
removing them now would break the build (the additive strategy gates Discord
removal on firebridge retirement).

### Step 3 — Event layer 🟢
Handler covers connection lifecycle, spaces, channels, messages, members,
reactions, typing, **and presence** — every accordkit gateway stream the read
path needs is now mapped into Riverpod. Presence lands in a global per-user
`PresenceController` (seeded from the READY payload, kept current by
`onPresenceUpdate`); wiring it into the roster (online dots / online-offline
sectioning) is tracked under step 6, not here.

### Step 4 — Read path 🟢
Spaces/channels/messages/members controllers self-load and feed
`AccordHomeScreen`; authors resolve to names; CDN images, markdown, and embeds
render. Both remaining items are now done:
- **On-demand `users.fetch`** — `AccordUsersController`
  (`lib/features/user/controllers/accord_users.dart`) is a global keepAlive
  `Map<userId, AccordUser>` cache; `ensure(userId)` lazily fetches via
  `users.fetch` (deduped against in-flight + cached). `_MessagePane` author rows
  and `_TypingIndicator` fall back to it (then the raw ID) for users outside the
  loaded 100-member page; the fetch is gated on the member cache having loaded.
- **Mention highlight** — `_MessagePane` computes `mentionsMe` per message
  (`mentionEveryone` OR `mentions` contains the current user OR `mentionRoles`
  intersects the current member's roles, excluding own messages) and
  `_MessageRow` renders a primary-accent left border + tinted background.
  (Accord has *no inline mention markup* to resolve — mentions are metadata
  arrays, body text renders verbatim. See the mentions note under Markdown
  rendering.)

### Step 6 — Members & roles (write side) 🟡
Gap (see [Parity audit](#parity-audit-2026-06-06)): banning a member works, but
there is **no ban-list view / unban UI** (`bans.list` / unban unused). Done:
- **Presence sectioning** — roster groups online members by hoisted role and
  collapses all offline members into a trailing "Offline" section; online status
  dots overlay avatars (shared `AccordMemberAvatar`).
- **Per-member avatar overrides** — `accordMemberAvatarUrl` prefers
  `AccordMember.avatar` (CDN path or bare hash) over the global user avatar, used
  in the roster, popout, and message rows.
- **Tappable profile popout** — roster rows and message author avatar/name open
  `showAccordMemberPopout`, a profile dialog with avatar/name/status, "member
  since", and role chips.
- **Moderation** — kick / ban (with confirm) / timeout (preset durations +
  remove) and **role assignment** (add/remove via FilterChips), each gated by
  `accordEffectivePermissions` (instance-admin / space owner / `@everyone` + role
  perms; `administrator` implies all) and hidden on self. Optimistic cache
  updates via `removeMember` / `upsertMember`.
- **Role CRUD + permission grid** — `showAccordRoleManagement` (a master/detail
  dialog) lists roles, creates/deletes them, edits name/color/hoist/mentionable
  and the full `AccordPermission` grid, and reorders via drag (persisted with
  `client.roles.reorder`). Hierarchy is enforced through
  `accordMyHighestRolePosition`: a role is editable only when it sits strictly
  below the user's highest role and isn't integration-managed; `@everyone`
  (position 0) is editable for perms but not deletable/movable. Role gateway
  events keep `AccordSpace.roles` live (`upsertRole`/`removeRole`/`setRoles`).
- **Space banners** — `showAccordSpaceSettings` renders the banner and lets
  `manage_space` holders upload (via `AccordCDN.buildDataUri` → `spaces.update`)
  or remove it; the banner also shows atop the channel list
  (`accordSpaceBannerUrl`). The settings gear in the channel header appears only
  to members with `manage_space` or `manage_roles`, and links into role
  management.
- **Instance-admin override** — `AccordSession.isAdmin` is now persisted (set
  from `AccordUser.isAdmin` at login) and feeds the permission bypass.

### Step 7 — Feature parity passes 🟡

The remaining surface needed to match the Godot reference client
(`../daccord`). Most sub-areas 7a–7j are implemented (additively, alongside
firebridge), but a 2026-06-06 UI audit found a tail of verified parity gaps —
see [Parity audit](#parity-audit-2026-06-06) (notably message pagination,
@mention autocomplete, ban-list/unban, custom-emoji management, own-profile
editing, per-space notification levels). Code is written against the accordkit
SDK but is also **pending device verification** — flutter is not on PATH in this
environment, so build_runner / analyze / app-run have not been executed against
these changes. Broken out below by area, each annotated with its reference-client
analogue.

#### 7a — Messaging extras 🟡
The core write path plus per-message features are done, but three reference-client
behaviours are still missing — see [Parity audit](#parity-audit-2026-06-06):
**message pagination / "load older"**, **@mention autocomplete**, and
**consecutive-message grouping**. Implemented:
- **Replies** — ✅ reply composer + quoted-reply rendering.
- **Threads** — ✅ reply-count chip on messages + thread IconButton in the hover
  toolbar open `showAccordThread` (`messaging/components/thread_view.dart`).
- **Pinned messages** — ✅ pin/unpin + pinned-messages list.
- **Spoiler markup** — ✅ `||spoiler||` reveal-on-tap.
- **Media players** — ✅ inline audio/video attachment players.
- **Image lightbox** — ✅ tappable/fullscreen image viewer.

#### 7b — Direct messages & friends 🟢
✅ `showAccordDirectMessages` (`user/views/accord_direct_messages.dart`), opened
from a chat-bubble button in the space rail. Tabbed dialog:
- **Messages tab** — DM channel list (`users.listChannels`) → conversation view
  (`messages.list`/`create`, recipient-derived titles).
- **Friends tab** — incoming/outgoing/friends sections from
  `users.listRelationships`; accept/decline/remove via
  `putRelationship`/`deleteRelationship`; **Add friend** sub-dialog searches
  (`users.searchUsers`) and sends requests.
- Group DMs and unread/mention badges deferred (1:1 + friends covered).

#### 7c — Forum & announcement channels 🟢
- **Forum channels** — ✅ post list / compose / view
  (`messaging/components/forum_view.dart`).
- **Announcement channels** — ✅ announcement channel rendering.
- (Voice channels stay deferred with step 9.)

#### 7d — Channel management 🟢
- **Channel CRUD** — ✅ create/edit/delete channels and categories
  (`channels/components/channel_management.dart`, manage_channels-gated).
- **Per-channel permission overwrites** — ✅
  `showChannelPermissionsDialog` (`channels/components/channel_permissions.dart`):
  per-role tri-state (allow/neutral/deny) editor over
  `channels.listOverwrites` / `upsertOverwrite` / `deleteOverwrite`. Reached via
  a Permissions button in channel edit.
- Reorder / collapse categories deferred (CRUD + overwrites covered).

#### 7e — Invites 🟢
- ✅ Create space invites (expiry presets), list, revoke, copy link
  (create_invites-gated).

#### 7f — Admin & discovery surface 🟢
- **Audit logs** — ✅ viewer in space settings (view_audit_log-gated).
- **User reports** — ✅ `showReportDialog` (per-message report, category +
  description) and `showReportsPanel` (moderator review/resolve), both in
  `spaces/views/accord_reports.dart`.
- **Transfer ownership** — ✅ `showTransferOwnership`
  (`spaces/views/accord_transfer_ownership.dart`, typed-confirm guard).
- **NSFW gate** + **rules interstitial** — ✅ `confirmNsfwGate` /
  `maybeShowRulesInterstitial` (`spaces/views/accord_gates.dart`), session-scoped
  acknowledgment, wired into channel selection / space open.
- **Discovery panel** — ✅ `showAccordDiscovery`
  (`spaces/views/accord_discovery.dart`): debounced `directory.browse` + join.

#### 7g — Search 🟢
- ✅ Space-scoped message + member search (debounced, tabbed); message results
  jump to channel.

#### 7h — Emoji & soundboard 🟡
- **Full emoji picker** — ✅ `showAccordEmojiPicker` (search, Recent + Custom + 9
  categories, 8-col grid; recents persisted).
- **Custom space emoji** — ✅ react path via `AccordEmojisController`; reactions
  thread the `name:id` REST token and render custom emoji images.
- **Custom-emoji management** — ❌ no admin upload / rename / delete UI
  (`emojis.create` / `delete` unused). See
  [Parity audit](#parity-audit-2026-06-06).
- **Soundboard** — ✅ `showAccordSoundboard`
  (`spaces/views/accord_soundboard.dart`): grid of clips, play
  (`soundboard.play`), and add/delete (FilePicker → `soundboard.create` /
  `delete`) gated on manage_soundboard. Reached from space settings.

#### 7i — Settings 🟡
Gaps (see [Parity audit](#parity-audit-2026-06-06)): **own-profile editing**
(avatar/bio/display name, `users.updateMe` unused) and **per-space notification
levels** (all/mentions/none) are missing; only a per-channel mute exists.
Implemented:
- **App settings** — ✅ `AccordSettingsScreen` (Appearance, Notifications,
  Account, About; Hive-persisted).
- **2FA setup** — ✅ `showAccordAccountSettings`
  (`user/views/accord_account_settings.dart`): password change + 2FA
  enable/verify/disable (`auth.enable2fa`/`verify2fa`/`disable2fa`, backup-code
  display), reached from the self-status menu.
- **Self presence/status** — ✅ online/idle/dnd/invisible picker in the space
  rail (`gateway.updatePresence`).
- **Notification levels** — ✅ per-channel mute toggle (`_MuteButton`,
  `channels.mute`/`unmute`, `users.listMutes`) in the message-pane header.
- Per-space nickname deferred (banner/roles already in space settings).

#### 7j — Notifications 🟢
- ✅ done. Local mention notifications via `flutter_local_notifications`.
  `initializeNotifications()` (called from `main`) sets up the Android
  `mentions` channel + Darwin/Linux init; `showMentionNotification` is fired
  from the gateway handler's mention listener (respects `notificationsEnabled` /
  `suppressEveryone`, skips own messages and the on-screen channel via
  `accordVisibleChannelId`). No-ops on web.

### Plugins / Lua activities ❓ (scope undecided)
The reference client ships a Lua-based plugin/activity system (activity lobby,
shared multiplayer sessions, per-plugin trust). This is a large surface with no
Flutter analogue yet. **Needs an explicit scope decision** — either deferred
like voice (and stubbed/hidden), or planned as its own step. Currently neither
built nor formally deferred.

### Step 8 — Retire firebridge 🟢
Done (gh issue #11). The router was stripped to Accord-only routes (`/`, `/login`,
`/switcher`, `/register`, `/spaces`, `/settings`, `/admin`) — removing the legacy
`NavigationFrame` / `GuildMessagingOverview` shell and the `/mfa` route — which
orphaned the entire Discord component tree. With nothing live importing it, the
unreachable set (205 Dart files: the firebridge-backed `features/{voice,guild,
sidebar,me,friends,forum,overview,window}`, the Discord auth widgets
`login.dart` / `credentials.dart` / `mfa.dart` / `captcha.dart` / qr-login, and
all their `.g.dart` / `.mapper.dart` companions) was deleted, along with
`packages/firebridge` + `packages/firebridge_extensions` and their `pubspec`
entries (also dropped a stale `firebridge` dep from `packages/markdown_viewer`).
No `discord.com` hosts or CORS proxy remain (they lived inside firebridge);
Firebase push was already removed in step 1. `flutter analyze lib/` is clean
(only 2 pre-existing `onReorder` deprecation infos) and all 83 tests pass.
The optional internal package rename (`bonfire` → `daccord`) was **not** done —
it stays carried-forward (high-churn, never user-visible; see step 1).

### Deferred — Voice / GDExtension ⛔
Voice/video and GDExtension transport (`client.voiceManager`) — intentionally
out of scope. Voice UI to be hidden/stubbed, not half-wired.

---

## What's done

### Networking foundation (additive, non-breaking)

The core Accord client/auth/event spine exists and runs in parallel with
firebridge. Vertical slice implemented: **server URL → credentials/MFA login →
token persisted → gateway connect → `onReady` loads `users.listSpaces()` →
spaces rail populated**, kept in sync by space create/update/delete events.

New files:

| File | Role | firebridge analogue |
|------|------|---------------------|
| `lib/features/server/models/accord_server.dart` | `AccordServer` connection config (base/gateway/cdn URLs; `fromBaseUrl()` derives `wss://host/ws` + `<base>/cdn`) | hardcoded `discord.com` hosts |
| `lib/features/authentication/models/accord_session.dart` | `AccordSession` — server + token + user, JSON-persistable | `auth` Hive box token |
| `lib/features/authentication/models/accord_auth.dart` | `AccordAuthState` sealed union (logged-out / in-progress / MFA-required / logged-in / failed) | `AuthResponse` union |
| `lib/features/authentication/repositories/accord_auth.dart` | **`AccordAuth`** provider — owns the live `AccordClient`; `loginWithCredentials` → `submitMfa` → connect, plus `loginWithToken`, `restoreSession`, `logout` | `Auth` provider |
| `lib/features/events/controllers/connection.dart` | `ConnectionController` + `ConnectionStatus` enum | (connection state was implicit) |
| `lib/features/events/utils/accord_event_handler.dart` | `handleAccordEvents(ref, client)` — gateway streams → connection state + space cache | `handleEvents` / `event_handler.dart` |
| `lib/features/spaces/controllers/spaces.dart` | `SpacesController` — the rail list | `GuildsController` |
| `lib/features/spaces/controllers/space.dart` | `SpaceController(spaceId)` — per-space cache | `GuildController` |

Edits to existing files:

- `pubspec.yaml` — added `accordkit` git dependency.
- `lib/features/authentication/utils/hive.dart` — added `accord-session` box.

Tests:

- `test/accord_server_test.dart` — URL derivation + session JSON round-trip.

### Auth wired into UI + router (first intentional breaking change)

The app now boots the **Accord** login flow instead of Discord's `LoginScreen`.

| File | Role | replaces |
|------|------|----------|
| `lib/features/authentication/views/accord_login.dart` | `AccordLoginScreen` — server-URL + credentials form, MFA step, error display, restore-on-launch loader; drives `accordAuthProvider` and, on `AccordAuthLoggedIn`, navigates to the Accord home (`/spaces`) | Discord `LoginScreen` / `PlatformLoginWidget` |
| `lib/router/controller.dart` | `/`, `/login`, `/register` now build `AccordLoginScreen` | `LoginScreen` |

- Login form persists the last server URL (`accord-session` box, `last-server`
  key) and prefills it next launch.
- On launch, `restoreSession()` runs; a stored session reconnects straight into
  `/spaces` without re-prompting.
- The old Discord `login.dart` / `credentials.dart` (webview) / `mfa.dart`
  remain in the tree (now unused by the router) until firebridge retirement.

### Read-path controllers (channels + messages)

Self-loading Riverpod family controllers + gateway wiring. Both load lazily on
first watch (once logged in) and stay in sync via gateway events. Consumed by
`AccordHomeScreen` (next section).

| File | Role | firebridge analogue |
|------|------|---------------------|
| `lib/features/channels/controllers/accord_channels.dart` | `AccordChannelsController(spaceId)` — a space's channel list; loads via `spaces.listChannels`, sorted by `position` | channel repositories |
| `lib/features/messaging/controllers/accord_messages.dart` | `AccordMessagesController(channelId)` — a channel's recent history (oldest→newest); loads via `messages.list` (limit 50). Exposes `activeMessageChannels` so the handler only mutates opened caches | `messages` repository |
| `lib/features/events/utils/accord_event_handler.dart` | now also routes `onChannelCreate/Update/Delete` → channels controller and `onMessageCreate/Update/Delete` → messages controller | `handleEvents` |

### First Accord-native read UI (`/spaces`)

A self-contained three-pane read view, consuming the controllers above. It does
**not** reuse the firebridge `NavigationFrame` / `Sidebar` (those are coupled to
`UserGuild` / `Snowflake` / DMs / folders); instead it's a fresh scaffold the
firebridge widgets will be migrated onto.

| File | Role |
|------|------|
| `lib/features/spaces/views/accord_home.dart` | `AccordHomeScreen` — space rail (`spacesControllerProvider`) → channel list (`accordChannelsControllerProvider`) → message list (`accordMessagesControllerProvider`). Local selection state; auto-selects first space + first text channel. Logout button; redirects to `/` when auth drops. |
| `lib/router/controller.dart` | new `/spaces` route building `AccordHomeScreen` |
| `lib/features/authentication/views/accord_login.dart` | post-login nav now targets `/spaces` (was `/channels/...`) |

### Member/user cache (authors resolve to names + avatars)

Message authors no longer render as raw IDs. A per-space member cache resolves
`authorId` to a name (nickname → display name → username → raw ID fallback) and
an initial avatar.

| File | Role | firebridge analogue |
|------|------|---------------------|
| `lib/features/member/controllers/accord_members.dart` | `AccordMembersController(spaceId)` — a space's members as a `Map<userId, AccordMember>` for O(1) author lookup. Self-loads via `members.list` (limit 100). Exposes `activeMemberSpaces` so the handler only mutates opened caches | member repositories |
| `lib/features/events/utils/accord_event_handler.dart` | now also routes `onMemberJoin/Update` → upsert and `onMemberLeave` → remove, gated on `activeMemberSpaces` | `handleEvents` |
| `lib/features/spaces/views/accord_home.dart` | `_MessagePane` watches `accordMembersControllerProvider(spaceId)`; `_MessageRow` shows resolved name + initial `CircleAvatar` | message author rendering |

### Write path — send / edit / delete

The `/spaces` message pane has a working composer plus per-message edit and
delete (gated to the current user's own messages via `session.userId`). All
three call REST and update the cache **after** the call succeeds (not
optimistically); the gateway echo (`onMessageCreate/Update/Delete`) is then a
dedup/no-op. (Reactions, below, are the only genuinely optimistic write.)

| File | Role |
|------|------|
| `lib/features/messaging/controllers/accord_messages.dart` | `send` → `messages.create`; `edit` → `messages.edit`; `delete` → `messages.delete`, each mutating the cache after the REST call succeeds |
| `lib/features/spaces/views/accord_home.dart` | `_Composer` (multiline `TextField`, send-on-enter); `_MessageRow` is a `ConsumerStatefulWidget` with hover-revealed `_MessageActions` (⋯ → Edit/Delete), inline edit field, delete-confirm dialog, and an "(edited)" marker |

### Attachments

The composer can attach files; sending routes through `createWithAttachments`
(multipart upload) when files are present, else the plain `send`.

| File | Role |
|------|------|
| `lib/features/messaging/controllers/accord_messages.dart` | `sendWithAttachments(client, content, files)` → `messages.createWithAttachments` (multipart `/messages/upload`); falls back to `send` when no files; appends the created message after upload succeeds |
| `lib/features/spaces/views/accord_home.dart` | `_Composer` paperclip button → `FilePicker.platform.pickFiles(allowMultiple, withData)`; pending files shown as removable `_AttachmentChip`s; `_send` builds `{filename, content (bytes), content_type}` (via an extension→MIME map) and routes accordingly, clearing on success |

### Reactions (read + write)

Messages render reaction pills and support toggling. Optimistic add/remove,
reverted on REST failure; the four reaction gateway events keep aggregate counts
in sync (gated to opened channels via `activeMessageChannels`).

| File | Role |
|------|------|
| `lib/features/messaging/controllers/accord_messages.dart` | `toggleReaction` (add/`removeOwn` based on `includesMe`); `applyReaction`/`clearReactions`/`clearReactionEmoji` mutate aggregate `AccordReaction` counts (used by both optimistic toggles and gateway echoes) |
| `lib/features/events/utils/accord_event_handler.dart` | wires `onReactionAdd/Remove/Clear/ClearEmoji`; computes `isOwn` from `session.userId` so own vs. others' reactions update `includesMe` correctly |
| `lib/features/spaces/views/accord_home.dart` | `_ReactionPill` (emoji/custom-emoji image + count, highlighted when `includesMe`, tap to toggle); `_ReactButton` in the hover toolbar opens the full `showAccordEmojiPicker` |

### Typing indicator

A per-channel typing indicator: the composer broadcasts typing while you write,
and a line above the composer shows who else is typing.

| File | Role |
|------|------|
| `lib/features/messaging/controllers/typing.dart` | `TypingController(channelId)` — holds typing user IDs, each on a 10s self-expiring timer (`generated .g.dart`) |
| `lib/features/events/utils/accord_event_handler.dart` | wires `onTypingStart` → `userTyping` (gated to opened channels; skips our own `session.userId`) |
| `lib/features/spaces/views/accord_home.dart` | `_Composer` POSTs `messages.typing` throttled to once / 8s while typing; `_TypingIndicator` resolves IDs → names via the member cache ("X is typing…" / "X and Y…" / "Several people…") |

### Presence cache (global per-user status)

The last gateway stream needed by the read path. A global, per-user presence
cache mirrors the reference client's `_user_cache[...]["status"]` model — one
presence per user, independent of how many spaces you share — rather than a
per-space store. Seeded from the READY payload, kept current by
`presence.update`. No UI yet (online dots / roster sectioning are step 6); this
is the event-layer plumbing only.

| File | Role | reference analogue |
|------|------|--------------------|
| `lib/features/events/controllers/presence.dart` | `PresenceController` — keepAlive Notifier holding `Map<userId, AccordPresence>`; `upsert` (single update) + `seed` (replace from READY). Top-level `accordPresenceStatus(map, userId)` resolves a status string, defaulting to `'offline'` (the gateway only pushes presence for non-offline users) | `client._user_cache[uid]["status"]` |
| `lib/features/events/utils/accord_event_handler.dart` | `onReady` now calls `_seedPresences` (parses `ready['presences']` → `AccordPresence.fromJson`); new `onPresenceUpdate` → `upsert` | `_apply_presences` / `on_presence_update` in `client_gateway.gd` |

The `presences` gateway intent was already requested at connect time, so no
auth change was needed. Hand-written `.g.dart` regenerated clean by build_runner.

### CDN images (space icons, avatars, inline image attachments)

The `/spaces` UI renders real images from the server's CDN, falling back
gracefully (initials / 📎 chip) when an asset is absent or fails to load. CDN
URLs are built with accordkit's `AccordCDN` helper against the logged-in
session's `server.cdnUrl`.

| File | Role |
|------|------|
| `lib/features/spaces/views/accord_home.dart` | Top-level helpers `_spaceIconUrl` / `_avatarUrl` (each handles both a bare asset **hash** → `AccordCDN.spaceIcon`/`avatar` and a path/absolute URL → `AccordCDN.resolvePath`, with `autoFormat` for `a_`-animated hashes) and `_attachmentUrl` / `_isImageAttachment` / `_asDouble`. `_SpaceIcon` shows the space icon (`CachedNetworkImage`, initials placeholder/error fallback); `_MessageRow`'s `CircleAvatar` uses `foregroundImage: CachedNetworkImageProvider` so the initial shows through on load/failure; image attachments render via the `_ImageAttachment` widget (aspect-preserving, max 400×350, spinner placeholder, broken-image error), non-images keep the 📎 filename. CDN URL read once in `AccordHomeScreen.build` (`session.server.cdnUrl`) and threaded to the rail; `_MessageRow` reads it via `accordAuthProvider.select`. |

Uses the existing `cached_network_image` dep.

### Markdown message rendering

Message bodies render as markdown (bold/italic, lists, headings, links, fenced
code with Prism syntax highlighting) instead of plain text — the first
firebridge-widget fold-in onto the `/spaces` scaffold.

| File | Role | firebridge analogue |
|------|------|---------------------|
| `lib/features/messaging/components/box/accord_markdown_box.dart` | `AccordMarkdownBox({required String content})` — reuses the kept `markdown_viewer` stack: `getMarkdownStyleSheet` + `flutter_prism` `highlightBuilder` + `url_launcher` `onTapLink`; `selectable` on desktop. Takes a plain string (not a firebridge `Message`) and **omits** the Discord mention extensions | `MessageMarkdownBox` (firebridge `Message`-coupled, `DiscordMentionSyntax`/`Builder`) |
| `lib/features/spaces/views/accord_home.dart` | `_MessageRow` renders content via `AccordMarkdownBox` in place of the old `Text(_message.content)` |

`markdown_viewer` / `flutter_prism` / `url_launcher` / `google_fonts` are all
existing deps (no `pubspec` change).

> **Note on mentions:** there is **no inline mention markup to resolve** in
> Accord. Unlike Discord's `<@id>`/`<#id>` tokens, the Accord protocol carries
> mentions as separate `AccordMessage.mentions` / `mentionRoles` /
> `mentionEveryone` metadata; the reference client renders the body text
> verbatim (markdown only) and uses those arrays solely for highlight /
> notification logic. So the firebridge `DiscordMentionSyntax`/`Builder` are not
> ported — there's nothing in the body to substitute. (A future enhancement,
> tracked under step 6, could *highlight* a message when `mentions` includes the
> current user.)

### Rich embeds

Message embeds render as cards beneath the body, mirroring the Godot reference
client's `embed.tscn`.

| File | Role | reference analogue |
|------|------|--------------------|
| `lib/features/messaging/components/box/accord_embed_box.dart` | `AccordEmbedBox({required AccordEmbed embed, String? cdnUrl})` — accent left-border card with optional author (icon + linked name), linked title, markdown description (via `AccordMarkdownBox`), fields (`_EmbedFields`, inline-grouped 3-per-row), image, thumbnail, and footer. Defensive accessors handle the loosely-typed embed model (image/thumbnail as bare URL **or** `{url}`; footer as string **or** `{text}`; color as RGB int). Images via `CachedNetworkImage`, links via `url_launcher` | `scenes/messages/embed.gd` |
| `lib/features/spaces/views/accord_home.dart` | `_MessageRow` renders `for (final embed in _message.embeds) AccordEmbedBox(...)` after attachments, before reactions |

Limitations: embed `timestamp` not shown; video-type embeds render as a static
image (no play overlay); fields assume well-formed maps.

### Member roster pane (role grouping + role-colored names)

A right-hand member roster renders on `/spaces`, grouping the space's cached
members by role and coloring names by role — the Accord analogue of Bonfire's
firebridge `MemberList`/`MemberScrollView`, but driven by the
`AccordMembersController` cache rather than Discord's lazy sync-range list.

| File | Role |
|------|------|
| `lib/features/member/utils/member_display.dart` | Shared, widget-free helpers: `accordMemberName` (nickname → display → username → fallback), `accordAvatarUrl` (bare-hash → `AccordCDN.avatar`, OR path/URL → `resolvePath`), `accordRoleColor` (RGB int → `Color`, `0` = none), `memberColorRole` / `memberHoistRole` (highest-positioned colored / hoisted role for a member). The single source for name/avatar/role-color logic across the message list and roster. |
| `lib/features/member/views/accord_member_list.dart` | `AccordMemberList({String? spaceId})` — 240px right pane. Groups members under their highest hoisted role into sections sorted by role position descending (ungrouped members fall into a trailing "Members" bucket); each section header shows `LABEL — count`; rows show a CDN avatar (initial fallback) and a name tinted by `memberColorRole` + `accordRoleColor`. Roles come from `AccordSpace.roles` via `spacesControllerProvider.select`. |
| `lib/features/spaces/views/accord_home.dart` | Renders `AccordMemberList(spaceId: …)` as the Row's right pane; `_MessagePane` also colors message author names via `memberColorRole`/`accordRoleColor`. The local `_avatarUrl` / `_authorName` / typing name-resolution were refactored onto the shared `member_display.dart` helpers (de-duplicated). |

### On-demand user cache + mention highlight (step 4 closeout)

The two remaining read-path gaps. Authors/typers outside a space's loaded
100-member page now resolve to real names/avatars, and messages that mention the
current user are visually highlighted.

| File | Role |
|------|------|
| `lib/features/user/controllers/accord_users.dart` | `AccordUsersController` — global keepAlive `Map<userId, AccordUser>` cache. `ensure(userId)` schedules a deduped one-time `client.users.fetch` (skips cached + in-flight IDs) and, on success, appends to the map so watchers rebuild. Safe to call during widget build (cache mutates only after the request completes). Hand-written `.g.dart`, regenerated clean by build_runner. |
| `lib/features/member/utils/member_display.dart` | new `accordUserName(AccordUser?, fallback)` (display name → username → fallback) for bare users with no `AccordMember`. |
| `lib/features/spaces/views/accord_home.dart` | `_MessagePane` watches `accordUsersControllerProvider`; per message, when the author isn't in the (loaded) member cache it reads the user cache and `ensure`s a fetch, passing `authorUser` to `_MessageRow` (name + avatar fall back through member → user → raw ID). `_TypingIndicator.nameFor` does the same. Mention highlight: `_MessagePane` computes `mentionsMe` (`mentionEveryone` ∨ `mentions`∋me ∨ `mentionRoles`∩ my member roles, minus own messages) and `_MessageRow` wraps the row in a primary-accent left-border + tinted `Container` when set. |

---

## Notes / gotchas

- **Codegen:** Riverpod `*.g.dart` files are committed. After changing any
  `@riverpod`/`@freezed`/mappable file, run
  `flutter pub get && dart run build_runner build -d`. The foundation's
  `.g.dart` files were authored by hand and should be regenerated to get correct
  source-hashes.
- **Dependency resolution:** watch for a possible `web_socket_channel` / `http`
  version clash between `accordkit` and `firebridge` during `pub get`; resolve
  with a `dependency_overrides` entry if it surfaces.
- **Discord coupling removed (step 8 🟢):** `packages/firebridge` +
  `firebridge_extensions` and the unused Discord auth/nav/voice widgets are
  deleted, so the `discord.com` hosts and CORS proxy that lived inside them are
  gone. Firebase push was removed in step 1. No runtime dependency on Discord
  remains.
