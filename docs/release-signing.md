# Release signing, notarization & checksums

How tagged-release artifacts from `.github/workflows/release.yml` are signed,
which secrets are required, and how verification blocks bad executables.

Tagged macOS, Windows and Android legs **fail closed**: missing credentials or
failed signing/notarization/trust/fingerprint checks block the GitHub Release.
Local builds still work without keys (Gradle and the Windows scripts have
non-strict fallbacks outside the tagged workflow).

## Reviewing release action updates

Every external action in `release.yml` is pinned to a full commit SHA with a
version comment (the local `ci.yml` is the only exception). Dependabot
(`.github/dependabot.yml`) opens weekly update PRs. Before merging one:

1. Read upstream release notes; confirm the SHA belongs to the expected repo and tag.
2. Review changes to `action.yml`, dependencies, inputs, permissions, executed
   code, and handling of signing/publishing secrets.
3. Keep the 40-character SHA in `uses:` and update the version comment; never
   use a branch or movable tag.
4. Run workflow YAML/action-reference checks; test in a non-publishing
   environment if inputs or execution change.

## How the gating works

`secrets` can't be used in job-level `if:`, so each job computes `'true'`/`'false'`
flags in `env:` and a preflight step fails the leg when its flag isn't true:

```yaml
jobs:
  build:
    env:
      WINDOWS_SIGN_AVAILABLE: ${{ secrets.WINDOWS_CERT_PFX_BASE64 != '' || (secrets.SIMPLYSIGN_USER != '' && secrets.SIMPLYSIGN_TOTP_SECRET != '') }}
    steps:
      - name: Require stable release-signing credentials
        if: matrix.platform == 'windows' && env.WINDOWS_SIGN_AVAILABLE != 'true'
        run: exit 1
```

Then outputs are verified: macOS `codesign`/`stapler`/`spctl`; Windows
`signtool verify /pa`; Android signature + certificate SHA-256 pin.

| Flag | Job | True when |
|------|-----|-----------|
| `DEVID_AVAILABLE` | `build` | all six Developer ID/notarization secrets are set |
| `WINDOWS_SIGN_AVAILABLE` | `build` | `WINDOWS_CERT_PFX_BASE64` is set, **or** both `SIMPLYSIGN_*` secrets are |
| `SIMPLYSIGN_AVAILABLE` | `build` | no PFX is set and both `SIMPLYSIGN_*` secrets are |
| `ANDROID_SIGN_AVAILABLE` | `build`, `android-play` | all four keystore values and `ANDROID_SIGNING_CERT_SHA256` are set |
| `GPG_AVAILABLE` | `release` | `GPG_PRIVATE_KEY` is set |

`linux` artifacts (`.tgz` / `.deb`) are unsigned; `SHA256SUMS.txt` always ships.

## macOS — Developer ID + notarization

`build` job (macOS leg) → `fastlane mac dmg`:

1. Fetches/creates and installs the **"Daccord Developer ID"** provisioning
   profile via the API key (required because `Release.entitlements` includes
   keychain access).
2. `gym` re-exports with Developer ID Application, `ENABLE_HARDENED_RUNTIME=YES`
   and `--timestamp` (hardened runtime is required for notarization).
3. Builds the universal `.dmg` and signs the disk image itself.
4. Notarizes via `notarize` with the API key (fastlane picks `notarytool`
   automatically — do **not** pass `use_notarytool`, the option was removed and
   fails the lane), then staples the ticket.
5. A blocking step verifies DMG signature, stapled ticket, Gatekeeper, and the
   mounted app's deep signature.

Secrets (see also [`app-store-deploy.md`](app-store-deploy.md)):

| Secret | Where it comes from |
|--------|--------------------|
| `DEVELOPER_ID_CERT_P12` | base64 Developer ID Application `.p12`. Must be created by the Apple Developer **account holder** (the API key can't mint it); `scripts/bootstrap-signing.sh` exports and uploads it. |
| `CERT_P12_PASSWORD` | `.p12` export password (shared with App Store certs) |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` | App Store Connect API key; used for notarization |
| `APPLE_TEAM_ID` | 10-character team ID |

Requires a paid Apple Developer Program membership.

### Verifying a released DMG

```bash
codesign --verify --strict --verbose=2 daccord-macos-universal.dmg
xcrun stapler validate daccord-macos-universal.dmg
spctl -a -t open --context context:primary-signature -v daccord-macos-universal.dmg
```

## Windows — Authenticode

Two `build`-job steps call `dist/sign-windows.ps1`:

- **Before packaging:** signs `daccord.exe` and DLLs in
  `build/windows/x64/runner/Release/` (already-validly-signed vendor DLLs are
  skipped), so the `.zip` and installer payload are signed.
- **After ISCC:** signs `daccord-windows-x86_64-setup.exe` (what SmartScreen judges).

It uses the newest SDK `signtool.exe`, `/fd sha256`, an RFC-3161 timestamp
(`/tr … /td sha256`, required or signatures die at cert expiry), with retries.

Credential modes, checked in order:

| Mode | Variable | When to use |
|------|----------|-------------|
| **store** | `WINDOWS_CERT_SHA1` — thumbprint in `Cert:\CurrentUser\My` | Non-exportable key (SimplySign cloud key, USB token). Signs with `/sha1`. |
| **pfx** | `WINDOWS_CERT_PFX_BASE64` + `WINDOWS_CERT_PASSWORD` | Exportable PKCS#12 (self-signed rehearsal or pre-June-2023 cert). Signs with `/f`. |

| Secret / variable | What it is |
|-------------------|------------|
| `SIMPLYSIGN_USER` (secret) | Certum SimplySign account ID / e-mail |
| `SIMPLYSIGN_TOTP_SECRET` (secret) | the full enrolment `otpauth://` URI — **not** a bare base32 secret (loses Certum's HMAC-SHA256 algorithm parameter) |
| `WINDOWS_CERT_PFX_BASE64` (secret) | base64 of the `.pfx` |
| `WINDOWS_CERT_PASSWORD` (secret) | `.pfx` password (optional) |
| `WINDOWS_TIMESTAMP_URL` (repo **variable**, optional) | defaults to `http://timestamp.digicert.com`; **set to `http://time.certum.pl` for Certum certs** |

`WINDOWS_CERT_SHA1` is not configured by hand; `simplysign-login.ps1` derives it
and exports it via `$GITHUB_ENV`, so cert renewal needs no secret rotation.

```bash
base64 -w0 daccord-codesign.pfx | gh secret set WINDOWS_CERT_PFX_BASE64
gh secret set WINDOWS_CERT_PASSWORD
```

Local rehearsal with a self-signed cert (works in permissive mode; tagged
releases pass `-Required` and reject it):

```powershell
$c = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=Daccord Test" `
       -CertStoreLocation Cert:\CurrentUser\My
Export-PfxCertificate -Cert $c -FilePath test.pfx `
       -Password (ConvertTo-SecureString -String "test" -Force -AsPlainText)
```

### Certificate source

Since June 2023, CAs issue code-signing keys only on hardware/cloud HSMs, so new
certificates can't use the pfx path. **We use Certum Open Source Code Signing in
the Cloud** (€49/yr, individual identity). SignPath Foundation declined us
(re-apply once the project has a track record). Azure Trusted Signing was
evaluated and not adopted (eligibility, lock-in); if ever provisioned, add
`azure/trusted-signing-action` pinned to a SHA as a gated step and test it on
`workflow_dispatch` first. Other cloud signers integrate via
`signtool sign /dlib <vendor.dll> /dmdf <metadata.json>` in `dist/sign-windows.ps1`.

### Certum SimplySign — how the cloud key is actually reached

Certum has no signing API. **SimplySign Desktop** mounts the key as a virtual
smart card into `Cert:\CurrentUser\My`, and `signtool` uses store mode.
`dist/simplysign-login.ps1`:

1. installs SimplySign Desktop via `winget`, else Certum's MSI (pinned SHA-256,
   verified Authenticode),
2. derives the TOTP from `SIMPLYSIGN_TOTP_SECRET` honoring the URI's
   `algorithm`/`digits`/`period`,
3. launches `/autologin <account> <otp>` headlessly — **both arguments are
   required**; bare `/autologin` is silently ignored (this broke the v0.2.16
   Windows job),
4. polls the cert store for the new code-signing cert,
5. exports its thumbprint as `WINDOWS_CERT_SHA1`.

No `SendKeys`/GUI automation, so it works on GitHub-hosted runners. Without
`-Required` it warns and exits; the tagged workflow passes `-Required`.

Caveats:

- The OTP appears briefly in the process command line — **do not use on a shared
  self-hosted runner**.
- Storing the TOTP secret collapses 2FA to 1FA: repo-secret access = signing ability.
- Session lifetime is undocumented; if installer signing starts failing, re-run
  the login before that step.
- The Linux alternative ([hpvb/certum-container](https://github.com/hpvb/certum-container))
  needs a human OTP over VNC per session — persistent self-hosted runners only.

**Before cutting a tag**, run the manual **Windows signing smoke test** workflow
(`windows-signing-smoke.yml`): it mounts the cloud cert, signs and timestamps a
disposable exe, and requires trusted verification, without publishing.

### Known gap

The Inno Setup uninstaller (`unins000.exe`) is unsigned; fixing needs a
`SignTool` definition plus `SignedUninstaller=yes` in `dist/installer.iss`. It
doesn't affect the download SmartScreen prompt.

## Android — stable APK and App Bundle identity

The GitHub APK and Play AAB share the upload keystore, decoded to the runner temp
dir with `ANDROID_REQUIRE_RELEASE_SIGNING=true`; `android/app/build.gradle` then
throws on any incomplete credential (no debug-key fallback in CI).

`dist/verify-android-signing.sh` verifies the APK (`apksigner`) or AAB
(`jarsigner`) and compares the cert fingerprint with
`ANDROID_SIGNING_CERT_SHA256`, blocking a valid-but-wrong key. Derive it once:

```bash
keytool -list -v -keystore upload-keystore.jks -alias upload \
  | sed -n 's/^[[:space:]]*SHA256: //p'
```

Colons and case are optional; the value must be 64 hex characters.

## Checksums & GPG (all platforms)

The `release` job hashes every artifact (after signing) into `SHA256SUMS.txt`
(`sha256sum -c` format); the in-app updater verifies against it
(`update_controller._expectedSha`). No secrets needed.

If `GPG_PRIVATE_KEY` is set, a detached armoured signature is published as
**`checksums.asc`**. **Do not rename it to anything containing `SHA256SUMS`**:
shipped updaters pick the first asset whose name contains that token, so a
`SHA256SUMS.txt.asc` could be chosen instead of the manifest and silently break
checksum verification.

### Creating the key

```bash
gpg --quick-generate-key "Daccord Releases <releases@example.org>" ed25519 sign 2y
gpg --armor --export-secret-keys releases@example.org | gh secret set GPG_PRIVATE_KEY
gh secret set GPG_PASSPHRASE     # omit if the key has no passphrase
gpg --armor --export releases@example.org > daccord-release-key.asc   # publish this
```

Use a dedicated key. Publish the public key and record its fingerprint in the README.

### Verifying a download

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing          # integrity
gpg --verify checksums.asc SHA256SUMS.txt             # authenticity
```

## Admin checklist

Settings → Secrets and variables → Actions. A partial or absent group fails that
platform's tagged leg (GPG is optional; without it checksums ship unsigned).

```
# macOS notarized DMG  (also used by the App Store jobs — see app-store-deploy.md)
DEVELOPER_ID_CERT_P12      base64 .p12, Developer ID Application
CERT_P12_PASSWORD          password for the .p12
ASC_KEY_ID                 App Store Connect API key id
ASC_ISSUER_ID              App Store Connect issuer id
ASC_KEY_P8_BASE64          base64 of AuthKey_<id>.p8
APPLE_TEAM_ID              10-char team id

# Windows Authenticode (SimplySign pair OR pfx)
SIMPLYSIGN_USER             Certum SimplySign account id (cloud-key mode)
SIMPLYSIGN_TOTP_SECRET      Certum enrolment otpauth:// URI (cloud-key mode)
WINDOWS_CERT_PFX_BASE64    base64 of the code-signing .pfx
WINDOWS_CERT_PASSWORD      password for the .pfx (optional)
WINDOWS_TIMESTAMP_URL      repo *variable*, optional; defaults to DigiCert

# Android GitHub APK + Play upload AAB
ANDROID_KEYSTORE_BASE64       base64 of the stable upload keystore
ANDROID_KEYSTORE_PASSWORD     keystore password
ANDROID_KEY_ALIAS             upload key alias
ANDROID_KEY_PASSWORD          upload key password
ANDROID_SIGNING_CERT_SHA256   pinned upload certificate fingerprint

# Release checksum signature (any platform)
GPG_PRIVATE_KEY            armoured private key block
GPG_PASSPHRASE             passphrase (optional)
```

Signing paths only run on tag pushes (secrets aren't exposed to fork PRs), so
exercise new secrets on a pre-release tag (`v0.0.0-rc.1`) first.
