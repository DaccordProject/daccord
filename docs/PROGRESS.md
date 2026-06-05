# Daccord Port — Progress

> Status tracker for the Bonfire → Daccord migration. Companion to
> [`technical-spec.md`](./technical-spec.md) (the plan) and the root
> [`CLAUDE.md`](../CLAUDE.md). Last updated: 2026-06-05 (member/user cache +
> write path: send/edit/delete + attachments + reactions + typing; CDN
> images: space icons, author avatars, inline image attachments; markdown
> message rendering + rich embeds; **member roster pane with role grouping +
> role-colored names**; analyzer-clean, Flutter 3.44).

## Strategy recap

Port, not rewrite: keep Bonfire's Flutter UI / Riverpod / routing / theming and
swap the `firebridge` (Discord) networking layer for
[`accordkit`](https://github.com/DaccordProject/accordkit-dart). Work proceeds
**additively** — new Accord code lands alongside firebridge and must keep the
app compiling; Discord code is removed only once its Accord equivalent works.

## Status at a glance

| # | Migration step (from technical-spec §11) | Status |
|---|------------------------------------------|--------|
| 1 | Rebrand & scaffolding | 🟡 In progress |
| 2 | Server config + auth | 🟡 In progress (login UI + router wired) |
| 3 | Connection / event layer | 🟡 In progress (spaces + channels + messages + members) |
| 4 | Read path (spaces → channels → messages) | 🟡 Read UI (`/spaces`) with resolved authors + CDN icons/avatars/image attachments |
| 5 | Write path (send/edit/delete, attachments, reactions, typing) | 🟢 Send/edit/delete + attachments + reactions + typing wired |
| 6 | Members & roles, moderation | 🟡 Member roster pane (role grouping + role-colored names); moderation not started |
| 7 | Parity polish (search, emoji, settings, notifications) | ⚪ Not started |
| 8 | Retire firebridge | ⚪ Not started |
| 9 | Voice / GDExtension | ⛔ Deferred (out of scope) |

Legend: ✅ done · 🟡 in progress · ⚪ not started · ⛔ deferred

## Done

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

Deliberate gaps in this scaffold (next passes): **no composer** (write path not
started); space icons are initials (CDN icon URLs not wired); no categories
grouping, DMs, folders, reactions, or typing.

### Member/user cache (authors resolve to names + avatars)

Message authors no longer render as raw IDs. A per-space member cache resolves
`authorId` to a name (nickname → display name → username → raw ID fallback) and
an initial avatar.

| File | Role | firebridge analogue |
|------|------|---------------------|
| `lib/features/member/controllers/accord_members.dart` | `AccordMembersController(spaceId)` — a space's members as a `Map<userId, AccordMember>` for O(1) author lookup. Self-loads via `members.list` (limit 100). Exposes `activeMemberSpaces` so the handler only mutates opened caches | member repositories |
| `lib/features/events/utils/accord_event_handler.dart` | now also routes `onMemberJoin/Update` → upsert and `onMemberLeave` → remove, gated on `activeMemberSpaces` | `handleEvents` |
| `lib/features/spaces/views/accord_home.dart` | `_MessagePane` watches `accordMembersControllerProvider(spaceId)`; `_MessageRow` shows resolved name + initial `CircleAvatar` | message author rendering |

Remaining gaps: authors beyond the first 100 members (or bots/webhooks not in
the member list) fall back to the raw ID — no on-demand `users.fetch` yet;
presence unwired. (CDN avatar URLs are now wired — see "CDN images".)

### Write path — send / edit / delete

The `/spaces` message pane now has a working composer plus per-message edit and
delete (gated to the current user's own messages via `session.userId`). All
three call REST and optimistically update the cache; the gateway echo
(`onMessageCreate/Update/Delete`) is then a dedup/no-op.

| File | Role |
|------|------|
| `lib/features/messaging/controllers/accord_messages.dart` | `send` → `messages.create`; `edit` → `messages.edit`; `delete` → `messages.delete`, each optimistically mutating the cache |
| `lib/features/spaces/views/accord_home.dart` | `_Composer` (multiline `TextField`, send-on-enter); `_MessageRow` now a `ConsumerStatefulWidget` with hover-revealed `_MessageActions` (⋯ → Edit/Delete), inline edit field, delete-confirm dialog, and an "(edited)" marker |

### Attachments

The composer can attach files; sending routes through `createWithAttachments`
(multipart upload) when files are present, else the plain `send`.

| File | Role |
|------|------|
| `lib/features/messaging/controllers/accord_messages.dart` | `sendWithAttachments(client, content, files)` → `messages.createWithAttachments` (multipart `/messages/upload`); falls back to `send` when no files; optimistically appends the created message |
| `lib/features/spaces/views/accord_home.dart` | `_Composer` paperclip button → `FilePicker.platform.pickFiles(allowMultiple, withData)`; pending files shown as removable `_AttachmentChip`s; `_send` builds `{filename, content (bytes), content_type}` (via an extension→MIME map) and routes accordingly, clearing on success |

### Reactions (read + write)

Messages now render reaction pills and support toggling. Optimistic add/remove,
reverted on REST failure; the four reaction gateway events keep aggregate counts
in sync (gated to opened channels via `activeMessageChannels`).

| File | Role |
|------|------|
| `lib/features/messaging/controllers/accord_messages.dart` | `toggleReaction` (add/`removeOwn` based on `includesMe`); `applyReaction`/`clearReactions`/`clearReactionEmoji` mutate aggregate `AccordReaction` counts (used by both optimistic toggles and gateway echoes) |
| `lib/features/events/utils/accord_event_handler.dart` | wires `onReactionAdd/Remove/Clear/ClearEmoji`; computes `isOwn` from `session.userId` so own vs. others' reactions update `includesMe` correctly |
| `lib/features/spaces/views/accord_home.dart` | `_ReactionPill` (emoji + count, highlighted when `includesMe`, tap to toggle); `_ReactButton` quick-picker (7 common unicode emoji) in the hover toolbar for any message |

Limitations: quick-picker is a fixed unicode set (no full emoji picker, no custom
space emoji yet); matching is by emoji `name` only.

### Typing indicator

A per-channel typing indicator: the composer broadcasts typing while you write,
and a line above the composer shows who else is typing.

| File | Role |
|------|------|
| `lib/features/messaging/controllers/typing.dart` | `TypingController(channelId)` — holds typing user IDs, each on a 10s self-expiring timer (`generated .g.dart`) |
| `lib/features/events/utils/accord_event_handler.dart` | wires `onTypingStart` → `userTyping` (gated to opened channels; skips our own `session.userId`) |
| `lib/features/spaces/views/accord_home.dart` | `_Composer` POSTs `messages.typing` throttled to once / 8s while typing; `_TypingIndicator` resolves IDs → names via the member cache ("X is typing…" / "X and Y…" / "Several people…") |

### CDN images (space icons, avatars, inline image attachments)

The `/spaces` UI now renders real images from the server's CDN, falling back
gracefully (initials / 📎 chip) when an asset is absent or fails to load. CDN
URLs are built with accordkit's `AccordCDN` helper against the logged-in
session's `server.cdnUrl`.

| File | Role |
|------|------|
| `lib/features/spaces/views/accord_home.dart` | Top-level helpers `_spaceIconUrl` / `_avatarUrl` (each handles both a bare asset **hash** → `AccordCDN.spaceIcon`/`avatar` and a path/absolute URL → `AccordCDN.resolvePath`, with `autoFormat` for `a_`-animated hashes) and `_attachmentUrl` / `_isImageAttachment` / `_asDouble`. `_SpaceIcon` shows the space icon (`CachedNetworkImage`, initials placeholder/error fallback); `_MessageRow`'s `CircleAvatar` uses `foregroundImage: CachedNetworkImageProvider` so the initial shows through on load/failure; image attachments render via the new `_ImageAttachment` widget (aspect-preserving, max 400×350, spinner placeholder, broken-image error), non-images keep the 📎 filename. CDN URL read once in `AccordHomeScreen.build` (`session.server.cdnUrl`) and threaded to the rail; `_MessageRow` reads it via `accordAuthProvider.select`. |

Uses the existing `cached_network_image` dep. Limitations: per-member avatar
overrides (`AccordMember.avatar`) and space banners not used yet; image
attachments aren't tappable/zoomable; no lightbox.

### Markdown message rendering

Message bodies now render as markdown (bold/italic, lists, headings, links,
fenced code with Prism syntax highlighting) instead of plain text — the first
firebridge-widget fold-in onto the `/spaces` scaffold (next-steps item 7).

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
> ported — there's nothing in the body to substitute. (A future enhancement
> could *highlight* a message when `mentions` includes the current user.)

### Rich embeds

Message embeds now render as cards beneath the body, mirroring the Godot
reference client's `embed.tscn`.

| File | Role | reference analogue |
|------|------|--------------------|
| `lib/features/messaging/components/box/accord_embed_box.dart` | `AccordEmbedBox({required AccordEmbed embed, String? cdnUrl})` — accent left-border card with optional author (icon + linked name), linked title, markdown description (via `AccordMarkdownBox`), fields (`_EmbedFields`, inline-grouped 3-per-row), image, thumbnail, and footer. Defensive accessors handle the loosely-typed embed model (image/thumbnail as bare URL **or** `{url}`; footer as string **or** `{text}`; color as RGB int). Images via `CachedNetworkImage`, links via `url_launcher` | `scenes/messages/embed.gd` |
| `lib/features/spaces/views/accord_home.dart` | `_MessageRow` renders `for (final embed in _message.embeds) AccordEmbedBox(...)` after attachments, before reactions |

Limitations: embed `timestamp` not shown; video-type embeds render as a static
image (no play overlay); fields assume well-formed maps.

### Member roster pane (role grouping + role-colored names)

A right-hand member roster now renders on `/spaces`, grouping the space's cached
members by role and coloring names by role — the Accord analogue of Bonfire's
firebridge `MemberList`/`MemberScrollView`, but driven by the
`AccordMembersController` cache rather than Discord's lazy sync-range list.

| File | Role |
|------|------|
| `lib/features/member/utils/member_display.dart` | Shared, widget-free helpers: `accordMemberName` (nickname → display → username → fallback), `accordAvatarUrl` (bare-hash → `AccordCDN.avatar`, OR path/URL → `resolvePath`), `accordRoleColor` (RGB int → `Color`, `0` = none), `memberColorRole` / `memberHoistRole` (highest-positioned colored / hoisted role for a member). Now the single source for name/avatar/role-color logic across the message list and roster. |
| `lib/features/member/views/accord_member_list.dart` | `AccordMemberList({String? spaceId})` — 240px right pane. Groups members under their highest hoisted role into sections sorted by role position descending (ungrouped members fall into a trailing "Members" bucket); each section header shows `LABEL — count`; rows show a CDN avatar (initial fallback) and a name tinted by `memberColorRole` + `accordRoleColor`. Roles come from `AccordSpace.roles` via `spacesControllerProvider.select`. |
| `lib/features/spaces/views/accord_home.dart` | Renders `AccordMemberList(spaceId: …)` as the Row's right pane; `_MessagePane` now also colors message author names via `memberColorRole`/`accordRoleColor`. The local `_avatarUrl` / `_authorName` / typing name-resolution were refactored onto the shared `member_display.dart` helpers (de-duplicated). |

Limitations: roster is not virtualized beyond the 100-member cache page and has
no presence sectioning (online/offline) yet; member rows are not yet tappable
(no profile popout); role icons are not rendered.

## In progress / partial

- **Step 1 (rebrand):** app still named "bonfire"; identifiers, icons, README,
  CI, and Firebase removal not yet done.
- **Step 2 (auth):** login UI + router **wired** — server-URL/credentials/MFA
  flow backed by `accordAuthProvider`, with session restore-on-launch. Still
  open: register / password-reset, multi-account switcher, and `loginWithToken`
  has no UI entry point yet.
- **Step 3 (events):** handler covers connection lifecycle, spaces, channels,
  messages, **members** (join/update/leave), **reactions**
  (add/remove/clear/clear_emoji), and **typing** (`typing.start`). Presence not
  yet wired.
- **Step 4 (read path):** spaces + channels + messages + members **controllers**
  self-load and are consumed by `AccordHomeScreen` at `/spaces`. Authors resolve
  to names; space icons, author avatars, and inline image attachments now load
  from the CDN (initials / 📎 fallback); message bodies render as **markdown**
  and **embeds** render as cards. Gaps: no on-demand author fetch for non-cached
  members; mention *highlighting* (not inline markup — see note) not wired.
- **Step 6 (members/roles):** member roster pane renders on `/spaces` — members
  grouped by highest hoisted role, names colored by highest colored role (from
  `AccordSpace.roles`). Still read-only: no role editing, permissions
  enforcement, or moderation actions (kick/ban/timeout); no presence sectioning.

## Not started

Roles/moderation, search/emoji/settings, local notifications, and firebridge
retirement. See technical-spec §11 steps 6–8.

## Deferred

Voice/video and GDExtension transport (`client.voiceManager`) — intentionally
out of scope; voice UI to be hidden/stubbed, not half-wired.

## Next steps (recommended order)

1. ✅ **Wire auth into the UI + router** — done (see "Auth wired into UI +
   router" above). Post-login now lands on the Accord-native `/spaces`, not the
   firebridge frame.
2. ✅ **Extend the read path** — done (see "Read-path controllers" above).
   `AccordChannelsController` / `AccordMessagesController` + channel/message
   gateway wiring. (Members/presence/typing/reactions still pending.)
3. 🟡 **Migrate UI widgets** off firebridge models — started: `AccordHomeScreen`
   at `/spaces` renders spaces/channels/messages from the Accord controllers
   (see "First Accord-native read UI").
4. ✅ **Member/user cache** — done (see "Member/user cache" above).
   `AccordMembersController(spaceId)` + `onMemberJoin/Update/Leave` wiring;
   message authors resolve to names. Remaining: on-demand `users.fetch` for
   authors outside the cached member page.
5. ✅ **Write path (step 5)** — send/edit/delete + attachments + reactions +
   typing done (see "Write path", "Attachments", "Reactions", "Typing
   indicator").
6. ✅ **CDN images** — done (see "CDN images"). Space icons, author avatars, and
   inline image attachments load from the server CDN via `AccordCDN`.
7. ✅ **Fold firebridge widgets onto `/spaces`** — message bodies render as
   **markdown** (`AccordMarkdownBox`) and **embeds** as cards (`AccordEmbedBox`).
   (Mentions need no inline rendering in Accord — see the note above.)
8. ✅ **Member roster pane (step 6 read side)** — `AccordMemberList` groups
   members by hoisted role and colors names by colored role (see "Member roster
   pane"). Remaining for step 6: role editing/permissions and moderation
   (kick/ban/timeout) write actions.
9. On-demand `users.fetch` for authors/typers outside the cached member page;
   then presence (`onPresenceUpdate`) → online/offline dots + roster presence
   sectioning; tappable member rows → profile popout.
10. Polish carried over from the reference client: spoiler markup, custom space
    emoji, video/audio attachment players, image lightbox, mention *highlight*
    when `AccordMessage.mentions` includes the current user.

## Notes / gotchas

- **Codegen:** Riverpod `*.g.dart` files are committed. After changing any
  `@riverpod`/`@freezed`/mappable file, run
  `flutter pub get && dart run build_runner build -d`. The foundation's
  `.g.dart` files were authored by hand and should be regenerated to get correct
  source-hashes.
- **Dependency resolution:** watch for a possible `web_socket_channel` / `http`
  version clash between `accordkit` and `firebridge` during `pub get`; resolve
  with a `dependency_overrides` entry if it surfaces.
- **Discord coupling still present:** `discord.com` hosts, the CORS proxy, and
  Firebase push remain in the tree until their Accord equivalents are wired and
  verified (steps 2–3, 9-adjacent).
