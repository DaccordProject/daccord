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
2. **No status bar at all.** The inner captures are cropped so the app content
   starts at its own app bar (740x1462, and 740x1350 for `t-06`); `--screen-ar`
   in `template.html` matches that, so the frame never stretches them. If a
   capture is ever replaced, crop the status bar off rather than redrawing an
   iOS-looking one, and re-point `--screen-ar` at the new size.
3. **iPad gets its own frame aspect.** `body[data-device="ipad"]` uses an iPad
   portrait `--screen-ar` (1640/2360), not the phone's, so the 2048x2732 renders
   do not read as an iPhone mockup on an iPad product page. Scenes may set
   `focus` to choose which end of the taller phone capture that wider frame
   keeps.
4. **Nothing may be half-visible.** No frame edge may saw through text or an
   icon — that reads as unfinished, which is what [guideline
   2.2](https://github.com/DaccordProject/daccord/issues/292) rejects for. Every
   crop edge has to land in flat pixels. `t-06` is cropped to 1350 rather than
   its full height for exactly this reason: its "Private / Encrypted / Open"
   row was truncated in the source asset, so the row could never be shown
   whole and is excluded instead. After a regeneration, check both the top and
   the bottom edge of all twelve, including the two iPad scenes anchored
   `center bottom`.

Regenerate with `CHROME=<chromium> store-media/ios-generator/render.sh`, then
copy `store-media/ios-generator/out/` over `store-media/ios-iphone-6.5/` and
`store-media/ios-ipad-13/` — `out/` itself is scratch and is not committed. The
sizes are fixed at iPhone 6.5" 1284x2778 and iPad 13" 2048x2732.

Still outstanding: the inner captures are illustrative compositions of the app's
**phone** layout, and `resolveHomeLayout` puts a real iPad in the wide layout
(rail + channel list + message column + member roster), which they do not show.
It shows: `ipad-02` ends with ~14% of the tablet screen empty below the `AFK`
row, because a phone-width channel list is all that capture has to fill a
tablet-width frame with. Real wide-layout captures put a message column and a
member roster in that space, so they fix it structurally — do not fill it with
decoration in the meantime. The per-device `--screen-ar`, `--dev-w` and radius
variables exist so a new capture set can be dropped in by editing them alone.

**The blocker is content, not the layout.** The app was built for web off
`fix/292-ipad-layout` and driven headless at 1180x820 against
`chat.daccord.gg`: the wide layout renders correctly and would make a good
tablet screenshot. What is on the public instance cannot be shipped. `#general`
— the channel a store shot would use — currently reads *"just trying to get
daccord on the ios store"*, *"verity die"*, and a leftover *"Hello from the
Daccord Flutter client — App Review walkthrough."*; the roster header says
`OFFLINE — 100` over names like `123`, `34343434`, `aa` and
`aidsonaburgerbun`; and the default landing channel `#rules` renders the
server's own rule 10, *"Discord's-not-the-point rules still apply"* — the exact
third-party platform reference 2.3.10 rejected us for, in 40px type. Capturing
that would trade one accurate-metadata problem for a worse one.

Real captures therefore need a **purpose-seeded space**, not the public
instance: 5-7 spaces so the rail reads as multi-server; categorised channels
with one unread badge and one populated voice channel; 6-8 written `#general`
messages from named accounts with avatars, covering a reply, an image, reactions
and a mention; ~15 named members mostly **online**, grouped Owner / Moderators /
Members, with one profile card open; ownership of the space so Roles and
permissions are reachable; and, for the voice scene, 2-3 clients genuinely
connected with one sharing a screen — that last one cannot be produced from a
single headless browser. Note also that a fresh account is auto-joined to the
public space, so it has to be left before capture, and that the landing channel
must not be one whose content names another platform.

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
