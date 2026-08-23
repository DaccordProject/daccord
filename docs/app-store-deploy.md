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

Direct-download (non-store) signing — the notarized DMG, Windows Authenticode
and the release checksums/GPG signature — is covered separately in
[release-signing.md](release-signing.md), including what happens when those
secrets are absent.

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

1. **Create the upload keystore** (once) and set the four `ANDROID_*` secrets:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
     -validity 10000 -alias upload
   base64 -i upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
   gh secret set ANDROID_KEYSTORE_PASSWORD   # store password
   gh secret set ANDROID_KEY_ALIAS           # "upload"
   gh secret set ANDROID_KEY_PASSWORD        # key password
   ```
   Keep `upload-keystore.jks` safe and out of git (`android/.gitignore` already
   excludes `*.keystore` / `key.properties`). Enable **Play App Signing** in the
   Play Console so Google manages the app signing key; this upload key only
   needs to match what Play expects for uploads.
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

To hand-write the notes for a release instead, edit the two `release_notes.txt`
paths after the generate step — or drop the step and commit the files.

## What's still manual

Nothing per release for **iOS and Android**. A tag push submits the iOS build
for review with automatic release on approval, and ships the Android build to
`production`. What remains there is **per-app, set once**, and every later
release reuses it:

- **iOS:** screenshots, the App Privacy questionnaire, and the age rating, in
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
