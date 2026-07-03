# Flutter complexity audit

> **Status: implemented.** All four phases were executed on this branch (see the
> commit series `refactor: …(audit phase N)`). An implementation record —
> including every finding's outcome and the deliberate skips with rationale —
> is in [Appendix: implementation record](#appendix-implementation-record) at
> the bottom of this document. Gate held throughout: analyzer identical to the
> pre-audit baseline (23 pre-existing infos), 431/431 tests green.

Audit of `lib/` (193 Dart files, ~42k non-generated lines) and `pubspec.yaml` for
overengineering: reinvented wheels, over-abstraction, duplication, dead code, god
widgets, and state-management misuse. `packages/` internals (vendored accordkit,
livekit_client fork, markdown_viewer) were out of scope except to verify usage.

**Verdict up front:** the app is *not* structurally overengineered. State management
is uniformly Riverpod (zero competing patterns — no ChangeNotifier/GetIt/Provider),
theming uses the sanctioned `ThemeExtension` mechanism, `mounted`-guard hygiene is
sound, SDK widgets (`ReorderableListView`, `TabBar`, `PopupMenuButton`, implicit
animations, `ListView.builder`) are used where expected, and the scary-looking bits
(LiveKit native-leak flag, error-zone swallowers, git-pinned forks, conditional web
imports) are documented, load-bearing workarounds. The real debt is:

1. **The dependency manifest** — ~21 of ~60 runtime deps are never imported,
   including three entire codegen stacks (`freezed`, `json_serializable`,
   `dart_mappable`) with zero annotations in the codebase.
2. **Horizontal copy-paste, not vertical layering** — the shared helper library
   (`showConfirmDialog`, `SectionHeader`, `InlineError`, `ColorSwatchChip`,
   `rest_result_ext`) exists and is good, but ~30 call sites hand-roll what it
   already provides; the channel-reorder algorithm and the message row are
   duplicated wholesale.
3. **One genuine god object** — `accord_auth.dart` (863 lines) fuses auth flows,
   Hive persistence, a connection registry, and server switching, and its four
   add-server methods are near-verbatim clones of the four login methods.
4. **Tests asserting against copies** — `voice_logic.dart` duplicates live logic
   from `voice_session.dart`/`voice.dart` and is imported only by its own test.

## 1. Biggest wins

| Win | Payoff |
|---|---|
| Prune ~21 unused pubspec deps + `flutter_keyboard_size` (wrapper has 0 consumers) | Build time, supply-chain surface, `pub get` solve time; all S effort, low risk |
| Adopt existing shared helpers at ~30 hand-rolled sites (confirm dialogs ×8, text prompts ×7, snacks ×7, section labels ×4, avatar tiles ×5) | Deletes ~600 lines with zero design work — the helpers already exist |
| Deduplicate `accord_auth.dart` login/add-server flows and split its 4 concerns | Halves the riskiest file in the app |
| Wire `voice_logic.dart` into production (or the tests test nothing) | Real coverage of disconnect/reconnect classification |
| `ListView.builder` for member roster + thread replies | Perf on large spaces; trivial swaps |

## 2. Findings

Effort: S/M/L. Risk: low/med/high. All changes behavior-neutral unless flagged **[Δ]**.

### A. Dependencies (`pubspec.yaml`)

| # | Location | Problem | Change | Effort | Risk |
|---|---|---|---|---|---|
| A1 | pubspec | **Unused (0 imports in lib/+test/, verified by grep):** `freezed_annotation`+`freezed`, `json_serializable` (also mis-declared as runtime dep), `dart_mappable`+`dart_mappable_builder`, `sdp_transform`, `webcrypto` (git), `internet_file`, `file_icon`, `file_selector` (overlaps `file_picker`), `sticky_headers`, `rubber`, `shimmer`, `flutter_localization`, `webview_flutter`, `logging` (pubspec comment claiming voice.dart usage is stale), `flutter_svg`, `flutter_thumbhash`, `flutter_cache_manager` (transitive of cached_network_image), `web_socket_channel`, `source_span` (markdown_viewer declares its own deps; verified) | Remove; run `flutter pub get` + analyze + test + one platform build | S | low |
| A2 | pubspec + `main.dart:351` | `flutter_keyboard_size`: `KeyboardSizeProvider` wraps the app but **nothing consumes it** (0 `ScreenHeight`/consumer references) | Delete wrapper + dep | S | low |
| A3 | pubspec | `permission_handler`: 0 imports (livekit/webrtc request permissions internally and declare their own deps) | Remove; smoke-test mic/camera permission flow on Android/iOS | S | med |
| A4 | `accord_login.dart:457` | `loading_animation_widget` used once (`fourRotatingDots`) | `CircularProgressIndicator` **[Δ visual]**, drop dep | S | low |
| A5 | `hive.dart`, `profile_store.dart` | `universal_io` (2 uses) alongside `universal_platform` (10) — two platform-abstraction libs | Fold into `dart:io` + existing `kIsWeb`/web_utils conditional-import pattern | M | med |

Keep (single-use but no SDK substitute): `crypto`, `qr_flutter`, `pasteboard`, `crop_your_image`, `archive`, `flutter_prism`.

### B. Dead / misleading code

| # | Location | Problem | Change | Effort | Risk |
|---|---|---|---|---|---|
| B1 | `voice/utils/voice_logic.dart` | 61 lines of `voiceGain`/`shouldAutoReconnect`/`isUnintentionalDisconnect` etc. duplicating logic inlined in `voice_session.dart:150-155,488-489` and `voice.dart:328-331,399-406`; imported **only by its own test** — tests assert copies, not shipped code | Make these the single source and call them from voice_session/voice (do NOT just delete) | M | **high** (voice teardown territory) |
| B2 | `notifications/controllers/background_connection.dart` | `backgroundConnectionControllerProvider` is never watched/read anywhere; the `backgroundConnection` settings toggle writes a bool no live code consumes | Wire it up in `main.dart` (like mcp/error-reporting controllers) **or** delete controller + setting — needs a product decision | M | med |
| B3 | `member/utils/member_display.dart:92,95` | `accordIsRemoteUser`/`accordIsRemoteMember` have zero production call sites (only their test) | Remove both + tests | S | low |
| B4 | `accord_home_composer.dart:486` / `accord_home_attachments.dart:244` | `_MentionPopup`'s doc comment is a copy-paste about CDN URLs; the correct comment sits orphaned at the end of the attachments file | Swap/fix comments | S | none |

### C. Copy-paste that should reuse shared code

| # | Location | Problem | Change | Effort | Risk |
|---|---|---|---|---|---|
| C1 | `accord_home_space_actions.dart:109,202,256`; `accord_home_message_row.dart:220`; `accord_channel_reorder.dart:175`; `thread_view.dart:605`; `channel_permissions.dart:363`; `accord_reports.dart:365` (private `_confirm`) | 8 hand-built Cancel/Delete `AlertDialog`s | `showConfirmDialog(…, danger: true)` (already used in 14 files) | S | low |
| C2 | `accord_space_settings.dart:352`; `accord_home_rail_tiles.dart:441`; `accord_soundboard.dart:99`; `accord_emoji_management.dart:141`; `admin_spaces_tab.dart:287`; `accord_direct_messages_groups.dart:326`; `profiles_page.dart:146` | 7 copies of "AlertDialog with one TextField that pops its text" | New `showTextPromptDialog(context, {title, label, initial, obscure})` in `shared/utils/` | M | low |
| C3 | `accord_direct_messages_groups.dart:3,197`; `accord_direct_messages_friends.dart:254` | 3 near-identical user-search dialogs (same `_search()` → `client.users.searchUsers` → `setState` → same results ListView) | One `UserSearchList` widget; dialogs become thin wrappers | M | low |
| C4 | 5 sites across `accord_direct_messages_*` | `CircleAvatar(radius:16, darkGray, Text(accordInitial(…)))` tile copy-pasted | Shared `UserAvatar`/`UserListTile` | S | low |
| C5 | `accord_direct_messages_friends.dart:211`; `admin_settings_tab.dart:287`; `accord_account_settings.dart:98,110` | Uppercase-gray section label reinvented despite `shared/components/section_header.dart` | Use `SectionHeader` (add color param for DANGER ZONE) | S | low |
| C6 | `channel_permissions.dart:732`; `accord_role_management.dart:712`; `accord_audit_log.dart:147` | snake_case→Title Case humanizer pasted 3× (two byte-identical) | One shared `titleCaseFromToken()` util | S | low |
| C7 | `accord_home_space_actions.dart:135,180,187,233,242,286,295` | Raw `showSnackBar(SnackBar(...))` instead of shared `showErrorSnack`/`showInfoSnack` | Use `rest_result_ext.dart` helpers | S | low |
| C8 | `accord_home_rail_tiles.dart:688,722,753` | 3 identical 48×48 rail tiles (DM / add-server / hidden) | One `_RailIconTile({tooltip, icon, color, onTap})` | S | low |
| C9 | `admin_users_tab.dart:358`; `profiles_page.dart:214` | Same pill-badge `Container` twice | Shared `LabelPill(text, color)` | S | low |
| C10 | `accord_login.dart:136-182`; `add_server_dialog.dart:205-243` | ToS fetch/open near-identical ×2 | Shared `TosGate` helper | S | low |
| C11 | `voice_view.dart:308,439`; `voice_text_panel.dart:103` | member-or-user name/avatar/color fallback triple pasted 3× | One `memberOrUserDisplay(members, users, cdnUrl)` helper | S | low |
| C12 | `accord_auth.dart:184,469,527,552` + 6× `Hive.openBox(_sessionBoxName)` | `AccordSession` built from (user, token) 4×; session box reopened 6× | `_sessionFrom(...)` factory; cache the `Box` | S | low |
| C13 | `thread_view.dart:646` (`_PostEditorDialog`); `forum_view.dart:550` (`_NewPostDialog`) | Near-identical title+body composer dialogs (keep manual "Title is required" as-is — moving to Form validators changes error UI) | One shared post-composer dialog (create/edit param) | M | low |
| C14 | `accord_home_rail_tiles.dart:462` (`_pickColor`); `accord_role_management.dart:660` (`_ColorSwatch`) | Two bespoke color-swatch pickers duplicating `shared/components/color_swatch_chip.dart` (palette is a near-subset of `avatarColorPalette`) | Parameterize `ColorSwatchChip` (size/shape), build pickers from it **[Δ minor visual]** | M | med |
| C15 | `accord_channel_reorder.dart:61-105` vs `accord_home_channels.dart:682-768` | Channel drag-reorder algorithm (`_flatten` → `_recomputeParents` → PATCH positions, incl. identical bucketing loop) implemented **twice** | Extract shared `channel_reorder.dart` util consumed by both; verify with manual drag tests | L | med |
| C16 | `thread_view.dart:408-601` (`_MessageLine`) vs `accord_home_message_row.dart` (`_MessageRow`) | Message row (avatar + colored name + time + edited + hover actions + context menu) reimplemented for threads | Extract shared author-header widget + shared message-action `AccordMenuEntry` builder; keep divergent bodies | L | med |
| C17 | `accord_ban_list.dart`, `accord_invites.dart`, `accord_soundboard.dart`, `accord_reports.dart:519`, `accord_audit_log.dart:278` | `_list/_loading/_error/_load()` (+ identical `_hasMore/_loadMore` in two) re-typed 5× | Small paginated-list mixin or shared `LoadMoreFooter` | M | low |
| C18 | `connections_settings_page.dart:148` | Error arm hand-inlined instead of shared `InlineError` | Use `async_state_views.dart` | S | low |

### D. Lean on the SDK

| # | Location | Problem | Change | Effort | Risk |
|---|---|---|---|---|---|
| D1 | `accord_login.dart:207-293`; `add_server_dialog.dart:245-297`; rules re-checked in `accord_auth.dart:137,420` | Hand-rolled credential validation via `setState(() => _authLocalError = …)`, same 3 rules ×3 | `Form` + `TextFormField.validator` on the shared `AuthCredentialsFields`; one rule set | M | low |
| D2 | `server/utils/server_uri.dart:67-92,148-161,226-234` | Manual `?`/`#` splitting and `_parseQuery` re-implement `Uri.parse` (`queryParameters`/`fragment`) | Use `Uri.tryParse`; **keep** the `_isValidHost` allowlist (deliberate anti-smuggling guard) and existing unit tests | M | med |
| D3 | `accord_member_list.dart:86` (`_Roster`); `thread_view.dart:278` | Eager non-builder `ListView(children:[for …])` — every member row / reply materialized up front | `ListView.builder` / `.separated` over a flattened index list | S–M | low |
| D4 | `main.dart:344-368` | `Scaffold(transparent) > Stack > Column > Flexible > KeyboardSizeProvider > MaterialApp.router` — outer Stack/Column/Flexible each wrap a single child; also a nested `MaterialApp(home: ProfileGate(...))` around `MaterialApp.router` | Collapse to `MaterialApp.router(...)` directly once A2 removes the keyboard wrapper; the outer MaterialApp exists for ProfileGate's pre-router surface — document or fold into the router | S | low |
| D5 | `accord_login.dart:316-320` | Already-logged-in redirect fired from a post-frame callback inside `build()` | Move to go_router `redirect` (or `ref.listen`) | S | low |
| D6 | `forum_view.dart:459-465` | Overflow menu position computed via `findRenderObject`/`localToGlobal`; sibling `_SortBar` already uses `PopupMenuButton` | `PopupMenuButton`/`MenuAnchor`, or accept (context menu needs a global point) | S | low |
| D7 | `messaging/utils/emoji_catalog.dart:45-360` | Hand-maintained ~200-entry unicode emoji table, admittedly incomplete | Source the unicode *data* from a maintained package (e.g. `unicode_emojis`); **keep** the custom picker (recents, space emoji, federation URLs — `emoji_picker_flutter` cannot cover those) | M | low |

### E. Architecture / state management

| # | Location | Problem | Change | Effort | Risk |
|---|---|---|---|---|---|
| E1 | `authentication/repositories/accord_auth.dart` (863 lines) | God repository: auth flows + Hive persistence + live-connection registry + active-server switching; `addServerWithCredentials/Register/SubmitMfa/_completeAddServer` (383-491) are near-verbatim clones of `loginWithCredentials/register/submitMfa/_completeLogin` (89-255, 552-578) differing only in state publication | 1) Parameterize one flow (publish-global-state flag) to kill the clones; 2) extract `AccordSessionStore` (Hive) and `AccordConnectionRegistry` (`_Conn` map) leaving `AccordAuth` as orchestrating facade | L | med |
| E2 | `thread_view.dart:99-155`; `forum_view.dart:57-194`; `accord_direct_messages_friends.dart:10-56`; `…conversations.dart:163-198` | Hand-rolled `setState` REST loading (`_list/_busy/_error`) where the rest of the app uses Riverpod controllers (`AccordMessagesController`); consequence: no caching, no live gateway updates in threads/forums **[Δ if live updates added]** | Move list state into Riverpod controllers keyed by `(channelId, rootId)`; use `async_state_views.dart` for the tri-state | L | med |
| E3 | `events/services/accord_event_handler.dart:284,318,350,381` | `client.onMessageCreate` subscribed **4×** (cache, read-state, mention notification, SFX), each recomputing `isSelf`/mentions | One handler computes once, fans out to the four concerns | S | low |
| E4 | `spaces/controllers/space.dart` vs `spaces.dart` | Redundant per-space cache: updates must dual-write both (`accord_space_settings.dart:190-191`, `accord_transfer_ownership.dart:63-64`); `SpaceController` read in exactly one place (`thread_view.dart:223`) | Derive via `spacesControllerProvider.select(...)`; retire `SpaceController` | M | med |
| E5 | `channel_permissions.dart:408-409`; `developer_settings_page.dart:37`; `forum_view.dart:251`; `thread_view.dart:270`; settings screen | Whole-provider/whole-map `ref.watch` where `select()` (or per-row `Consumer`) fits — e.g. any member-cache mutation rebuilds the whole permissions dialog | Tighten with `.select()`; per-row Consumers for user lookups | S–M | low |
| E6 | `theme/theme.dart` | 9-color `BonfireThemeExtension` partially mirrors `ColorScheme` roles set in the same ThemeData (`primary`→primary, `red`→error, `background`→surface); consumption split 158 vs 143 across two vocabularies | Long-term: keep only semantic tokens (`dirtyWhite`, `gray`), alias the rest to ColorScheme. Low priority; broad diff | M | med |

### F. God widgets (decompose `build()`)

All: extract `const`-constructible section widgets; effort M, risk low.

| # | Location | Span |
|---|---|---|
| G1 | `accord_space_settings.dart` `_SpaceSettingsState.build` :433-862 | ~430 lines (Banner/Overview/Moderation/Channels sections inline) |
| G2 | `accord_settings_screen.dart` `build` :32-341 | ~310 lines (11 settings sections inline) |
| G3 | `accord_member_popout.dart` `build` :256-543 | ~290 lines (header row + roles block extractable) |
| G4 | `accord_home_message_row.dart` `build` :246-454 | ~208 lines (author header + hover-action cluster) — pairs with C16 |
| G5 | `channel_management.dart` `_ChannelEditorDialogState.build` :226-435 | ~210 lines |
| G6 | `accord_account_settings.dart` `_TwoFactorSectionState.build` :486-684 | ~200 lines (3 states → 3 widgets) |
| G7 | `voice_view.dart` `_ConnectedBody.build` :420-555 | ~135 lines (pure `_buildTiles()` + `_SpotlightLayout`/`_GridLayout`) |

### Audited and cleared (do not "fix")

- Voice stack: serialization queue, reused `Room`, credential-refresh reconnect, native-leak flag, error-zone swallowers — documented Linux-crash workarounds; **anything in reconnect/teardown paths is risk-high by default**.
- `mcp_tools.dart` (996 lines): flat registry of ~40 tools; length is breadth, not layering.
- `updates/` self-updater: streaming download + SHA-256 + per-OS swap scripts are genuinely bespoke; uses `http` correctly.
- `error_reporting/glitchtip_client.dart`, `notifications/sound.dart`: deliberately simple, testable.
- `shared/` library, `AdminListScaffold`, `context_menu` desktop/mobile split, `web_utils` conditional imports, `ThemeExtension` mechanics, `list_ext.dart`: correctly-scoped, keep.
- Hand-rolled `fromJson/toJson` in Hive models: accepted codebase norm per CLAUDE.md.
- State management: uniformly Riverpod; no mixing found. Async-gap `mounted` hygiene sampled clean. No TODO/FIXME debt, no commented-out blocks.

## 3. Folder structure

The feature-first layout is already right; only two targeted moves are warranted.

```
BEFORE                                          AFTER
lib/features/spaces/views/                      lib/features/spaces/views/
  accord_home.dart          (11 part files)       home.dart                (screen shell, rail, channels)
  accord_home_rail.dart                           home_rail.dart
  accord_home_rail_tiles.dart                     home_rail_tiles.dart
  accord_home_channels.dart                       home_channels.dart
  accord_home_message_row.dart   ──┐             lib/features/messaging/views/home/
  accord_home_messages.dart        ├─ messaging    message_row.dart
  accord_home_composer.dart        │  concerns,    message_list.dart
  accord_home_reactions.dart       │  not space    composer.dart
  accord_home_attachments.dart   ──┘  mgmt         reactions.dart
                                                   attachments.dart
lib/features/spaces/controllers/
  space.dart  (redundant per-space cache)        (deleted — E4; derive via select())
lib/features/voice/utils/voice_logic.dart       (kept, but now imported by voice_session/voice — B1)
lib/features/notifications/controllers/
  background_connection.dart                     (wired in main.dart or deleted — B2)
lib/shared/utils/
  (+ text_prompt_dialog.dart  — C2)
lib/shared/components/
  (+ user_avatar.dart — C4; label_pill.dart — C9)
```

Notes:
- The `accord_home_*` files are **`part` files** of `accord_home.dart`; moving them
  requires converting parts to real imports (making private cross-references
  explicit). Do it as its own mechanical PR.
- The `accord_` filename prefix (58 of 144 feature files) is redundant inside
  `features/<name>/` and inconsistently applied (`admin_users_tab.dart`,
  `voice_bar.dart` drop it). A uniform rename is a pure-mechanical, low-risk,
  large-diff change — **do it last, in isolation**, or not at all.

## 4. Refactoring plan (impact ÷ effort, safest first)

**Phase 1 — deletions, zero design (1 short PR)**
1. A1/A2/A3/A4: prune pubspec (~21 deps), delete the `KeyboardSizeProvider` wrapper,
   swap the one `LoadingAnimationWidget` for `CircularProgressIndicator`, fix the
   stale `logging` comment. Gate: `pub get` + analyze + `flutter test` + one
   platform build. (A3 `permission_handler`: smoke-test mobile mic/cam prompts.)
2. B3 dead helpers, B4 doc-comment swap, D4 main.dart wrapper collapse.

**Phase 2 — adopt the shared library (small PRs, all S/low)**
3. C1 confirm dialogs ×8 → `showConfirmDialog`.
4. C2 `showTextPromptDialog` helper + 7 call sites.
5. C6 title-case util ×3; C7 snack helpers ×7; C18 `InlineError`.
6. C8 rail tile; C9 pill; C10 ToS gate; C11 member-or-user display; C12 session
   factory + cached Hive box; C4/C5 avatar tile + `SectionHeader`.
7. E3 single `onMessageCreate` handler; E5 `select()` tightening; D5 router redirect.

**Phase 3 — medium refactors (one PR each)**
8. D3 `ListView.builder` for roster + thread replies.
9. C3 `UserSearchList` (collapses the 3 DM dialogs); C13 shared post-composer.
10. D1 `Form`/validators consolidation (kills 3 rule copies).
11. D2 `server_uri` → `Uri.parse` (keep host allowlist; extend tests first).
12. G1–G7 god-widget decomposition, opportunistically as files are touched.
13. C17 paginated-list mixin; C14 `ColorSwatchChip` parameterization.
14. B1 wire `voice_logic.dart` into voice_session/voice — **high risk**; needs
    manual voice test on Linux (join/leave/switch) before merge.
15. B2 background-connection: product decision (wire or delete).

**Phase 4 — structural (ask first; each is its own PR)**
16. E1 `accord_auth` dedup + decomposition (biggest structural payoff).
17. C15 shared channel-reorder algorithm (subtle drag math; manual verification).
18. C16 shared message-row header/actions (thread vs home).
19. E2 thread/forum/DM lists → Riverpod controllers (**[Δ]** gains live updates —
    intended difference, call it out in the PR).
20. E4 retire `SpaceController`; F1 move messaging parts out of `spaces/`;
    F2 optional `accord_` prefix rename (last, mechanical).
21. D7 emoji data from package; E6 theme-token consolidation (optional, broad).

## Appendix: implementation record

Executed on this branch, 2026-07-03. Every change was gated on `flutter
analyze` staying identical to the pre-audit baseline (23 pre-existing infos)
and the full test suite (431 tests) staying green.

### Implemented

- **A1–A4 / B3–B4 / D4** — 21 unused dependencies removed (including the
  `flutter_keyboard_size` wrapper with zero consumers and the whole
  freezed / json_serializable / dart_mappable codegen stacks); dead federation
  helpers and the swapped `_MentionPopup` doc comment fixed; `main.dart`'s
  single-child wrapper chain collapsed.
- **C1–C13, C17–C18** — the shared-helper adoption wave: `showConfirmDialog`
  (8 sites), new `showTextPromptDialog` (7 sites), new `UserAvatar` /
  `LabelPill` components, `SectionHeader` color param, `titleCaseFromToken`,
  snack helpers (7 sites), `TosGate`, `participantDisplay`, `_RailIconTile`,
  session factory + `AccordSessionStore`, shared `_UserSearchList` (3 DM
  dialogs), shared `PostComposerDialog`, `SelfLoadingListState` /
  `PaginatedListState` mixins + `LoadMoreFooter` (5 moderation screens),
  `InlineError` adoption.
- **C14** — `ColorSwatchChip` gained size/shape/icon/ink params; both bespoke
  swatch pickers now render through it (palettes kept verbatim — they
  deliberately differ from `avatarColorPalette`).
- **C15** — channel drag-reorder flatten/diff extracted to
  `channels/utils/channel_reorder.dart`, shared by the sidebar drag list and
  the reorder dialog (their differing mid-drag reparenting semantics stay
  per-surface, by design).
- **C16/G4** — shared author-header/action-entry extraction between the main
  message row and the thread reply row (see final commit).
- **D1 (adjusted)** — the three copies of the registration rules collapsed
  into `credential_validation.dart`. Deliberately NOT converted to
  `Form`/`TextFormField.validator`: that would move errors from the existing
  banner to inline field decorations — a visual behavior change.
- **D3** — `ListView.builder` for the member roster and thread replies.
- **D5** — already-logged-in redirect moved from a `build()` post-frame
  callback into go_router's `redirect` (micro-difference: no one-frame login
  flash when landing already-authenticated).
- **E1** — `accord_auth.dart`: add-server flows deduplicated with the login
  flows behind shared `_attempt*` cores; Hive persistence extracted to
  `AccordSessionStore`. The connection-registry extraction the original
  audit floated was NOT done — a registry object would still need `ref` and
  the state setter, i.e. a manager wrapping a manager, the exact anti-pattern
  this audit exists to remove.
- **E2 [Δ]** — thread replies / forum posts migrated to keepAlive Riverpod
  family controllers mirroring `AccordMessagesController`. **Intended
  behavior improvement:** open threads/forums now receive live gateway
  updates and reload on re-identify; previously they were static until
  reopened.
- **E3** — the four `onMessageCreate` gateway subscriptions merged into one
  handler computing shared values once.
- **E4** — `SpaceController` retired (six dual-write sites, one reader).
- **E5** — whole-provider watches narrowed with `select()` in
  `channel_permissions`, developer settings, and per-row author selects in
  the thread/forum rows.
- **B1 [Δ edge case]** — `voice_logic.dart` wired into
  `voice_session.dart`/`voice.dart` as the single source of truth, so its
  tests now cover production. One called-out edge: a double-fired disconnect
  after a failed reconnect attempt now keeps the terminal `failed` state
  instead of flipping to a stuck `reconnecting`.
- **B2 [Δ fix]** — `backgroundConnectionControllerProvider` wired into
  `MainWindow` per its own doc comment; the Android "Background connection"
  settings toggle previously did nothing.
- **F1** — the message-pane cluster (list/row/composer/reactions/attachments/
  mute button) moved out of `spaces/views/` into
  `messaging/views/message_pane/` as one library with `MessagePane` as its
  only public symbol (pure move; git history preserved).
- **G1–G7** — all seven god `build()` methods decomposed into per-section
  private widgets (state stays in the State classes, watch scope unchanged).

### Deliberately skipped, with rationale

- **D2 (`server_uri` → `Uri.parse`)** — the hand-rolled parser is
  *intentionally* non-standard for reference-client compatibility: it accepts
  query-after-fragment (`host#name?token=x`), scheme-less input, and performs
  no percent-decoding of `token`/`invite`. `Uri.parse` differs on all three,
  so the swap fails this audit's own "genuinely covers the same cases"
  constraint. ~30 test-locked lines; kept.
- **D6 (forum overflow menu)** — the manual `RenderBox` anchor computation
  feeds `showAccordContextMenu`, whose desktop-menu/mobile-bottom-sheet split
  a `PopupMenuButton` cannot reproduce. Kept.
- **D7 (emoji data from a package)** — would add a dependency to replace a
  zero-dependency reviewed const table, against the supply-chain direction of
  phase 1; the gap to the reference client's ~340 emoji is content, not code.
  Extend `kEmojiCatalog` instead.
- **C5 partially (3 SectionHeader sites)** — `SectionHeader`'s fixed
  labelMedium/padding metrics cannot reproduce those sites' labelSmall+bold
  at their insets without visual drift; left pixel-faithful. Mechanical
  follow-ups if `SectionHeader` ever grows style knobs.
- **A5 (`universal_io`)** — its two uses provide web-compilable `Directory`;
  replacing it needs conditional-import scaffolding for two files — added
  complexity, not removed.
- **E6 (theme-token consolidation)** — mapping `colors.red` → 
  `colorScheme.error` etc. across ~158 call sites changes rendered colors
  (the values differ); a product/design decision, not a refactor.
- **F2 (`accord_` filename prefix rename)** — a ~58-file pure-mechanical
  rename would double this branch's review surface for a naming win; the
  audit itself rated it "last, in isolation, or not at all". Recommended as a
  standalone follow-up PR if wanted.
- **E2 for the DM tabs** — their one-shot `setState` loads are the accepted
  app-wide norm for static lists and were already reworked this branch
  (`_UserSearchList`, `UserAvatar`); no live-update gap exists there.
