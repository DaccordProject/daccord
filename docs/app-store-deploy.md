# App / Play Store deployment

The `Release` workflow (`.github/workflows/release.yml`) builds signed store
builds and takes iOS and Android all the way to public release — a tag push
needs no follow-up clicks in App Store Connect or the Play Console. macOS is the
exception: its build is uploaded but not submitted, because the Mac product page
does not exist yet ([below](#mac-app-store-listing-first)).

| Target | Job | Lane | Lands in |
|--------|-----|------|----------|
| iOS App Store | `ios-appstore` | `fastlane ios appstore` | App Store (submitted for review, auto-release) |
| Mac App Store | `mac-appstore` | `fastlane mac appstore` | App Store Connect (uploaded only — **not** submitted) |
| Notarized DMG | `build` (macOS) | `fastlane mac dmg` | GitHub Release (direct download) |
| Google Play | `android-play` | `fastlane android play` | Play Console (AAB → `production` track) |

Direct-download signing — the notarized DMG, Windows Authenticode, stable
Android APK identity, and the release checksums/GPG signature — is covered in
[release-signing.md](release-signing.md). Tagged executable platform jobs fail
when their complete credential set is absent or verification fails.

These run on a **tag push** (`v*`) and on **workflow_dispatch** (with
`deploy_ios` / `deploy_mac` / `deploy_android` toggles, handy for testing
without cutting a real release). Apple auth uses an **App Store Connect API
key**; Google Play auth uses a **service-account JSON** — no interactive logins
or 2FA in CI.

The Play build is signed with the **upload key** (from secrets); Google's
**Play App Signing** re-signs it with the app signing key for delivery. It's
released to the **`production`** track with the rollout **`completed`**, so a
tagged release always ships to all users immediately. The track and release
status are hardcoded in the workflow and cannot be overridden by repo
variables — staging a build to testers is a deliberate edit to
`.github/workflows/release.yml`, not a setting someone can leave switched on by
accident. Listing metadata and graphics live in the Play Console and are not
touched by the upload.

The store builds (`ios-appstore`, `mac-appstore`, `android-play`) are compiled
with `--dart-define=APP_STORE=true`, which sets `kAppStoreBuild` and disables
the in-app GitHub self-updater (store guidelines forbid it; the Mac build is
also sandboxed). The DMG and direct-download APK builds keep the updater.

## Required GitHub secrets

Set under **Settings → Secrets and variables → Actions**. The
`scripts/bootstrap-signing.sh` helper (run locally on a Mac with the API key)
generates the certs/profiles and prints the `gh secret set` commands.

| Secret | What it is |
|--------|------------|
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_KEY_P8_BASE64` | base64 of the `AuthKey_<id>.p8` |
| `APPLE_TEAM_ID` | 10-char Apple Developer team ID |
| `CERT_P12_PASSWORD` | password protecting every `.p12` below (shared) |
| `APPLE_DIST_CERT_P12` | base64 `.p12` — **Apple Distribution** (iOS + Mac app signing) |
| `MAC_INSTALLER_CERT_P12` | base64 `.p12` — **Mac Installer Distribution** (the Mac App Store `.pkg`) |
| `DEVELOPER_ID_CERT_P12` | base64 `.p12` — **Developer ID Application** (notarized DMG) |
| `IOS_PROFILE_BASE64` | base64 of the iOS **App Store** provisioning profile |
| `IOS_PROFILE_NAME` | that profile's name (matches `PROVISIONING_PROFILE_SPECIFIER`) |
| `MAC_PROFILE_BASE64` | base64 of the **Mac App Store** provisioning profile |
| `MAC_PROFILE_NAME` | that profile's name |

### Google Play (`android-play` job)

| Secret | What it is |
|--------|------------|
| `PLAY_SERVICE_ACCOUNT_JSON` | the full JSON key for a Google Cloud **service account** granted access in the Play Console |
| `ANDROID_KEYSTORE_BASE64` | base64 of the upload keystore (`.jks`) used to sign the AAB |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore (store) password |
| `ANDROID_KEY_ALIAS` | the upload key alias inside the keystore |
| `ANDROID_KEY_PASSWORD` | the key password (often the same as the store password) |
| `ANDROID_SIGNING_CERT_SHA256` | SHA-256 fingerprint of the upload certificate; pins both APK and AAB identity |

No repo variables affect the rollout: the workflow pins `PLAY_TRACK=production`
and `PLAY_RELEASE_STATUS=completed`. (Older revisions read these from repo
variables; any `PLAY_TRACK` / `PLAY_RELEASE_STATUS` still defined under Settings
→ Secrets and variables → Actions → Variables is now ignored and can be
deleted.)

## One-time human steps

1. **Create the API key** in App Store Connect → Users and Access →
   Integrations → App Store Connect API (role: Admin or App Manager). Download
   the `.p8` (Apple lets you download it **once**).
2. Run `scripts/bootstrap-signing.sh /path/to/AuthKey_XXXX.p8` on a Mac — it
   creates the three certificates and two provisioning profiles via the API key
   and sets all the secrets above with `gh`.
3. App record + bundle ID `com.cattrall.daccord` must already exist (they do —
   see the App Store Connect listing).

### Google Play

1. **Create the upload keystore** (once) and set the five `ANDROID_*` secrets:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
     -validity 10000 -alias upload
   base64 -i upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
   gh secret set ANDROID_KEYSTORE_PASSWORD   # store password
   gh secret set ANDROID_KEY_ALIAS           # "upload"
   gh secret set ANDROID_KEY_PASSWORD        # key password
   keytool -list -v -keystore upload-keystore.jks -alias upload \
     | sed -n 's/^[[:space:]]*SHA256: //p' \
     | gh secret set ANDROID_SIGNING_CERT_SHA256
   ```
   Keep `upload-keystore.jks` safe and out of git (the root `.gitignore`
   excludes `*.jks`, `*.keystore`, and `android/key.properties`). Enable
   **Play App Signing** in the Play Console so Google manages the app signing
   key; this upload key only needs to match what Play expects for uploads.
2. **Create a service account** in Google Cloud (IAM → Service Accounts) for the
   project linked to the Play Console, create a JSON key, then in **Play Console
   → Users and permissions → Invite new user** grant that service account access
   to the app (at least *Release to testing tracks* + *Release apps to
   production*). Store the JSON:
   ```bash
   gh secret set PLAY_SERVICE_ACCOUNT_JSON < play-service-account.json
   ```
3. The Play app record + package `com.daccord_projects.daccord` must already
   exist with the listing and App content declarations completed (they do — see
   the Play Console listing). Note the **first-ever** AAB for a brand-new app
   must be uploaded by hand in the Play Console (the API rejects it until an
   initial release exists); once past that, tagged releases go straight to the
   `production` track.

## Triggering

- **Real release:** push a tag matching `pubspec.yaml` (`git tag v0.2.3 && git push --tags`).
- **Test a store deploy only:** Actions → Release → Run workflow, pick the
  branch, and toggle `deploy_ios` / `deploy_mac` / `deploy_android`.

## Release notes ("What's New")

Apple rejects a version submission that has no release notes, so CI generates
them rather than leaving the release to block on a human.
`dist/app-store-release-notes.sh` reads the commits between the previous stable
tag and `HEAD` (release candidates are skipped, so a stable release's notes span
everything since the last stable one), keeps the `feat`/`fix`/`perf` subjects,
strips the conventional-commit prefixes and writes a bulleted list to
`fastlane/metadata/{ios,mac}/en-US/release_notes.txt`. That is the only metadata
field CI delivers; everything else stays managed in App Store Connect. Only the
iOS job runs it today — the Mac job delivers no metadata at all (below).

The output is generated, not committed — `fastlane/metadata/` is gitignored.
The iOS job checks out with `fetch-depth: 0` because a shallow clone has no
previous tag to diff against; if one is ever missing the script falls back to a
generic note instead of failing the release.

To hand-write the notes for one release, add a version marker and the copy to
`dist/release-notes.txt`:

```text
# Release version: 0.2.14
• Added a clearer example of a user-visible improvement.
```

The marker must match both `pubspec.yaml` and the `v*` release tag or the job
fails before upload. After the release, return the file to its comment-only
template; otherwise a later version also fails instead of silently reusing
stale copy.

## What's still manual

Nothing per release for **iOS and Android**. A tag push submits the iOS build
for review with automatic release on approval, and ships the Android build to
`production`. What remains there is **per-app, set once**, and every later
release reuses it:

- **iOS:** screenshots (generated from `store-media/ios-generator/` — see
  [guideline 2.3.10](#guideline-2310-what-the-ios-screenshots-may-show) before
  regenerating them), the App Privacy questionnaire, and the age rating, in
  App Store Connect. A brand-new app also needs its first release created by
  hand before API submissions work.
- **Google Play:** the store listing, content rating and Data safety
  declarations — already complete for this app.

**macOS is not there yet** — see the next section.

What no CI can remove is the stores' own review. Apple's review typically takes
about a day; the build sits in *Waiting for Review* → *In Review* and then goes
live on its own (`automatic_release: true`). Google's review gates the
`production` rollout the same way. "All the way to production" means *submitted
and set to ship*, not *live within minutes*.

### Retrying an iOS App Store release

The iOS lane queries App Store Connect before asking `deliver` to submit. If the
same marketing version **and build** is already *Waiting for Review* or *In
Review*, and its release type is still **After Approval**, the run is treated as
an idempotent success: the duplicate IPA upload, version/metadata mutation, and
review-submission request are all skipped. The Fastlane log calls this out
explicitly. The original submission keeps automatic release enabled.

The lane fails closed when the active review belongs to another version or
build, is being cancelled, has unresolved issues, is configured for manual
release, or App Store Connect returns incomplete/inconsistent state. In
particular, rerunning the same GitHub Actions run keeps its build number and is
idempotent; starting a new run for the same marketing version produces a new
build number and therefore conflicts with a review already using the older
build.

For an intentional binary replacement after App Review sets a submission to
`UNRESOLVED_ISSUES`, temporarily set the repository variable
`IOS_REPLACE_UNRESOLVED=true`. The lane then cancels that rejected submission,
waits for its version record to unlock, uploads the new build and resubmits it
with automatic release. Remove the variable as soon as the replacement is
submitted; the switch is deliberately not a general bypass for an in-progress
review.

## Mac App Store: listing first

The `mac-appstore` job **uploads only**. It does not submit, because there is
nothing submittable: the macOS product page has never been filled in. As of
0.2.11 it has 0 of 10 screenshots and an empty description, keywords, support
URL and copyright, and the version record has no App Store Review Detail.

That last one is not a soft failure. `deliver`'s metadata upload calls
`fetch_app_store_review_detail`, spaceship gets `{"data": null}` back for a
version that has never been submitted, and raises `No data` — killing the job
*before* the `.pkg` is uploaded (fastlane's own "Uploading the very first
version of my app yields `No data`"). That is what turned v0.2.11's release run
red while iOS, Google Play and the GitHub Release all succeeded. Passing
`skip_metadata: true` skips that call, so the binary reaches App Store Connect
and waits there.

To turn macOS on, in App Store Connect → Daccord → macOS App:

1. Add Mac screenshots (1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800) —
   these have to be real captures of the app on macOS.
2. Fill in description, keywords, support URL and copyright. The iOS listing is
   a reasonable starting point.
3. Fill in App Review Information (contact details), which is what creates the
   review-detail record `deliver` chokes on.
4. Attach the uploaded build and submit that first version by hand.

Then swap the `mac :appstore` lane's `upload_to_app_store` call back to
`submit_release(api_key: api_key, platform: "osx", metadata_path:
"fastlane/metadata/mac", pkg: pkg)`, and restore the "Generate What's New" step
in the `mac-appstore` job, and macOS releases the same way iOS does.

## Guideline 1.2: user-generated content

iOS 0.2.16 (build 160, reviewed 2026-08-30) was rejected under App Store
guideline *1.2 Safety: User-Generated Content*, which requires an app carrying
user content to present an EULA before a user registers **or** signs in, to let
users flag objectionable content, and to let them block abusive accounts.

Two of those had gaps, both since fixed:

- **The EULA never appeared.** The terms gate read `tos_enabled` from the
  server's `GET /settings`, which accordserver serves only to authenticated
  users — signed out it 401s, so the gate always resolved to "disabled", and it
  was wired into the Register tab alone. The app now carries terms of its own
  (`lib/features/authentication/models/app_terms.dart`) behind an unconditional
  gate ahead of the whole signed-out flow. A server's own ToS still shows
  alongside it when the server advertises one.
- **Reporting only existed on space messages.** The action was gated on a
  non-null space, and a DM pane passes none. Report now sits on every message
  surface — the pane, thread replies and the pinned list — and on user profiles
  and DM user menus, filing to the space's moderators where there is a space and
  to the account-level `/reports` route where there isn't. When neither route
  took the report the confirmation says so instead of promising a review.

Blocking was already in place (member popout, DM relationship actions) and is
now reachable from the two places a reviewer actually lands: the account-level
profile a DM user tap opens, and a visible overflow button in the 1:1 DM header
(the menu behind it was long-press/right-click only). A blocked account's
messages are filtered out of every message surface — see `MessageVisibility`
(`lib/features/messaging/utils/message_visibility.dart`) over
`BlockedUsersController` — so the promise the block makes is one the client
keeps rather than one only the server could.

Do not re-gate the terms on a server response: nothing a signed-out client can
read is guaranteed to be there, and the gate has to hold before any server is
chosen at all.

Apple also asks for a screen recording of all three precautions, attached under
**App Review Information → Notes** in App Store Connect, and it is reused by
later submissions.

### Recording the 1.2 precautions

Apple asks for the recording to be **captured on a physical device** (#293), so it
cannot be produced from a simulator, a desktop build, or the web build. Use iOS
Screen Recording from Control Centre, or QuickTime's *Movie Recording* with the
device tethered and selected as the source. OBS works too but adds nothing here.

**Build.** The recording must come from a build containing both 1.2 fixes — they
landed in `749c4b5a` and `5a47d319`, so anything at or after `5a47d319` is fine;
0.2.16 (160) has neither. Build the way the store lane does, so the recording
shows the surfaces a reviewer gets:

```bash
flutter run --release -d <device-id> --dart-define=APP_STORE=true
```

Without `APP_STORE=true` the Settings → Updates entry is present, and a
reviewer seeing the self-updater in a recording invites the 2.2 finding back
(see below). The Developer Mode toggle is desktop-only
(`isDeveloperModeAvailable` in `lib/shared/app_info.dart`) and never appears on
the phone or tablet this recording is captured on, regardless of this flag —
still build with it set, since the store lane always does.

**Reset first.** Terms acceptance is stored device-globally and keyed by
`appTermsVersion` (`lib/features/authentication/utils/terms_acceptance.dart`), so
an install that has already accepted will skip the gate. **Delete the app and
reinstall** before recording, or the first and most important beat is missing.

**Do not record against a public instance whose content you do not control.** A
channel's message history and member roster appear on camera, and a landing
channel naming another platform puts a 2.3.10 problem inside a 1.2 recording.
Use a space you control, seeded the way `tool/store_capture/seeded_space.dart`
seeds its fixture.

#### Shot list

Record in this order and note the timestamps — the App Review reply should point
at each one.

**1 — Terms before registering or signing in.** Launch the freshly installed
app. Before any server is chosen, the gate shows the app icon, the heading
**"Terms of Use & Community Guidelines"**, the scrollable terms body, an
**"Agree and continue"** button, and beneath it *"You must accept these terms to
create an account or sign in."* Scroll the body far enough to show the
zero-tolerance and abusive-user clauses. Tap **Agree and continue**.

This single beat covers both halves of Apple's requirement: the gate replaces
the whole signed-out flow, so it precedes Sign In and Register alike rather than
sitting on the Register tab. Show that the welcome screen appears only after
accepting.

Then show the terms remain reachable: on the auth screen, tap the terms link in
the *"By continuing you agree to …"* line. Later, Settings → About has the same
entry.

**2 — Flagging content in a space channel.** Open a space channel and long-press
another user's message. The menu includes **Report**. Tap it: the dialog is
titled **"Report message"** and reads *"Reports go to this space's moderators."*
Choose a reason from the **"Choose a reason"** picker and tap **Submit report**.

**3 — Flagging content in a direct message.** This is the context Apple named
separately and the one that previously had nothing, so record it explicitly.
Open a DM and long-press a message from the other person — **Report** is present
here too. The dialog now reads *"Reports outside a space go to the server
operator. Blocking takes effect immediately."*

Outside a space the **"Also block …"** checkbox starts **ticked** — with no
moderator to act on a DM, the block is what actually stops the abuse, so the
dialog defaults it on. Untick it unless you want this shot to end the
conversation: submitting with it set blocks the account, which empties the DM
of their messages and turns **Block** into **Unblock** in the menus shot 4
needs.

Also show reporting the person rather than the message, from any of: the DM
header's **⋮ "Conversation options"** button → **Report user**; tapping the
other person's avatar in the DM, which opens their profile carrying **Report
user** and **Block**; or, in a space, tapping an avatar to open the member
popout, which carries **Report user** beside **Block user**.

**4 — Blocking an abusive user.** In a space, tap a member's avatar and use
**Block user** in the popout. In a DM, use **Block** on the profile or the
header menu. Also worth showing: the report dialog's **"Also block …"**
checkbox, whose subtitle promises *"They can no longer message you, and their
messages are hidden from your view."* — a promise the client keeps via
`MessageVisibility`, so demonstrate a blocked account's messages disappearing
from the pane.

#### Before a retake

Shots 2–4 change state, so a second take does not start where the first one
did:

- **A reported message stays hidden.** Reporting hides it for good — persisted
  under `reported-hidden-message-ids` in the profile's settings box, with
  nothing in the UI to unhide it. The delete-and-reinstall above clears that
  box along with the terms acceptance, so a clean retake is free; carrying on
  without reinstalling needs a message you have not already reported.
- **A block is not.** It is a relationship on the account, held server-side, so
  reinstalling leaves it in place. Clear it from Friends → **Blocked** →
  **Unblock**, or shot 4 has nobody left to block.

#### After recording

- Attach it under **App Review Information → Notes** so later submissions carry
  it, alongside the guideline 2.2 reviewer walkthrough below.
- Reply to the 1.2 message on the App Review page with a timestamp per
  precaution.

## Guideline 2.3.10: what the iOS screenshots may show

iOS 0.2.16 (build 160, reviewed 2026-08-30 on an iPad Air 11-inch) was rejected
under *2.3.10 Performance: Accurate Metadata* for two things in the App Store
screenshots — both generated from `store-media/ios-generator/`:

- **A platform badge row.** Scene 6 of `template.html` rendered `iOS` /
  `Android` / `Desktop` / `Web` pills. Apple reads any non-iOS platform as
  "information about third-party platforms".
- **A painted status bar.** Every capture in `store-media/ios-generator/inner/`
  had a 9:41 + signal/Wi-Fi/battery bar drawn into it that is not iOS's.

Four rules for anything that regenerates these:

1. **No other platform, anywhere in the copy.** Not a badge, not a pill, not a
   subhead — no "Android", "Windows", "Linux", "desktop", "web", "all your
   devices", and no third-party product names either. Describe the iOS app only.
2. **No status bar at all.** The phone captures are cropped so the app content
   starts at its own app bar (740x1462, and 740x1350 for `t-06`); `--screen-ar`
   in `template.html` matches that, so the frame never stretches them. The
   tablet captures have none to begin with — they are photographed off a
   browser canvas, which has no OS chrome. If a capture is ever replaced, crop
   the status bar off rather than redrawing an iOS-looking one, and re-point
   `--screen-ar` at the new size.
3. **iPad gets its own frame aspect, and its own captures.**
   `body[data-device="ipad"]` frames `inner/tab-0N.png` at `--screen-ar:
   2732/2048` — a 13" iPad in **landscape**, because that is the orientation
   `resolveHomeLayout` puts all four panes in (rail + channel list + message
   column + member roster). The phone frame keeps `inner/t-0N.png` at
   `740/1462`. Neither frame may stretch or crop its set: each `--screen-ar`
   matches its captures exactly.
4. **Nothing may be half-visible.** No frame edge may saw through text or an
   icon — that reads as unfinished, which is what [guideline
   2.2](https://github.com/DaccordProject/daccord/issues/292) rejects for.
   `t-06` is cropped to 1350 rather than its full height for exactly this
   reason: its "Private / Encrypted / Open" row was truncated in the source
   asset, so the row could never be shown whole and is excluded instead.
   `tool/store_capture/verify_store_shots.dart` checks this mechanically —
   delivery sizes from each PNG's IHDR chunk, and a colour-transition count
   along every capture's four edge lines (content cutting an edge produces
   dozens; a pane boundary produces a handful).

### Regenerating

```bash
# 1. The tablet captures: the real app, real widgets, seeded offline data.
CHROME=<chromium> store-media/ios-generator/capture-inner.sh
# 2. The framed store renders.
CHROME=<chromium> store-media/ios-generator/render.sh
# 3. Install (out/ is scratch and is not committed).
cp store-media/ios-generator/out/ipad-0*.png   store-media/ios-ipad-13/
cp store-media/ios-generator/out/iphone-0*.png store-media/ios-iphone-6.5/
dart run tool/store_capture/verify_store_shots.dart
```

The sizes are fixed at iPhone 6.5" 1284x2778 and iPad 13" 2048x2732. Then look
at all twelve: the checks above catch sliced glyphs and wrong dimensions, not an
ugly screenshot.

### The tablet captures come from the app, not from a server

`store-media/ios-generator/capture-inner.sh` serves
`tool/store_capture/capture_app.dart` — the shipped widgets, wired to the
fictional fixture in `tool/store_capture/seeded_space.dart` through an in-memory
`MockClient` instead of a network transport — and photographs six scenes with a
headless Chromium at a 1366x1024 canvas at 2x. **No Accord server is
contacted**, so there is nothing to seed, no throwaway account to clean up, and
no live content to vet.

That fixture is the whole point. The 0.2.16 attempt tried to photograph
`chat.daccord.gg` and could not ship what was there: `#general` read *"just
trying to get daccord on the ios store"* and *"verity die"*, the roster said
`OFFLINE — 100` over names like `aa` and `34343434`, and the landing channel
`#rules` rendered the server's own rule 10 — a third-party platform name in 40px
type, the exact thing 2.3.10 rejected us for. A public instance's content is not
under our control and must not be photographed. **Do not point this harness at a
real server.**

Two rules for the fixture, both enforced by
`test/store_capture/seeded_content_test.dart` — a string scan that runs with the
normal suite, because the failure it prevents costs a review cycle:

- No third-party platform, product or company name may appear in any seeded
  string.
- Nothing may narrate the app's own distribution, review or store status.

That test is the only part of this harness in `flutter test`. The capture run
itself is on demand.

Notes on the scenes, so a regeneration reproduces them rather than reinventing
them:

- Each scene is a URL (`?scene=1` … `?scene=6`) and sets itself up through the
  app's own affordances — opening a tab, opening the member popout, opening the
  roles dialog, folding the roster away with the home screen's own
  `toggle_member_list`. Nothing draws a fake widget tree.
- The call scene reports a *joining* voice connection so `VoiceChannelView`
  mounts with the channel's chat beside the grid, and the grid's tiles come from
  the voice-state cache with no video track — the state a camera-off call is
  genuinely in. No media track is invented, and a screen share is not faked.
- The channel list is widened to 380pt (a user preference the divider drags).
  At the 220pt default an owner's five channel-list header actions leave the
  space name no room at all, which photographs as a broken header.

### Why a web entry point and not a widget test

`flutter test` starts the engine with `--use-test-fonts`, which resolves every
*unstyled* `TextStyle` to a box-drawing font. Message bodies are unstyled — on a
device they take the platform's font, because `markdown_viewer`'s renderer names
no family — so a widget test can only ever photograph message text as boxes.
Loading a real font under the test font's own family name does not displace it,
and `flutter run -d flutter-tester` has no font manager at all unless the host
has `/usr/share/fonts` populated. A browser supplies a real default font and a
real engine, so that is what the harness drives.

For the same reason `shoot_scenes.dart` talks the DevTools protocol instead of
using `chromium --screenshot` the way `render.sh` does: the CLI screenshot fires
on the load event, and `--virtual-time-budget` does not wait for a Flutter app's
first frame.

Screenshots are metadata, so a new upload in App Store Connect (Previews and
Screenshots → View All Sizes in Media Manager) needs no new build.
## Guideline 2.2: App Review Information notes

The same 0.2.16 review also returned *2.2 Performance: Beta Testing* — "your app
appears to be a pre-release, test, or trial version with a limited feature set".
Nothing in the binary is beta-labelled; the finding is about what a reviewer can
*see* in fifteen minutes on a fresh account. Two things drive it: reachable
surfaces that look unfinished, and a reviewer who never found the finished ones.
The second is fixed here — the walkthrough below goes in **App Store Connect →
App Review Information → Notes** with every submission, alongside the 1.2 screen
recording.

Keep it accurate rather than aspirational: a step that does not do what it says
is worse than no step at all. Re-walk it against the build being submitted
before pasting, and keep the demo account named in the Notes joined to a
populated space.

<!-- BEGIN reviewer notes — paste into App Review Information → Notes -->

```text
Daccord is a full chat client for Accord servers — self-hosted communities that
run their own instance, in the way an IRC or Matrix client connects to a server
the user chooses. It is not a demo or trial: every feature below is shipping and
works against the demo account supplied with this submission.

There is no Daccord-operated account system. The app connects to a server the
user picks, and the account lives on that server. The sign-in screen therefore
asks for a server URL as well as credentials.

SETUP (about 1 minute)
1. Launch the app. Accept the Terms of Use & Community Guidelines. (This gate is
   the guideline 1.2 EULA; it appears before registration and before sign-in.)
2. Tap "Browse Servers" to see the public server directory, then "Join" on a
   listing — or tap "Connect directly to a server" and enter a server URL by
   hand. Either path lands on the sign-in form.
3. Sign in with the demo credentials supplied with this submission. You will
   land in a space with channels, message history, and members.
4. A six-step guided tour starts automatically on first sign-in. Step through it
   or skip it; it can be replayed from Settings → "Replay the app tour" (in the
   Help & tour section — under the "Advanced" category on a wide/desktop
   window, or further down the flat list on a phone).

MESSAGING
5. Pick any text channel in the left sidebar. Type in the composer at the bottom
   and send. Messages appear live for every member over the server's WebSocket
   gateway.
6. Long-press (or right-click / hover) a message for the full action set: reply,
   react with an emoji, edit or delete your own message, pin, copy a link, and
   Report. Reply threads open in a side panel.
7. The "+" button in the composer attaches images, video, and files. Images and
   video preview inline; links unfurl into embeds.
8. The magnifier in the channel-list header searches messages and members across
   the space.
9. The pin icon in the channel header lists pinned messages; the bell sets that
   channel's notification level.

DIRECT MESSAGES AND FRIENDS
10. The speech-bubble icon at the top of the far-left rail opens Direct Messages.
    "Friends" manages friend requests and blocking; "New group" starts a group
    DM; "Message remote user" starts a DM with a user on another Accord server.
11. Report and Block are available on messages, on user profiles, and in the DM
    user menu — including in DMs, where there are no space moderators, in which
    case the report is filed to the server operator.

VOICE, VIDEO, AND SCREEN SHARING
12. Channels under a "Voice" category are voice channels. Open one and tap
    "Join Voice". Real-time audio, camera video, and screen sharing all run over
    WebRTC. Two devices (or a second browser signed in as another account) are
    needed to see a second participant.
13. In-call controls: mute, deafen, camera on/off, share screen, and disconnect.
    Screen sharing on iOS uses the system broadcast picker.
14. Settings → App → Voice & video settings has input/output device selection,
    input sensitivity, a live microphone test meter, video resolution, and
    bitrate controls.

SPACES, ROLES, AND MODERATION
15. The far-left rail lists the servers and spaces the account belongs to; "+"
    adds a server and the compass icon opens the public directory.
16. The member list on the right shows the roster grouped by role. Tap a member
    for their profile, with role badges, and — with permission — kick, ban, and
    timeout.
17. On a space you own or administer, the space header menu opens space settings:
    channel creation and ordering, per-channel permission overrides, role
    creation and permission editing, invites, the ban list, the audit log,
    custom emoji, a soundboard, and ownership transfer. These are permission
    gated: a member without the permission does not see the entry at all, which
    is why they are not visible on a brand-new account. Sign in as the demo
    admin account (also supplied) to reach them.
18. Server administrators additionally get a "Server administration" entry in
    Settings → Account, with instance-wide user, space, and report management.

ACCOUNT AND PRIVACY
19. Settings → Account has profile editing, password and two-factor
    authentication, "Request Data Export" (a full JSON copy of the account's
    data), per-server "Leave & Delete", and account deletion.
20. Settings → App covers themes, accent colour, message density, UI scale,
    notifications, and sounds.

SELF-HOSTING
21. Anyone can run their own Accord server and connect this app to it — that is
    the point of the product, and why the server URL is part of signing in. The
    public directory is one way to find a community; "Connect directly to a
    server" is the other, and neither depends on infrastructure we operate.
    Server software: https://github.com/DaccordProject/accordserver
```

<!-- END reviewer notes -->

## Guideline 2.5.1: no libmpv in the iOS build

iOS 0.2.6 (build 141, submitted 2026-07-09) was **rejected** under App Store
guideline *2.5.1 Performance: Software Requirements* — Apple's automated binary
scan reported "the app uses or references non-public or deprecated APIs".

The offender was `media_kit_libs_ios_video`, which vendors a prebuilt
`Mpv.xcframework` (libmpv + FFmpeg). Of everything linked into the iOS app it
was the only binary referencing APIs an iOS app may not use:

```
$ llvm-nm -u Mpv.framework/Mpv | grep -E '^_(fork|execve|setsid|waitpid|kill)$'
_execve _fork _kill _setsid _waitpid
```

— mpv's POSIX subprocess and TTY layer (`tcgetattr`/`tcsetattr`/`tcgetpgrp`,
`shm_open`) — plus `EAGLContext` and `CVOpenGLESTextureCache*`, i.e. OpenGL ES,
which Apple deprecated in iOS 12. `media_kit_video`'s own iOS plugin renders
through that same OpenGL ES path and compiles with `GL_SILENCE_DEPRECATION`.
Every other embedded binary (WebRTC, the FFmpeg libs, libxml2, …) was clean.

So **iOS does not get media_kit**. `pubspec.yaml` lists media_kit's native libs
per platform (`media_kit_libs_android_video`, `_macos_video`, `_windows_video`,
`_linux`) instead of the `media_kit_libs_video` umbrella, deliberately omitting
the iOS package. With no `media_kit_libs_ios_*` in `pubspec.lock`,
`media_kit_video`'s iOS podspec falls back to `Classes/stub` — a no-op plugin
registrar — and nothing of mpv reaches the binary.

Video attachments on iOS play through `package:video_player`'s AVFoundation
backend instead (`lib/features/messaging/views/inline_video_player.dart`);
`main.dart` passes `iOS: false` to `VideoPlayerMediaKit.ensureInitialized` so
media_kit is never registered as the `video_player` backend there. The trade-off
is container support: AVFoundation handles `mp4`/`m4v`/`mov`, so on iOS the
other formats in `attachment_types.dart` are shown as a download rather than a
player that would fail on the first frame.

**Do not re-add `media_kit_libs_video` (or `media_kit_libs_ios_video`) to
`pubspec.yaml`** — it silently puts libmpv back in the iOS binary and the next
submission gets the same automated rejection.
