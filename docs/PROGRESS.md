# Daccord Port — Progress

> Status tracker for the Bonfire → Daccord migration. Companion to
> [`technical-spec.md`](./technical-spec.md) (the plan) and the root
> [`CLAUDE.md`](../CLAUDE.md). Last updated: 2026-06-04 (auth UI + router wired;
> read-path controllers; first Accord-native read UI at `/spaces`).

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
| 3 | Connection / event layer | 🟡 In progress (spaces + channels + messages) |
| 4 | Read path (spaces → channels → messages) | 🟡 Controllers + first Accord read UI (`/spaces`) |
| 5 | Write path (send/edit/delete, attachments, reactions, typing) | ⚪ Not started |
| 6 | Members & roles, moderation | ⚪ Not started |
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

Deliberate gaps in this scaffold (next passes): message **authors render as raw
IDs** (no member/user cache yet); **no composer** (write path not started);
space icons are initials (CDN icon URLs not wired); no categories grouping,
DMs, folders, reactions, or typing.

## In progress / partial

- **Step 1 (rebrand):** app still named "bonfire"; identifiers, icons, README,
  CI, and Firebase removal not yet done.
- **Step 2 (auth):** login UI + router **wired** — server-URL/credentials/MFA
  flow backed by `accordAuthProvider`, with session restore-on-launch. Still
  open: register / password-reset, multi-account switcher, and `loginWithToken`
  has no UI entry point yet.
- **Step 3 (events):** handler covers connection lifecycle, spaces, channels,
  and messages. Members, presence, typing, and reactions not yet wired.
- **Step 4 (read path):** spaces + channels + messages **controllers** self-load
  and are consumed by `AccordHomeScreen` at `/spaces`. Gaps: authors render as
  raw IDs (no member/user cache), no composer, initials-only space icons, and the
  richer firebridge widgets (markdown, embeds, reactions) aren't folded in yet.

## Not started

Write path, members/roles/moderation, search/emoji/settings, local
notifications, and firebridge retirement. See technical-spec §11 steps 5–8.

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
4. **Member/user cache** — resolve `authorId`/`ownerId` to names + avatars (REST
   `members`/`users` + `onMemberJoin`/`onMemberUpdate` gateway wiring), so the
   message list and rail stop showing raw IDs.
5. **Write path (step 5)** — wire the composer to `messages.create`, then
   edit/delete, attachments, reactions, and the typing indicator.
6. Fold richer firebridge widgets (markdown, embeds, reactions) onto the
   `/spaces` scaffold, or migrate them in place.

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
