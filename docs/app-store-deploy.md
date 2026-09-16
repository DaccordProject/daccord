# App / Play Store deployment

The `Release` workflow (`.github/workflows/release.yml`) builds signed store
builds. iOS and Android go all the way to public release on a tag push; macOS is
uploaded but not submitted ([below](#mac-app-store-listing-first)).

| Target | Job | Lane | Lands in |
|--------|-----|------|----------|
| iOS App Store | `ios-appstore` | `fastlane ios appstore` | App Store (submitted for review, auto-release) |
| Mac App Store | `mac-appstore` | `fastlane mac appstore` | App Store Connect (uploaded only — **not** submitted) |
| Notarized DMG | `build` (macOS) | `fastlane mac dmg` | GitHub Release (direct download) |
| Google Play | `android-play` | `fastlane android play` | Play Console (AAB → `production` track) |

Direct-download signing (DMG, Windows Authenticode, Android APK identity,
checksums/GPG) is in [release-signing.md](release-signing.md).

- Runs on a `v*` tag push, or **workflow_dispatch** with `deploy_ios` /
  `deploy_mac` / `deploy_android` toggles.
- Apple auth: App Store Connect API key. Play auth: service-account JSON. No
  interactive logins in CI.
- The AAB is signed with the upload key; Play App Signing re-signs it.
  `PLAY_TRACK=production` and `PLAY_RELEASE_STATUS=completed` are hardcoded in
  the workflow — staging to testers requires editing `release.yml`. Any
  leftover `PLAY_TRACK` / `PLAY_RELEASE_STATUS` repo variables are ignored.
- Store builds use `--dart-define=APP_STORE=true` (`kAppStoreBuild`), which
  disables the GitHub self-updater (store guidelines forbid it). The DMG and
  sideload APK keep it.

## Required GitHub secrets

Settings → Secrets and variables → Actions.

| Secret | What it is |
|--------|------------|
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_KEY_P8_BASE64` | base64 of `AuthKey_<id>.p8` |
| `APPLE_TEAM_ID` | 10-char Apple Developer team ID |
| `CERT_P12_PASSWORD` | password shared by every `.p12` below |
| `APPLE_DIST_CERT_P12` | base64 `.p12` — Apple Distribution (iOS + Mac app) |
| `MAC_INSTALLER_CERT_P12` | base64 `.p12` — Mac Installer Distribution (`.pkg`) |
| `DEVELOPER_ID_CERT_P12` | base64 `.p12` — Developer ID Application (DMG) |
| `IOS_PROFILE_BASE64` / `IOS_PROFILE_NAME` | iOS App Store provisioning profile and its name |
| `MAC_PROFILE_BASE64` / `MAC_PROFILE_NAME` | Mac App Store provisioning profile and its name |

### Universal Links

The iOS App ID must enable **Associated Domains**. The app claims
`applinks:www.daccord.gg`; regenerate `IOS_PROFILE_BASE64` after enabling the
capability. `scripts/bootstrap-signing.sh` verifies the decoded profile permits
that domain, including profiles granting `*` rather than listing each domain.

Before merging/releasing the entitlement and new share links, verify:

- `https://www.daccord.gg/.well-known/apple-app-site-association` is public,
  serves JSON without redirects, and associates `/open/*` with the signed
  app's application identifier (App ID prefix plus bundle ID).
- `/open/connect/...` and `/open/navigate/...` provide a browser fallback.
- A freshly signed iOS install opens a link from another app and navigates to
  the intended server/channel; also test the fallback without the app installed.

The custom `daccord://` scheme remains accepted. Parser tests cover the HTTPS
host/path allowlist, but cannot establish that Apple's association or signing
configuration is deployed. See [Apple's Universal Links documentation](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/UniversalLinks.html).

### Google Play (`android-play` job)

| Secret | What it is |
|--------|------------|
| `PLAY_SERVICE_ACCOUNT_JSON` | JSON key of a Google Cloud service account with Play Console access |
| `ANDROID_KEYSTORE_BASE64` | base64 of the upload keystore (`.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | store password |
| `ANDROID_KEY_ALIAS` | upload key alias |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_SIGNING_CERT_SHA256` | upload certificate SHA-256; pins APK and AAB identity |

Repo variable `IOS_REPLACE_UNRESOLVED` — see [retrying](#retrying-an-ios-app-store-release).

## One-time human steps

### Apple

1. App Store Connect → Users and Access → Integrations → App Store Connect API:
   create a key (Admin or App Manager). The `.p8` downloads **once**.
2. On a Mac: `scripts/bootstrap-signing.sh /path/to/AuthKey_XXXX.p8` — creates
   the certificates and profiles and prints/sets the `gh secret set` commands.
   The Developer ID certificate must be created by the account holder.
3. App record + bundle ID `com.cattrall.daccord` already exist.

### Google Play

1. Upload keystore (once):
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
   Keep the `.jks` out of git (`.gitignore` covers `*.jks`, `*.keystore`,
   `android/key.properties`). Enable **Play App Signing**.
2. Google Cloud → IAM → Service Accounts: create one and a JSON key; in Play
   Console → Users and permissions → Invite new user, grant it *Release to
   testing tracks* + *Release apps to production*.
   ```bash
   gh secret set PLAY_SERVICE_ACCOUNT_JSON < play-service-account.json
   ```
3. Package `com.daccord_projects.daccord` exists with listing and App content
   done. For a brand-new app the first AAB must be uploaded by hand (the API
   rejects it until a release exists).

## Triggering

- **Real release:** push a tag matching `pubspec.yaml` (`git tag vX.Y.Z && git push --tags`).
- **Store deploy only:** Actions → Release → Run workflow, pick the branch,
  toggle `deploy_ios` / `deploy_mac` / `deploy_android`.

## Release notes ("What's New")

Apple rejects a submission without release notes, so the iOS job runs
`dist/app-store-release-notes.sh`: `feat`/`fix`/`perf` commit subjects since the
previous stable tag (RCs skipped), written to
`fastlane/metadata/ios/en-US/release_notes.txt` (generated, gitignored). The job
needs `fetch-depth: 0`; with no previous tag the script falls back to a generic
note. The Mac job delivers no metadata.

To hand-write notes, put a marker and copy in `dist/release-notes.txt`:

```text
# Release version: X.Y.Z
• A user-visible improvement.
```

The marker must match `pubspec.yaml` and the `v*` tag or the job fails before
upload. Return the file to comment-only after the release, or the next version
fails. Commit subjects are maintainer-facing and App Review reads the notes —
hand-write when subjects would read badly.

The tracked files in `fastlane/metadata/ios/en-US` (support, privacy, marketing
URLs) are uploaded by the iOS lane; keep them aligned with
`lib/shared/app_info.dart`.

## What's still manual

Per release, nothing for iOS/Android. Set once per app and reused:

- **iOS:** screenshots (see [2.3.10](#guideline-2310-what-the-ios-screenshots-may-show)),
  App Privacy questionnaire, age rating, and App Review Information notes
  ([1.2 recording](#recording-the-12-precautions),
  [2.2 walkthrough](#guideline-22-app-review-information-notes)).
- **Google Play:** listing, content rating, Data safety — complete.
- **macOS:** see next section.

Store review still gates going live (Apple ~1 day, then auto-release).

### Retrying an iOS App Store release

The iOS lane checks App Store Connect first. If the same version **and build**
is *Waiting for Review* / *In Review* with release type **After Approval**, the
run succeeds without re-uploading or resubmitting. Rerunning the same Actions
run reuses its build number (idempotent); a **new** run for the same version
gets a new build number and fails against the in-review build. The lane also
fails on another version/build in review, a cancelling review, unresolved
issues, manual release, or inconsistent ASC state.

To replace a binary after App Review sets `UNRESOLVED_ISSUES`: set repo variable
`IOS_REPLACE_UNRESOLVED=true` (the lane cancels the rejected submission, uploads
and resubmits), then **remove it** once submitted.

## Mac App Store: listing first

`mac-appstore` **uploads only** (`upload_to_app_store` with `skip_metadata:
true`). The macOS product page is empty and has no App Store Review Detail;
deliver's metadata upload then raises `No data` before the `.pkg` uploads.

The lane explicitly passes `fastlane/metadata/mac` and
`fastlane/screenshots/mac`: fastlane validates folder names even when skipped,
and the shared parent's `ios` folder is not a language code. The folders may be
absent. CI checks this with
`bundle exec ruby fastlane/test/mac_upload_metadata_test.rb`.

**Recovering a failed Mac upload** after fixing tooling on `master`: run Release
on `master` with `deploy_mac=true`, `deploy_ios=false`, `deploy_android=false`
(new build number, Mac only). Rerunning the old tagged run uses the old
Fastfile. The reusable CI call runs test gates but skips artifact builds unless
`build_artifacts=true`.

To enable macOS submission, in App Store Connect → Daccord → macOS App:

1. Add real Mac screenshots (1280×800, 1440×900, 2560×1600 or 2880×1800).
2. Fill in description, keywords, support URL, copyright.
3. Fill in App Review Information (creates the review-detail record).
4. Attach the uploaded build and submit the first version by hand.

Then change the `mac :appstore` lane back to `submit_release(api_key: api_key,
platform: "osx", metadata_path: "fastlane/metadata/mac", pkg: pkg)` and add a
"Generate What's New" step to the `mac-appstore` job.

## Guideline 1.2: user-generated content

Apple requires an EULA before registering **or** signing in, content
flagging, and user blocking. The client implements:

- **Terms gate:** app-owned terms (`lib/features/authentication/models/app_terms.dart`)
  gate the whole signed-out flow unconditionally; a server's own ToS shows
  alongside when advertised. **Do not gate the terms on a server response** —
  signed-out `GET /settings` 401s, which previously hid the gate.
- **Report:** on every message surface (pane, threads, pinned) and user
  profiles/DM menus; files to space moderators, or account-level `/reports`
  outside a space.
- **Block:** member popout, DM profile, DM header overflow; blocked users'
  messages are filtered by `MessageVisibility`
  (`lib/features/messaging/utils/message_visibility.dart`) over
  `BlockedUsersController`.

Apple wants a screen recording of all three under **App Review Information →
Notes**.

### Recording the 1.2 precautions

Must be captured on a **physical device** (#293) — not simulator, desktop or web.
Use iOS Screen Recording or QuickTime with the tethered device.

**Build** like the store lane, so the self-updater is hidden (showing it invites
a 2.2 finding):

```bash
flutter run --release -d <device-id> --dart-define=APP_STORE=true
```

**No Mac or device:** dispatch **iOS .ipa artifact**
(`.github/workflows/ios-ipa.yml`, `fastlane ios ipa`) — same build and signing as
`ios-appstore`, uploaded as `Daccord-iOS.ipa`. Then either:

- **TestFlight to a borrowed iPhone**, recorded via Control Centre; or
- **A real-device cloud** (BrowserStack App Live, Sauce Labs, AWS Device Farm),
  which resigns the `.ipa`. The Accord server must be reachable from their
  datacentre. Their MP4 carries no device provenance, so screenshot the
  provider's **Device information** panel (model + iOS version) first and name
  model, OS, provider and build in the reply.

A simulator capture (`ios-simulator.yml`, `xcrun simctl io <udid> recordVideo`)
is a last resort and must be labelled as such — expect to be asked again.

**Reset first:** terms acceptance is stored device-globally by `appTermsVersion`
(`lib/features/authentication/utils/terms_acceptance.dart`). **Delete and
reinstall** or the gate won't show.

**Use a server you control**, seeded like `tool/store_capture/seeded_space.dart`
— on-camera content naming another platform creates a 2.3.10 problem.

**Verify `POST /api/v1/reports` works on that instance** before the final take.
Without it, a DM report confirms *"Done — The message is now hidden for you."*
instead of **"Report submitted"**, which does not prove flagging. The accordserver
image pinned by CI fixtures lacks this route.

#### Shot list

Note timestamps for each.

1. **Terms before registering or signing in.** Fresh launch shows **"Terms of
   Use & Community Guidelines"**, the zero-tolerance summary, the terms body,
   **"Agree and continue"**, and *"You must accept these terms to create an
   account or sign in."* Scroll to sections 4 and 5 (zero tolerance, abusive
   users). Accept; show the welcome screen only appears afterwards. Show the
   terms link in *"By continuing you agree to …"* (also Settings → About). Sign
   in and **Skip** the "Welcome to Daccord" tour.
2. **Flag in a space channel.** Long-press another user's message → **Report** →
   **"Report message"** (*"Reports go to this space's moderators."*) → pick a
   reason → **Submit report**.
3. **Flag in a DM.** Long-press the other person's message → **Report** (*"Reports
   outside a space go to the server operator. Blocking takes effect
   immediately."*). **"Also block …"** starts ticked here — untick it or shot 4
   loses its target. Must end on **"Report submitted"**. Also show **Report
   user** via the DM header **⋮ "Conversation options"**, the DM avatar profile,
   or a space member popout.
4. **Block.** Space: avatar → **Block user**. DM: **Block** on profile or header
   menu. Show a blocked account's messages disappearing from the pane.

#### Before a retake

- Reported messages stay hidden (`reported-hidden-message-ids` in the settings
  box, no UI to unhide) — reinstalling clears this.
- Blocks are server-side and survive reinstall: Friends → **Blocked** →
  **Unblock**.

#### After recording

Attach under **App Review Information → Notes** (with the 2.2 walkthrough) and
reply to the 1.2 message with timestamps. For a device-cloud capture:

> Recorded on a physical [iPhone model] running [iOS version] through
> [real-device-cloud provider], using Daccord [version] ([build]). The pointer
> is the provider's remote-control overlay. Terms before authentication:
> [00:00–00:00]. Space-message reporting and “Report submitted” confirmation:
> [00:00–00:00]. Direct-message reporting and “Report submitted” confirmation:
> [00:00–00:00]. Blocking and the blocked user's messages disappearing:
> [00:00–00:00].

## Guideline 2.3.10: what the iOS screenshots may show

Screenshots come from `store-media/ios-generator/`. A previous submission was
rejected for a platform badge row and a painted-on status bar. Rules:

1. **No other platform anywhere** — no "Android", "Windows", "Linux", "desktop",
   "web", "all your devices", and no third-party product names.
2. **No status bar.** Phone captures are cropped to start at the app bar
   (740x1462; 740x1350 for `t-06`), matching `--screen-ar` in `template.html`.
   If a capture is replaced, crop the bar off and update `--screen-ar`.
3. **iPad has its own frame and captures:** `body[data-device="ipad"]` frames
   `inner/tab-0N.png` at `--screen-ar: 2732/2048` (13" landscape, all four panes);
   phone frames `inner/t-0N.png` at `740/1462`. Never stretch or crop.
4. **Nothing half-visible** at a frame edge (reads as unfinished → 2.2). `t-06`
   is cropped to 1350 for this reason. `tool/store_capture/verify_store_shots.dart`
   checks sizes and edge-cutting.

### Regenerating

```bash
# 1. Tablet captures: real app, seeded offline data.
CHROME=<chromium> store-media/ios-generator/capture-inner.sh
# 2. Framed store renders.
CHROME=<chromium> store-media/ios-generator/render.sh
# 3. Install (out/ is scratch, not committed).
cp store-media/ios-generator/out/ipad-0*.png   store-media/ios-ipad-13/
cp store-media/ios-generator/out/iphone-0*.png store-media/ios-iphone-6.5/
dart run tool/store_capture/verify_store_shots.dart
```

Sizes: iPhone 6.5" 1284x2778, iPad 13" 2048x2732. Eyeball all twelve afterwards.
Uploading new screenshots (Media Manager) needs no new build.

### The tablet captures come from the app, not from a server

`capture-inner.sh` serves `tool/store_capture/capture_app.dart` — shipped widgets
over the fictional fixture in `tool/store_capture/seeded_space.dart` via an
in-memory `MockClient` — and photographs `?scene=1`…`?scene=6` in headless
Chromium (1366x1024 @2x). **No server is contacted. Do not point this harness at
a real server** — public-instance content previously included off-topic chatter
and a third-party platform name.

`test/store_capture/seeded_content_test.dart` (in `flutter test`) enforces: no
third-party platform/product/company names in seeded strings, and nothing
narrating the app's distribution/review/store status.

Scene notes: scenes set themselves up via the app's own affordances (no fake
widgets); the call scene uses a *joining* voice connection with camera-off tiles
(no faked media or screen share); the channel list is widened to 380pt so the
space name isn't crushed by header actions.

It is a web entry point, not a widget test, because `flutter test` renders
unstyled text (message bodies) with a box-glyph test font. `shoot_scenes.dart`
uses DevTools protocol because `chromium --screenshot` fires before Flutter's
first frame.

## Guideline 2.2: App Review Information notes

A *2.2 Beta Testing* rejection stemmed from reviewers not finding finished
features. Paste the walkthrough below into **App Store Connect → App Review
Information → Notes** with every submission. Re-walk it against the build first
— an inaccurate step is worse than none — and keep the demo account joined to a
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

`media_kit_libs_ios_video` vendors `Mpv.xcframework`, which references
non-public/deprecated APIs (`fork`/`execve`/…, OpenGL ES) and got the app
rejected by Apple's automated scan. So iOS does not get media_kit:

- `pubspec.yaml` lists per-platform libs (`media_kit_libs_android_video`,
  `_macos_video`, `_windows_video`, `_linux`) instead of the umbrella, so
  `media_kit_video`'s iOS podspec falls back to its stub.
- iOS plays video via `video_player`'s AVFoundation backend
  (`lib/features/messaging/views/inline_video_player.dart`); `main.dart` passes
  `iOS: false` to `VideoPlayerMediaKit.ensureInitialized`. Only
  `mp4`/`m4v`/`mov` play; other formats show as downloads.

**Do not add `media_kit_libs_video` or `media_kit_libs_ios_video` to
`pubspec.yaml`** — the next submission gets the same rejection.
