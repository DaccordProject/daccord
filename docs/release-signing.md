# Release signing, notarization & checksums

How the tagged-release artifacts from `.github/workflows/release.yml` are signed,
which GitHub secrets an admin must configure, and how release verification
prevents an unsigned or incorrectly signed executable from being published.

Tagged macOS, Windows, and Android artifacts **fail closed**. Their matrix legs
stop when stable credentials are absent, and signing, notarization, trust, or
signer-fingerprint verification failures block the GitHub Release. Local builds
remain usable without production keys: Gradle and the Windows helper scripts
retain explicit non-strict fallbacks outside the tagged workflow.

## Reviewing release action updates

Every external action in `.github/workflows/release.yml` is pinned to a full
commit SHA; the trailing comment records the corresponding upstream release.
The local reusable `ci.yml` workflow is the only `uses:` entry that is not an
external action. Dependabot checks GitHub Actions weekly via
`.github/dependabot.yml` and opens explicit update pull requests.

Before merging one of those pull requests:

1. Read the upstream release notes and compare the old and new commits. Confirm
   that the proposed SHA belongs to the expected repository and release tag.
2. Review changes to `action.yml`, runtime dependencies, inputs, permissions,
   downloaded or executed code, and handling of any signing or publishing
   secrets used by the affected step.
3. Keep the immutable 40-character SHA in `uses:` and update its readable
   version comment; never replace it with a branch or movable version tag.
4. Run the workflow YAML/action-reference checks. Test behavior in a
   non-publishing environment when an update changes inputs or execution.

## Status at a glance

| Artifact | Signing | Secrets needed | Without them |
|----------|---------|----------------|--------------|
| `daccord-macos-universal.dmg` | Developer ID + hardened runtime, notarized (`notarytool`) + stapled | `DEVELOPER_ID_CERT_P12`, `CERT_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `APPLE_TEAM_ID` | macOS matrix leg fails |
| `daccord-windows-x86_64-setup.exe`, `daccord-windows-x86_64.zip` | Authenticode (SHA-256, RFC-3161 timestamped) on `daccord.exe`, the bundled DLLs and the installer | `SIMPLYSIGN_USER` + `SIMPLYSIGN_TOTP_SECRET` (Certum cloud), **or** `WINDOWS_CERT_PFX_BASE64` + `WINDOWS_CERT_PASSWORD` (exportable `.pfx`) | Windows matrix leg fails |
| `daccord-android.apk`, Play `.aab` | Android APK/JAR signature pinned to the stable upload-key certificate | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_SIGNING_CERT_SHA256` | Android matrix / Play job fails |
| `daccord-linux-x86_64.tgz` / `.deb` | none needed | — | — |
| `SHA256SUMS.txt` | always generated | none | always present |
| `checksums.asc` (detached GPG signature of `SHA256SUMS.txt`) | OpenPGP | `GPG_PRIVATE_KEY`, `GPG_PASSPHRASE` | Checksums ship unsigned |

`SHA256SUMS.txt` covers **every** published artifact on every platform, and the
hashes are taken *after* signing, so they match what a user downloads. The
in-app updater already verifies downloads against it
(`update_controller._expectedSha`).

## How the gating works

`secrets` cannot be referenced from a job-level `if:`, so each job resolves the
complete presence test once in its `env:` block into a plain `'true'`/`'false'`
string. A preflight step fails the executable platform leg when its flag is not
true:

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

Two layers of enforcement follow:

1. **Fail when absent** — the preflight prevents unsigned platform output.
2. **Verify what was produced** — macOS runs blocking `codesign`, `stapler`, and
   `spctl` checks; Windows strict mode requires `signtool verify /pa`; Android
   cryptographically verifies the APK/AAB and compares its certificate SHA-256
   fingerprint with the configured stable identity.

The flags live at the top of each job:

| Flag | Job | True when |
|------|-----|-----------|
| `DEVID_AVAILABLE` | `build` | all six Developer ID/notarization secrets are set |
| `WINDOWS_SIGN_AVAILABLE` | `build` | `WINDOWS_CERT_PFX_BASE64` is set, **or** both `SIMPLYSIGN_*` secrets are |
| `SIMPLYSIGN_AVAILABLE` | `build` | no PFX is set and both `SIMPLYSIGN_*` secrets are |
| `ANDROID_SIGN_AVAILABLE` | `build`, `android-play` | all four keystore values and `ANDROID_SIGNING_CERT_SHA256` are set |
| `GPG_AVAILABLE` | `release` | `GPG_PRIVATE_KEY` is set |

## macOS — Developer ID + notarization

Implemented in the `build` job (macOS leg) and the `mac dmg` lane in
`fastlane/Fastfile`. The order matters and is the order Apple documents:

1. `gym` re-exports the Flutter-built app with `CODE_SIGN_IDENTITY="Developer ID
   Application"`, `ENABLE_HARDENED_RUNTIME=YES` and `--timestamp`, so the `.app`
   and every nested framework/dylib are signed (a hardened runtime is a
   prerequisite for notarization).
2. The universal `.dmg` is built from that app, then the **disk image itself** is
   signed with the same identity.
3. The `.dmg` is submitted to Apple's notary service with **`notarytool`**
   (`use_notarytool: true` — `altool`'s notarization endpoint was retired in
   November 2023) using the App Store Connect API key, so there is no Apple ID
   password or 2FA in CI.
4. The ticket is **stapled** into the `.dmg`, which is what lets it pass
   Gatekeeper on a machine that is offline or behind a filtering proxy.
5. A blocking verification step validates the DMG signature, stapled ticket and
   Gatekeeper assessment, mounts the image, and validates the nested app's deep
   signature and Gatekeeper assessment.

### Secrets

All six are already documented in
[`app-store-deploy.md`](app-store-deploy.md); the DMG needs this subset:

| Secret | Where it comes from |
|--------|--------------------|
| `DEVELOPER_ID_CERT_P12` | base64 of a **Developer ID Application** `.p12`. Must be created by the Apple Developer **account holder** — the App Store Connect API key cannot mint one. `scripts/bootstrap-signing.sh` exports and uploads it. |
| `CERT_P12_PASSWORD` | the password the `.p12` was exported with (shared with the App Store certs). |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` | App Store Connect API key (Users and Access → Integrations). Used for notarization auth. |
| `APPLE_TEAM_ID` | 10-character Apple Developer team ID. |

Requires a paid **Apple Developer Program** membership ($99/year). There is no
way to notarize without one.

### Verifying a released DMG

```bash
codesign --verify --strict --verbose=2 daccord-macos-universal.dmg
xcrun stapler validate daccord-macos-universal.dmg
spctl -a -t open --context context:primary-signature -v daccord-macos-universal.dmg
```

## Windows — Authenticode

Implemented as two steps in the `build` job (Windows leg), both calling
`dist/sign-windows.ps1`:

- **before packaging** — signs `daccord.exe` and the DLLs in
  `build/windows/x64/runner/Release/`, so the `.zip` *and* the installer payload
  both contain signed binaries. Files that already carry a valid signature (a
  vendor-signed prebuilt DLL) are left untouched.
- **after ISCC** — signs `daccord-windows-x86_64-setup.exe`. The installer is a
  new executable that wraps the payload, so it needs its own signature; it is
  also the file SmartScreen judges when someone downloads it.

The script picks the newest `signtool.exe` from the installed Windows SDKs,
signs with `/fd sha256` and an RFC-3161 timestamp (`/tr … /td sha256`), and
retries a few times because timestamp servers are the flakiest part of signing.
Without a timestamp every signature would stop validating the day the
certificate expires.

`sign-windows.ps1` takes its credential from **either** of two modes, checked in
this order:

| Mode | Variable | When to use |
|------|----------|-------------|
| **store** | `WINDOWS_CERT_SHA1` — thumbprint of a cert in `Cert:\CurrentUser\My` | The private key is non-exportable: a cloud key mounted by `dist/simplysign-login.ps1`, or a USB token on a self-hosted runner. Signs with `/sha1`; no key material touches the disk. |
| **pfx** | `WINDOWS_CERT_PFX_BASE64` + `WINDOWS_CERT_PASSWORD` | An exportable PKCS#12. In practice this means a self-signed rehearsal cert or a pre-2023 certificate — see below. Signs with `/f`. |

| Secret / variable | What it is |
|-------------------|------------|
| `SIMPLYSIGN_USER` (secret) | Certum SimplySign account ID / e-mail |
| `SIMPLYSIGN_TOTP_SECRET` (secret) | the enrolment `otpauth://` URI, or just its base32 `secret=` value |
| `WINDOWS_CERT_PFX_BASE64` (secret) | base64 of the code-signing `.pfx`/PKCS#12 |
| `WINDOWS_CERT_PASSWORD` (secret) | password protecting that `.pfx` (omit if none) |
| `WINDOWS_TIMESTAMP_URL` (repo **variable**, optional) | RFC-3161 timestamp server; defaults to `http://timestamp.digicert.com`. **Set this to `http://time.certum.pl` when signing with a Certum certificate.** |

`WINDOWS_CERT_SHA1` is not a secret and is not configured by hand — it is derived
from the public certificate by `simplysign-login.ps1` and passed to the signing
steps through `$GITHUB_ENV`, so renewing the certificate needs no secret
rotation.

```bash
base64 -w0 daccord-codesign.pfx | gh secret set WINDOWS_CERT_PFX_BASE64
gh secret set WINDOWS_CERT_PASSWORD
```

To rehearse the helper locally without buying anything, a self-signed cert works
in its default permissive mode. Tagged releases pass `-Required`, so the same
certificate is rejected when `signtool verify /pa` cannot build a trusted chain:

```powershell
$c = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=Daccord Test" `
       -CertStoreLocation Cert:\CurrentUser\My
Export-PfxCertificate -Cert $c -FilePath test.pfx `
       -Password (ConvertTo-SecureString -String "test" -Force -AsPlainText)
```

### Where the `.pfx` actually comes from

Since **1 June 2023** the CA/Browser Forum baseline requirements have mandated
that code-signing private keys live on FIPS 140-2 Level 2 (or equivalent)
hardware. Public CAs therefore no longer hand out an exportable `.pfx` — a
standard OV certificate arrives on a USB token or inside the CA's cloud HSM.
That means the `WINDOWS_CERT_PFX_BASE64` path above works for:

- a **self-signed** cert (rehearsal only),
- a **pre-2023** certificate you already hold,
- a service that lets you export a PKCS#12 (some internal/enterprise CAs);

but a brand-new certificate bought today will almost certainly need a cloud
signing service instead. Those services all work through the same mechanism —
`signtool sign /dlib <vendor.dll> /dmdf <metadata.json>` — so switching means
editing the single `signtool` invocation in `dist/sign-windows.ps1` and adding
that vendor's credentials as secrets. Nothing else in the pipeline changes.

Options, cheapest first:

| Option | Cost | Notes |
|--------|------|-------|
| **SignPath Foundation** | free for OSS | Purpose-built for open-source projects (GPLv3 qualifies). ~~Best first thing to try for this project.~~ **Applied — declined.** Their bar is a project with an established public track record, so it is worth re-applying once Daccord has one. |
| **Certum Open Source Code Signing in the Cloud** | **€49/year** | **What we use.** OSS-specific product, far cheaper than Certum's commercial OV cert. Issued to an individual (`Open Source Developer, <name>`), needs identity-document verification. Automation is awkward — see below. |
| **Azure Trusted Signing** | ~$10/month (Basic) | Microsoft-operated, keys in Microsoft's HSM — see below. Eligibility is the blocker, not price. |
| **DigiCert KeyLocker / SSL.com eSigner / Certum (commercial OV)** | ~$200–600/year | Traditional CA + their cloud HSM. Proper CI APIs, no GUI automation, but ~10× the cost. |

### Certum SimplySign — how the cloud key is actually reached

Certum publish **no signing API and no login CLI**. The cloud key is reachable
only through **SimplySign Desktop**, which mounts it as a *virtual smart card*;
once a session is open the certificate appears in `Cert:\CurrentUser\My` and
`signtool` signs with it by thumbprint exactly as it would with a physical
token. So unlike DigiCert/SSL.com there is no `/dlib` to point at — the store
mode described above is the integration.

Opening that session unattended is the hard part, and `dist/simplysign-login.ps1`
does it the only way anyone has documented:

1. installs SimplySign Desktop with `winget` when available, otherwise from
   Certum's official 64-bit MSI with a pinned SHA-256 checksum and verified
   Authenticode signature,
2. derives the current TOTP from `SIMPLYSIGN_TOTP_SECRET` (RFC 6238, the
   SHA1/6-digit/30s defaults Certum use),
3. launches the app and **types the credentials into its GUI via `SendKeys`**,
4. polls `Cert:\CurrentUser\My` until a new code-signing cert appears,
5. exports its thumbprint as `WINDOWS_CERT_SHA1`.

Step 3 is exactly as fragile as it sounds. It depends on the runner having an
interactive desktop and on Certum not rearranging the login dialog's tab order,
and it will break without warning at some point. Two things make that
acceptable rather than reckless:

- without `-Required`, the script warns and exits for local experimentation;
- the tagged workflow passes `-Required`, so a broken login or missing mounted
  certificate fails the Windows leg before packaging.

Two caveats worth stating plainly:

- **It collapses 2FA to 1FA.** `SIMPLYSIGN_TOTP_SECRET` is the second factor;
  storing it next to the account ID means anyone with repo-secret access can
  sign as you. That is inherent to unattended signing with this product, not
  something the script introduces.
- **Session lifetime is unverified.** Certum do not document how long a
  SimplySign session stays open. The login runs once per job and both signing
  steps reuse it, which is fine if sessions outlive a build; if they turn out to
  be shorter, the installer-signing step is the one that will start failing
  first, and the fix is to re-run the login before it.

The Linux alternative ([hpvb/certum-container](https://github.com/hpvb/certum-container)
— SimplySign under Xvnc, `p11-kit` socket, `osslsigncode`) is more robust but
needs a human to enter the OTP over VNC per session, so it only suits a
persistent self-hosted runner, not GitHub-hosted ones.

Certum certificates should be timestamped against Certum's own server: set the
`WINDOWS_TIMESTAMP_URL` repo variable to `http://time.certum.pl`.

### Azure Trusted Signing — evaluation

The issue suggests it for "instant SmartScreen reputation". Assessment:

**For**
- Cheapest paid option by a wide margin (~$9.99/month Basic tier).
- No key material in GitHub secrets at all — Microsoft holds the key in an
  Azure-managed HSM and CI authenticates with an Entra identity (ideally OIDC).
  That removes the worst part of the `.pfx`-in-a-secret model.
- Certificates are short-lived (~72h) and rotated for you; timestamped
  signatures stay valid after rotation. No annual renewal scramble.
- First-party integration: an official GitHub Action and a signtool dlib.

**Against**
- **"Instant reputation" is not something anyone actually promises.** SmartScreen
  reputation attaches to a publisher identity, and Microsoft does not guarantee
  a new Trusted Signing identity starts trusted. The historical EV-certificate
  automatic pass has been eroding for years; expect reputation to build over
  downloads either way.
- **Eligibility.** The public offering targets organizations that can show ~3
  years of verifiable legal existence; individual-developer onboarding exists but
  is narrower and slower. A young project may simply not qualify yet.
- **Lock-in, and it's real.** The key is non-exportable and the account is tied
  to an Azure subscription and Entra tenant. Leaving means signing under a new
  publisher identity, which resets whatever SmartScreen reputation had accrued —
  the switching cost is the reputation, not the config.
- Adds an Azure subscription to a project whose infrastructure is otherwise just
  GitHub.

**Decision:** implement the portable `signtool` + PKCS#12 path (what is in the
repo now), because it is the conventional approach, has zero lock-in, and is the
common denominator every cloud signer degrades to. Azure Trusted Signing is
documented here as a first-class alternative rather than wired in, for one
concrete reason beyond preference: the GitHub runner resolves and downloads
every `uses:` action during job setup, *before* step `if:` conditions are
evaluated. Adding an unexercisable third-party action to the release workflow
would add a release dependency that cannot currently be exercised or reviewed
end-to-end. When someone actually provisions Trusted Signing, add
`azure/trusted-signing-action` (pinned to a SHA) as a gated step then, and verify
it on a `workflow_dispatch` run before the next tag.

### Known gap

The uninstaller that Inno Setup generates at install time (`unins000.exe`) is
**not** signed — it is materialised on the user's machine, so it can only be
signed by giving ISCC its own `SignTool` definition plus
`SignedUninstaller=yes` in `dist/installer.iss`. That means handing the
certificate to the installer build step as well. Worth doing once real
certificates exist; it does not affect the download-time SmartScreen prompt.

## Android — stable APK and App Bundle identity

The tagged GitHub APK and Play App Bundle use the same upload keystore. The
workflow decodes it only into the runner's temporary directory and sets
`ANDROID_REQUIRE_RELEASE_SIGNING=true`; `android/app/build.gradle` throws if the
path, file, alias, or passwords are incomplete. Secret-less local release runs
retain the historical debug-key fallback, but CI cannot take it.

After each build, `dist/verify-android-signing.sh` verifies the APK with
`apksigner` or the AAB with `jarsigner`, extracts its signing-certificate
fingerprint, and compares it with `ANDROID_SIGNING_CERT_SHA256`. This identity
pin prevents a valid but wrong/debug/replacement key from entering an update
chain. Derive the value once from the protected upload keystore:

```bash
keytool -list -v -keystore upload-keystore.jks -alias upload \
  | sed -n 's/^[[:space:]]*SHA256: //p'
```

Colons and letter case are optional when storing the fingerprint. The value
must otherwise be exactly 32 SHA-256 bytes (64 hexadecimal characters).

## Checksums & GPG (all platforms)

The `release` job hashes every downloaded artifact into `SHA256SUMS.txt`
(`<sha256>  <filename>`, the `sha256sum -c` format) and publishes it as a release
asset. This needs no secrets and always runs.

If `GPG_PRIVATE_KEY` is set, a detached ASCII-armoured signature of that manifest
is published as **`checksums.asc`**.

> The filename is load-bearing. It is *not* `SHA256SUMS.txt.asc`, because the
> shipped updater finds the manifest with
> `assets.firstWhere(name.toUpperCase().contains('SHA256SUMS'))` and GitHub does
> not promise an asset ordering — a signature containing that token could be
> picked instead of the manifest, and self-updates would silently stop verifying
> checksums. Already-released clients can't be fixed, so the name avoids the
> token. (Same class of constraint as the `.tgz`-not-`.tar.gz` rule for the Linux
> bundle.)

### Creating the key

Use a dedicated release-signing key, not a personal one:

```bash
gpg --quick-generate-key "Daccord Releases <releases@example.org>" ed25519 sign 2y
gpg --armor --export-secret-keys releases@example.org | gh secret set GPG_PRIVATE_KEY
gh secret set GPG_PASSPHRASE     # omit if the key has no passphrase
gpg --armor --export releases@example.org > daccord-release-key.asc   # publish this
```

Publish the **public** key somewhere users can find it (repo root, this docs
site, or a keyserver) and record its fingerprint in the README — a signature is
only worth as much as the out-of-band way to get the key.

| Secret | What it is |
|--------|------------|
| `GPG_PRIVATE_KEY` | ASCII-armoured private key block (multi-line secrets are fine) |
| `GPG_PASSPHRASE` | passphrase for that key; may be omitted for an unprotected key |

### Verifying a download

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing          # integrity
gpg --verify checksums.asc SHA256SUMS.txt             # authenticity
```

## Admin checklist

Add under **Settings → Secrets and variables → Actions**. Each executable
platform requires its complete group; a partial or absent group fails that
tagged-release leg.

```
# macOS notarized DMG  (also used by the App Store jobs — see app-store-deploy.md)
DEVELOPER_ID_CERT_P12      base64 .p12, Developer ID Application
CERT_P12_PASSWORD          password for the .p12
ASC_KEY_ID                 App Store Connect API key id
ASC_ISSUER_ID              App Store Connect issuer id
ASC_KEY_P8_BASE64          base64 of AuthKey_<id>.p8
APPLE_TEAM_ID              10-char team id

# Windows Authenticode
SIMPLYSIGN_USER             Certum SimplySign account id (cloud-key mode)
SIMPLYSIGN_TOTP_SECRET      Certum enrolment TOTP secret (cloud-key mode)
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

After adding secrets, exercise them on a pre-release tag (`v0.0.0-rc.1`) before
relying on them for a real release: the signing paths cannot be tested from a
pull request, because secrets are not exposed to forks and these steps only run
on a tag push.

## What is still blocked

The repository now blocks executable publication until the required external
identities exist. Those enrolments and secrets cannot be created here:

- **Apple Developer Program membership** ($99/yr) to obtain a Developer ID
  Application certificate and notarization credentials.
- **A Windows code-signing certificate** — SignPath Foundation (free for OSS),
  Azure Trusted Signing, or a CA's cloud-HSM product.
- **A protected Android upload key**, enrolled in Play App Signing, plus an
  active Play developer account for store publication.

Until a platform's credentials are configured, its tagged job fails and no
unsigned replacement is attached to the release. Platform-native trust and
reputation still depend on Apple, Microsoft/CA, and Google enrolment.
