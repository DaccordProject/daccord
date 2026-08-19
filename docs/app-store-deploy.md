# App / Play Store deployment

The `Release` workflow (`.github/workflows/release.yml`) builds signed store
builds and takes them all the way to public release on both stores — a tag push
needs no follow-up clicks in App Store Connect or the Play Console:

| Target | Job | Lane | Lands in |
|--------|-----|------|----------|
| iOS App Store | `ios-appstore` | `fastlane ios appstore` | App Store (submitted for review, auto-release) |
| Mac App Store | `mac-appstore` | `fastlane mac appstore` | Mac App Store (submitted for review, auto-release) |
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
| `SENTRY_DSN` | (optional, already used) GlitchTip DSN baked into builds |

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
field CI delivers; everything else stays managed in App Store Connect.

The output is generated, not committed — `fastlane/metadata/` is gitignored.
Both Apple jobs check out with `fetch-depth: 0` because a shallow clone has no
previous tag to diff against; if one is ever missing the script falls back to a
generic note instead of failing the release.

To hand-write the notes for a release instead, edit the two `release_notes.txt`
paths after the generate step — or drop the step and commit the files.

## What's still manual

Nothing per release. A tag push submits both Apple builds for review with
automatic release on approval, and ships the Android build to `production`.
What remains is **per-app, set once**, and every later release reuses it:

- **Apple:** screenshots, the App Privacy questionnaire, and the age rating, in
  App Store Connect. A brand-new app also needs its first release created by
  hand before API submissions work.
- **Google Play:** the store listing, content rating and Data safety
  declarations — already complete for this app.

What no CI can remove is the stores' own review. Apple's review typically takes
about a day; the build sits in *Waiting for Review* → *In Review* and then goes
live on its own (`automatic_release: true`). Google's review gates the
`production` rollout the same way. "All the way to production" means *submitted
and set to ship*, not *live within minutes*.
