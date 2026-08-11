# Release signing, notarization & checksums

How the tagged-release artifacts from `.github/workflows/release.yml` are signed,
which GitHub secrets an admin has to add to switch each piece on, and what
happens while those secrets are missing.

**Nothing here is required for a release to succeed.** Every signing step is
gated on its secrets being present and skips cleanly when they are not, so a
tag push with no signing secrets configured publishes exactly the artifacts it
always did — unsigned, but published. A missing secret can never fail a release.

## Status at a glance

| Artifact | Signing | Secrets needed | Without them |
|----------|---------|----------------|--------------|
| `daccord-macos-universal.dmg` | Developer ID + hardened runtime, notarized (`notarytool`) + stapled | `DEVELOPER_ID_CERT_P12`, `CERT_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `APPLE_TEAM_ID` | Unsigned `.dmg`; Gatekeeper says *"can't be opened because Apple cannot check it"* |
| `daccord-windows-x86_64-setup.exe`, `daccord-windows-x86_64.zip` | Authenticode (SHA-256, RFC-3161 timestamped) on `daccord.exe`, the bundled DLLs and the installer | `SIMPLYSIGN_USER` + `SIMPLYSIGN_TOTP_SECRET` (Certum cloud), **or** `WINDOWS_CERT_PFX_BASE64` + `WINDOWS_CERT_PASSWORD` (exportable `.pfx`) | Unsigned binaries; SmartScreen shows *"Windows protected your PC — unrecognized app"* |
| `daccord-linux-x86_64.tgz` / `.deb` | none needed | — | — |
| `SHA256SUMS.txt` | always generated | none | always present |
| `checksums.asc` (detached GPG signature of `SHA256SUMS.txt`) | OpenPGP | `GPG_PRIVATE_KEY`, `GPG_PASSPHRASE` | Checksums ship unsigned |

`SHA256SUMS.txt` covers **every** published artifact on every platform, and the
hashes are taken *after* signing, so they match what a user downloads. The
in-app updater already verifies downloads against it
(`update_controller._expectedSha`).

## How the gating works

`secrets` cannot be referenced from a job-level `if:`, so each job resolves the
presence test once in its `env:` block (where `secrets` *is* available) into a
plain `'true'`/`'false'` string, and the steps gate on that:

```yaml
jobs:
  build:
    env:
      WINDOWS_SIGN_AVAILABLE: ${{ secrets.WINDOWS_CERT_PFX_BASE64 != '' || (secrets.SIMPLYSIGN_USER != '' && secrets.SIMPLYSIGN_TOTP_SECRET != '') }}
    steps:
      - name: Sign binaries (Windows)
        if: matrix.platform == 'windows' && env.WINDOWS_SIGN_AVAILABLE == 'true'
        continue-on-error: true
```

Two layers of safety on top of that:

1. **Skip when absent** — the `if:` means the step never runs without its secret.
   `dist/sign-windows.ps1` re-checks and exits 0 anyway, so running it by hand is
   also harmless.
2. **Never fail when present but broken** — the signing steps are
   `continue-on-error: true` and the macOS lane has an explicit unsigned-DMG
   fallback, so an expired certificate or a down timestamp server produces a
   loud warning and an unsigned artifact rather than a lost release.

The flags live at the top of each job:

| Flag | Job | True when |
|------|-----|-----------|
| `DEVID_AVAILABLE` | `build` | `DEVELOPER_ID_CERT_P12` **and** `ASC_KEY_P8_BASE64` are set |
| `WINDOWS_SIGN_AVAILABLE` | `build` | `WINDOWS_CERT_PFX_BASE64` is set, **or** both `SIMPLYSIGN_*` secrets are |
| `SIMPLYSIGN_AVAILABLE` | `build` | `SIMPLYSIGN_USER` **and** `SIMPLYSIGN_TOTP_SECRET` are set |
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
5. A diagnostic step runs `codesign -dv`, `stapler validate` and `spctl -a -t
   open` and prints the result. It is `continue-on-error` — it reports, it never
   blocks.

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
codesign -dv --verbose=4 daccord-macos-universal.dmg
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

To rehearse the pipeline without buying anything, a self-signed cert works — it
produces a real (untrusted) signature, and the script downgrades the failing
`signtool verify /pa` to a warning:

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

1. installs SimplySign Desktop (`winget install Certum.SmartSignSimplySignDesktop`),
2. derives the current TOTP from `SIMPLYSIGN_TOTP_SECRET` (RFC 6238, the
   SHA1/6-digit/30s defaults Certum use),
3. launches the app and **types the credentials into its GUI via `SendKeys`**,
4. polls `Cert:\CurrentUser\My` until a new code-signing cert appears,
5. exports its thumbprint as `WINDOWS_CERT_SHA1`.

Step 3 is exactly as fragile as it sounds. It depends on the runner having an
interactive desktop and on Certum not rearranging the login dialog's tab order,
and it will break without warning at some point. Two things make that
acceptable rather than reckless:

- the script exits 0 on **every** failure path, so a broken login leaves
  `WINDOWS_CERT_SHA1` unset and the release ships unsigned — the same outcome as
  owning no certificate;
- the signing steps are already `continue-on-error: true`, so a tagged release
  can never be lost to it.

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
would risk failing every release at setup if that action reference ever went
away — which violates the "a release must never break" rule this whole design is
built around. When someone actually provisions Trusted Signing, add
`azure/trusted-signing-action` (pinned to a SHA) as a gated step then, and verify
it on a `workflow_dispatch` run before the next tag.

### Known gap

The uninstaller that Inno Setup generates at install time (`unins000.exe`) is
**not** signed — it is materialised on the user's machine, so it can only be
signed by giving ISCC its own `SignTool` definition plus
`SignedUninstaller=yes` in `dist/installer.iss`. That means handing the
certificate to the installer build step as well. Worth doing once real
certificates exist; it does not affect the download-time SmartScreen prompt.

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

Add under **Settings → Secrets and variables → Actions**. Any subset works;
each row switches on independently.

```
# macOS notarized DMG  (also used by the App Store jobs — see app-store-deploy.md)
DEVELOPER_ID_CERT_P12      base64 .p12, Developer ID Application
CERT_P12_PASSWORD          password for the .p12
ASC_KEY_ID                 App Store Connect API key id
ASC_ISSUER_ID              App Store Connect issuer id
ASC_KEY_P8_BASE64          base64 of AuthKey_<id>.p8
APPLE_TEAM_ID              10-char team id

# Windows Authenticode — Certum cloud key (what this project uses)
SIMPLYSIGN_USER            SimplySign account ID / e-mail
SIMPLYSIGN_TOTP_SECRET     enrolment otpauth:// URI, or its base32 secret= value

# Windows Authenticode — exportable .pfx (alternative to the two above)
WINDOWS_CERT_PFX_BASE64    base64 of the code-signing .pfx
WINDOWS_CERT_PASSWORD      password for the .pfx (optional)
WINDOWS_TIMESTAMP_URL      repo *variable*; set to http://time.certum.pl (done)

# Release checksum signature (any platform)
GPG_PRIVATE_KEY            armoured private key block
GPG_PASSPHRASE             passphrase (optional)
```

After adding secrets, exercise them on a pre-release tag (`v0.0.0-rc.1`) before
relying on them for a real release: the signing paths cannot be tested from a
pull request, because secrets are not exposed to forks and these steps only run
on a tag push.

## What is still blocked

- **Windows** — **unblocked.** The Certum *Open Source Code Signing in the Cloud*
  certificate was issued on 11 Aug 2026 to `Open Source Developer Jacob
  Cattrall` (issuer `Certum Code Signing 2021 CA`, valid until 11 Aug 2027).
  The `WINDOWS_TIMESTAMP_URL` repo variable is set to `http://time.certum.pl`.
  Signing switches on as soon as `SIMPLYSIGN_USER` and `SIMPLYSIGN_TOTP_SECRET`
  are added as repo secrets — the private key stays in Certum's HSM, so there is
  no `.pfx` to upload and `WINDOWS_CERT_SHA1` is derived at build time by
  `dist/simplysign-login.ps1`. Renewing the certificate needs no secret rotation.
- **macOS** — still blocked on an **Apple Developer Program membership**
  ($99/yr) for a Developer ID Application certificate and notarization
  credentials.
