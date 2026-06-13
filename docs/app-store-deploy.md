# App Store deployment

The `Release` workflow (`.github/workflows/release.yml`) can build and upload
signed Apple builds to App Store Connect:

| Target | Job | Lane | Lands in |
|--------|-----|------|----------|
| iOS App Store | `ios-appstore` | `fastlane ios beta` | TestFlight / App Store Connect |
| Mac App Store | `mac-appstore` | `fastlane mac appstore` | App Store Connect (sandboxed `.pkg`) |
| Notarized DMG | `build` (macOS) | `fastlane mac dmg` | GitHub Release (direct download) |

These run on a **tag push** (`v*`) and on **workflow_dispatch** (with
`deploy_ios` / `deploy_mac` toggles, handy for testing without cutting a real
release). Auth + upload use an **App Store Connect API key** — no Apple ID or
2FA in CI.

The store builds (`ios-appstore`, `mac-appstore`) are compiled with
`--dart-define=APP_STORE=true`, which sets `kAppStoreBuild` and disables the
in-app GitHub self-updater (App Store guidelines forbid it; the Mac build is
also sandboxed). The DMG build keeps the updater.

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

## One-time human steps

1. **Create the API key** in App Store Connect → Users and Access →
   Integrations → App Store Connect API (role: Admin or App Manager). Download
   the `.p8` (Apple lets you download it **once**).
2. Run `scripts/bootstrap-signing.sh /path/to/AuthKey_XXXX.p8` on a Mac — it
   creates the three certificates and two provisioning profiles via the API key
   and sets all the secrets above with `gh`.
3. App record + bundle ID `com.cattrall.daccord` must already exist (they do —
   see the App Store Connect listing).

## Triggering

- **Real release:** push a tag matching `pubspec.yaml` (`git tag v0.2.3 && git push --tags`).
- **Test the App Store deploy only:** Actions → Release → Run workflow, pick the
  branch, and toggle `deploy_ios` / `deploy_mac`.

## What's still manual on Apple's side

CI uploads the **build**. Promoting it to public release (selecting the build on
the version page and clicking *Add for Review* → *Submit*) is a human step in
App Store Connect, as are screenshots, the App Privacy questionnaire, and age
rating.
