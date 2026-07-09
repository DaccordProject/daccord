# App / Play Store deployment

The `Release` workflow (`.github/workflows/release.yml`) can build and upload
signed store builds to Apple's App Store Connect and to Google Play:

| Target | Job | Lane | Lands in |
|--------|-----|------|----------|
| iOS App Store | `ios-appstore` | `fastlane ios beta` | TestFlight / App Store Connect |
| Mac App Store | `mac-appstore` | `fastlane mac appstore` | App Store Connect (sandboxed `.pkg`) |
| Notarized DMG | `build` (macOS) | `fastlane mac dmg` | GitHub Release (direct download) |
| Google Play | `android-play` | `fastlane android play` | Play Console (AAB → `production` track) |

These run on a **tag push** (`v*`) and on **workflow_dispatch** (with
`deploy_ios` / `deploy_mac` / `deploy_android` toggles, handy for testing
without cutting a real release). Apple auth uses an **App Store Connect API
key**; Google Play auth uses a **service-account JSON** — no interactive logins
or 2FA in CI.

The Play build is signed with the **upload key** (from secrets); Google's
**Play App Signing** re-signs it with the app signing key for delivery. It's
released to the **`production`** track by default (`completed`), so a tagged
release ships to all users immediately — change the `PLAY_TRACK` /
`PLAY_RELEASE_STATUS` repo variables for a different rollout (e.g.
`PLAY_TRACK=internal` to stage to testers, or `PLAY_RELEASE_STATUS=draft` to
upload without distributing). Listing metadata and graphics live in the Play
Console and are not touched by the upload.

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

Optional repo **variables** (Settings → Secrets and variables → Actions →
Variables) tune the rollout: `PLAY_TRACK` (default `production`) and
`PLAY_RELEASE_STATUS` (default `completed`, releasing to that track immediately;
set `draft` to upload without distributing).

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
   `production` track (override with `PLAY_TRACK` to stage to a testing track).

## Triggering

- **Real release:** push a tag matching `pubspec.yaml` (`git tag v0.2.3 && git push --tags`).
- **Test a store deploy only:** Actions → Release → Run workflow, pick the
  branch, and toggle `deploy_ios` / `deploy_mac` / `deploy_android`.

## What's still manual on Apple's side

CI uploads the **build**. Promoting it to public release is a human step:

- **Apple:** select the build on the version page and click *Add for Review* →
  *Submit* in App Store Connect (screenshots, App Privacy questionnaire, and age
  rating are also manual there).
- **Google Play:** the AAB is released to the **`production`** track and goes
  live once Google finishes its review (no manual promotion needed). Set
  `PLAY_TRACK=internal` to route a build to testers instead. The store listing,
  content rating, and Data safety declarations are already complete.
