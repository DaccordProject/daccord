# Cross-Platform GitHub Releases

Last touched: 2026-02-19

## Overview

This flow documents how daccord builds cross-platform release artifacts (Linux x86_64, Linux ARM64, Windows, macOS) via GitHub Actions and publishes them as GitHub Releases. When a version tag (e.g., `v0.1.0`) is pushed, a CI pipeline validates the tag against `project.godot`, exports the Godot project for all four platforms in parallel, optionally injects a production Sentry DSN, downloads AccordStream native binaries, packages each artifact (with `.desktop` file for Linux), optionally signs/notarizes (when secrets are configured), and creates a GitHub Release with changelog notes extracted from `CHANGELOG.md`.

## User Steps

### Tagging a Release

1. Developer updates `CHANGELOG.md` with a new version section (e.g., `## [0.2.0]`) following Keep a Changelog format.
2. Developer updates `config/version` in `project.godot` (currently `"0.1.0"`, line 18).
3. Developer commits the changes and pushes to `master`.
4. Developer creates and pushes a git tag: `git tag v0.2.0 && git push origin v0.2.0`.
5. The `v*` tag push triggers the Release workflow (`.github/workflows/release.yml`, line 6).

### What Happens in CI

6. Four parallel build jobs start — one per platform (Linux x86_64, Linux ARM64, Windows, macOS). Linux and Windows jobs run on `ubuntu-latest`; macOS runs on `macos-latest`.
7. Each build job validates that the git tag matches the version in `project.godot`. If they differ, the build fails immediately.
8. Each build job checks out the main repo with LFS, then checks out `accordkit` and `accordstream` addons (with LFS for accordstream) into `.accordkit_repo/` and `.accordstream_repo/` respectively, and symlinks them into `addons/`.
9. AccordStream platform binaries are downloaded from the latest `accordstream` GitHub release and merged into the addon directory. This step uses `continue-on-error` so builds succeed even if no release exists yet.
10. Godot 4.6 is installed via `chickensoft-games/setup-godot@v2` with export templates included.
11. The project is imported headlessly (`godot --headless --import .`).
12. If the `SENTRY_DSN` secret is configured, the Sentry DSN in `project.godot` is replaced with the production value.
13. Custom template paths in `export_presets.cfg` are checked — if a referenced template file doesn't exist, the path is cleared so Godot falls back to stock templates.
14. The build output directory is created, then the project is exported with `godot --headless --export-release "<Preset>"`.
15. Platform-specific packaging runs:
    - **Linux (x86_64 and ARM64):** `tar.gz` archive including the `.desktop` file and icon.
    - **Windows:** `zip` archive. If `WINDOWS_CERT_BASE64` secret is set, the `.exe` is signed with `osslsigncode`.
    - **macOS:** `.zip` from Godot's export. If `APPLE_CERTIFICATE_BASE64` is set, the app bundle is code-signed. If `APPLE_ID` is set, the app is notarized and stapled.
16. Packaged artifacts are uploaded via `actions/upload-artifact@v4`.

### Release Creation

17. After all four builds succeed, the release job downloads all artifacts.
18. The job extracts changelog notes for the tagged version from `CHANGELOG.md` using `awk`.
19. If no matching changelog section is found, the release body falls back to `"Release <tag>"`.
20. A GitHub Release is created via `softprops/action-gh-release@v2` with the tag name as the release title, changelog as the body, and all four platform artifacts attached.
21. If the tag contains a hyphen (e.g., `v0.2.0-beta`), the release is automatically marked as a prerelease.

### Downloading a Release (End User)

22. End user visits the GitHub Releases page.
23. User downloads the artifact matching their platform:
    - **Linux x86_64:** `daccord-linux-x86_64.tar.gz` — extract and run `daccord.x86_64`. Includes `daccord.desktop` and `daccord.png` for desktop integration.
    - **Linux ARM64:** `daccord-linux-arm64.tar.gz` — extract and run `daccord.arm64`. Includes `daccord.desktop` and `daccord.png` for desktop integration.
    - **Windows:** `daccord-windows-x86_64.zip` — extract and run `daccord.exe`.
    - **macOS:** `daccord-macos.zip` — extract and open `daccord.app`.

## Signal Flow

```
Developer pushes tag v*
  -> GitHub Actions triggers .github/workflows/release.yml

build job (matrix: linux, linux-arm64, windows, macos) — runs in parallel:
  -> actions/checkout@v4 (main repo + LFS)
  -> Validate version matches tag
       strips "v" prefix from tag, compares to project.godot config/version
       fails build on mismatch
  -> actions/checkout@v4 (accordkit -> .accordkit_repo/)
  -> actions/checkout@v4 (accordstream -> .accordstream_repo/, with LFS)
  -> ln -sf symlinks into addons/
  -> Download AccordStream platform binaries (continue-on-error)
       gh release download from daccord-projects/accordstream
       extracts missing .dll/.dylib/.so into addons/accordstream/bin/
  -> chickensoft-games/setup-godot@v2 (Godot 4.6 + export templates)
  -> godot --headless --import .
  -> [conditional] Inject Sentry DSN
       if SENTRY_DSN secret is set:
         sed replaces config/dsn in project.godot with production DSN
  -> Clear missing custom templates
       scans export_presets.cfg for custom_template/release paths
       clears any paths where the file doesn't exist (stock fallback)
  -> mkdir -p dist/build/<platform>
  -> godot --headless --export-release "<Preset>"
     reads export_presets.cfg (uses custom templates from dist/templates/ if present):
       preset.0 "Linux"       -> dist/build/linux/daccord.x86_64
       preset.1 "Windows"     -> dist/build/windows/daccord.exe
       preset.2 "macOS"       -> dist/build/macos/daccord.zip
       preset.3 "Linux ARM64" -> dist/build/linux-arm64/daccord.arm64
  -> Platform packaging:
       linux*:  copy .desktop + icon, tar czf daccord-linux-*.tar.gz
       windows: zip -r daccord-windows-x86_64.zip
       macos:   cp daccord.zip daccord-macos.zip
  -> [conditional] Windows code signing (if WINDOWS_CERT_BASE64 secret)
       osslsigncode signs daccord.exe, re-packages zip
  -> [conditional] macOS code signing (if APPLE_CERTIFICATE_BASE64 secret)
       imports .p12 into temp keychain, codesign --deep --force --options runtime
  -> [conditional] macOS notarization (if APPLE_ID secret)
       xcrun notarytool submit + xcrun stapler staple
  -> actions/upload-artifact@v4

release job (needs: build):
  -> actions/checkout@v4
  -> actions/download-artifact@v4 (merge-multiple: true)
  -> Extract changelog section for version via awk
  -> softprops/action-gh-release@v2
       name: tag name (e.g., "v0.2.0")
       body: changelog notes
       prerelease: true if tag contains "-"
       files: artifacts/*
```

## Key Files

| File | Role |
|------|------|
| `.github/workflows/release.yml` | Release CI pipeline. Validates version tag, downloads AccordStream binaries, builds all four platforms in parallel (macOS on native runner), clears missing custom templates, packages with .desktop files, optionally signs/notarizes, creates GitHub Release. |
| `.github/workflows/ci.yml` | CI pipeline (lint + unit tests + integration tests). Runs on push/PR to `master`. Integration test job builds and starts accordserver, runs AccordKit test suite. |
| `export_presets.cfg` | Godot export presets for Linux x86_64 (preset.0), Windows (preset.1), macOS (preset.2), Linux ARM64 (preset.3). Defines output paths, architectures, custom templates, and platform-specific options. |
| `project.godot` | Project config. Declares version (`config/version="0.1.0"`, line 18), Sentry DSN (`sentry/config/dsn`, line 62), renderer (GL Compatibility, line 57), and autoloads. |
| `CHANGELOG.md` | Keep a Changelog format. The release job extracts notes for the tagged version from this file. |
| `dist/icons/daccord.ico` | Windows application icon referenced by the Windows export preset. |
| `dist/icons/icon_512x512.png` | macOS application icon referenced by the macOS export preset. |
| `dist/icons/icon_128x128.png` | Linux icon bundled into release artifacts as `daccord.png`. |
| `dist/templates/` | Custom export templates for reduced binary size. The workflow clears missing template paths at build time so Godot falls back to stock templates. See [Reducing Build Size](reducing_build_size.md). |
| `dist/daccord.desktop` | Linux desktop entry file. Included in both Linux x86_64 and ARM64 release artifacts. |
| `scripts/autoload/error_reporting.gd` | Sentry SDK integration. Reads `sentry/config/dsn` from ProjectSettings — the value injected by the release workflow. |

## Implementation Details

### Release Workflow (`.github/workflows/release.yml`)

**Trigger:** Push of a tag matching `v*` (line 6). The workflow requires `contents: write` permission (line 12) to create releases.

**Environment:** `GODOT_VERSION: "4.6"` (line 9) — used by the `setup-godot` action.

**Build matrix**: Four entries defining platform, preset name, artifact name, file extension, and runner OS:

| Platform | Preset | Artifact | Extension | Runner |
|----------|--------|----------|-----------|--------|
| `linux` | `Linux` | `daccord-linux-x86_64` | `x86_64` | `ubuntu-latest` |
| `linux-arm64` | `Linux ARM64` | `daccord-linux-arm64` | `arm64` | `ubuntu-latest` |
| `windows` | `Windows` | `daccord-windows-x86_64` | `exe` | `ubuntu-latest` |
| `macos` | `macOS` | `daccord-macos` | `zip` | `macos-latest` |

The macOS build runs on `macos-latest` to enable native code signing and notarization. Linux and Windows builds cross-compile from `ubuntu-latest`.

**Version validation**: Strips the `v` prefix from the git tag and compares it against `config/version` in `project.godot`. If they differ, the step emits a `::error::` annotation and exits with code 1, failing the build before any export work begins.

**Addon checkout**: The `accordkit` and `accordstream` addons live in separate repositories. They are checked out into `.accordkit_repo/` and `.accordstream_repo/` within the workspace. The accordstream checkout uses `lfs: true` to pull native binary files. Both are symlinked into `addons/`.

**AccordStream binary download**: After symlinking, a `continue-on-error` step uses `gh release download` to fetch the latest `accordstream-addon.zip` from the `daccord-projects/accordstream` repository. Missing native binaries (`.dll`, `.dylib`, `.so`) are extracted into `addons/accordstream/bin/`. This ensures release builds include voice/audio support. The step is a no-op if no accordstream release exists yet.

**Custom template fallback**: Before export, a step scans `export_presets.cfg` for `custom_template/release` paths and checks if each referenced file exists. If a template is missing (e.g., the Windows or macOS custom templates haven't been built yet), the path is cleared via `sed` so Godot falls back to stock export templates. This prevents export failures from missing template files.

**Godot setup**: Uses `chickensoft-games/setup-godot@v2` with `include-templates: true`. This downloads the stock Godot export templates for all platforms. The `use-dotnet: false` flag skips the .NET/C# variant.

**Import step**: `godot --headless --import . || true` — the `|| true` prevents the workflow from failing if the import produces warnings. 2-minute timeout.

**Sentry DSN injection**: Conditionally replaces the `config/dsn` value in `project.godot` with the production Sentry DSN from the `SENTRY_DSN` GitHub secret. Only runs if the secret is non-empty.

**Export step**: `godot --headless --export-release "${{ matrix.preset }}"` runs the export. The output path comes from `export_presets.cfg`. 10-minute timeout.

**Packaging**:
- **Linux** (both x86_64 and ARM64): Copies `dist/daccord.desktop` and `dist/icons/icon_128x128.png` (as `daccord.png`) into the build directory, then creates a `tar.gz` archive.
- **Windows**: Creates a `zip` archive. If the `WINDOWS_CERT_BASE64` secret is configured, a subsequent step installs `osslsigncode`, extracts the zip, signs `daccord.exe` with the PFX certificate, and re-packages.
- **macOS**: Godot's macOS export produces a `.zip` containing the `.app` bundle. If `APPLE_CERTIFICATE_BASE64` is configured, the app is unzipped, code-signed with `codesign --deep --force --options runtime`, and re-zipped. If `APPLE_ID` is configured, the app is submitted for notarization via `xcrun notarytool`, then stapled with `xcrun stapler`.

**Artifact upload**: Each build uploads its packaged archive. The `path` glob `${{ matrix.artifact }}.*` matches the `.tar.gz` or `.zip` file.

### Release Job

**Artifact download**: `merge-multiple: true` merges all four platform artifacts into a single `artifacts/` directory.

**Changelog extraction**: Uses `awk` to extract the section between `## [<version>]` and the next `## [` heading. Falls back to `"Release <tag>"` if no matching section exists.

**Release creation**: Uses `softprops/action-gh-release@v2`:
- `name`: The tag ref name (e.g., `v0.2.0`).
- `body`: Extracted changelog notes.
- `draft: false`: Released immediately.
- `prerelease`: `true` if the tag contains a hyphen, supporting tags like `v0.2.0-beta`.
- `files: artifacts/*`: Attaches all downloaded artifacts.

### Export Presets (`export_presets.cfg`)

All presets reference custom export templates from `dist/templates/` for reduced binary size. The release workflow clears missing template paths at build time so Godot falls back to stock templates. See [Reducing Build Size](reducing_build_size.md) for the template build process.

**Linux x86_64** (preset.0):
- Output: `dist/build/linux/daccord.x86_64`.
- Custom template: `res://dist/templates/godot.linuxbsd.template_release.x86_64`.
- Architecture: `x86_64`.
- PCK embedding disabled — the `.pck` file ships alongside the binary.
- Texture format: S3TC/BPTC only, ETC2/ASTC disabled — desktop-only textures.

**Windows** (preset.1):
- Output: `dist/build/windows/daccord.exe`.
- Custom template: `res://dist/templates/godot.windows.template_release.x86_64.exe`.
- Architecture: `x86_64`.
- Application metadata set: icon (`dist/icons/daccord.ico`), company name (`daccord-projects`), product name (`daccord`), description, copyright.
- Code signing disabled in preset (`codesign/enable=false`) — signing handled by the workflow when secrets are available.
- D3D12 Agility SDK multiarch enabled.

**macOS** (preset.2):
- Output: `dist/build/macos/daccord.zip` — Godot exports macOS as a `.zip` containing the `.app` bundle.
- Custom template: `res://dist/templates/godot.macos.template_release.universal`.
- Architecture: `universal` — fat binary with both x86_64 and ARM64.
- Code signing: ad-hoc in preset (`codesign/codesign=1`) — proper signing handled by the workflow when secrets are available.
- Notarization disabled in preset (`notarization/notarization=0`) — handled by the workflow when secrets are available.
- Bundle identifier: `com.daccord-projects.daccord`.
- Category: `public.app-category.social-networking`.
- Minimum macOS version: `10.15`.
- High-DPI enabled.
- OpenXR disabled.

**Linux ARM64** (preset.3):
- Output: `dist/build/linux-arm64/daccord.arm64`.
- Custom template: `res://dist/templates/godot.linuxbsd.template_release.arm64`.
- Architecture: `arm64`.
- PCK embedding disabled.
- Texture format: ETC2/ASTC only, S3TC/BPTC disabled — ARM-appropriate textures.

### CI Workflow (`.github/workflows/ci.yml`)

The CI workflow runs on push/PR to `master` with three jobs:

- **Lint job**: Installs `gdtoolkit` via pip, runs `gdlint scripts/ scenes/`.
- **Unit test job**: Checks out addons, sets up Godot (without templates), runs GUT unit tests from `tests/unit/`.
- **Integration test job** (`continue-on-error: true`): Checks out all repos including `accordserver`, installs Rust via `dtolnay/rust-toolchain@stable`, builds accordserver, starts it in the background with `ACCORD_TEST_MODE=true` and a SQLite database, waits for readiness (polling `/health` for 30 seconds), sets up Godot, imports the project, and runs the `tests/accordkit` test suite. Server logs are uploaded as an artifact on failure. The job uses `continue-on-error` because the `/test/seed` endpoint has a known bug causing 500 errors after the first test file (see [Test Coverage](test_coverage.md)).

### Changelog Format (`CHANGELOG.md`)

Uses [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format with Semantic Versioning. When cutting a release, the developer should:
1. Rename `[Unreleased]` to `[0.x.0]` with a date.
2. Add a new empty `[Unreleased]` section above it.
3. The `awk` command in the release job expects headers like `## [0.2.0]`.

### Platform Distribution Assets

The `dist/` directory contains platform-specific distribution files:
- `dist/icons/` — App icons at multiple resolutions (16x16 through 512x512 PNG, plus `.ico` for Windows).
- `dist/templates/` — Custom export templates for reduced binary size. Missing templates are automatically cleared at build time for stock fallback.
- `dist/daccord.desktop` — Linux FreeDesktop entry file. Included in both Linux x86_64 and ARM64 release artifacts.

### Version Management

The project version is set in `project.godot` at `config/version="0.1.0"` (line 18). This is the only source of truth for the version number. The release workflow validates that the git tag matches this version, failing the build on mismatch.

- There is no `APP_VERSION` constant in client code — `client.gd` and `config.gd` have no version references.
- `error_reporting.gd` reads the version from ProjectSettings at runtime and sets it as a Sentry tag.

### Sentry DSN Injection

The release workflow conditionally injects a production Sentry DSN into release builds:

1. `project.godot` contains a development DSN under `[sentry]` / `config/dsn` pointing to a local GlitchTip instance.
2. During CI, if the `SENTRY_DSN` GitHub secret is configured, the "Inject Sentry DSN" step uses `sed` to replace the DSN value in `project.godot` before export.
3. At runtime, `error_reporting.gd` reads the DSN via `ProjectSettings.get_setting("sentry/config/dsn", "")` and passes it to `SentrySDK.init()`.
4. This ensures development builds report to the local instance while release builds report to production.

### Code Signing and Notarization

Signing and notarization are conditional on GitHub secrets being configured. Without secrets, builds proceed unsigned (no-op).

**Windows code signing** (requires `WINDOWS_CERT_BASE64` and `WINDOWS_CERT_PASSWORD` secrets):
- Uses `osslsigncode` on the Linux runner to sign `daccord.exe` with a PFX certificate.
- Timestamps via DigiCert's timestamp server.
- Eliminates SmartScreen/Defender warnings for end users.

**macOS code signing** (requires `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, and `APPLE_IDENTITY` secrets):
- Imports a `.p12` certificate into a temporary keychain on the `macos-latest` runner.
- Signs with `codesign --deep --force --options runtime` for hardened runtime support.
- The temporary keychain is deleted after signing.

**macOS notarization** (requires `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID` secrets):
- Submits the signed `.zip` to Apple's notary service via `xcrun notarytool`.
- Waits for notarization to complete, then staples the ticket to the app bundle.
- Eliminates Gatekeeper warnings for end users.

## Implementation Status

- [x] Release workflow triggered by `v*` tag push
- [x] Parallel cross-platform build matrix (Linux x86_64, Linux ARM64, Windows, macOS)
- [x] Addon checkout and symlinking for accordkit and accordstream
- [x] Godot 4.6 setup with export templates
- [x] Headless project import before export
- [x] Platform-specific artifact packaging (tar.gz, zip)
- [x] Artifact upload between jobs
- [x] Changelog extraction from `CHANGELOG.md`
- [x] Automatic prerelease detection from tag hyphens
- [x] GitHub Release creation with artifacts and notes
- [x] CI pipeline (lint + unit tests) on push/PR
- [x] Export presets configured for all four platforms
- [x] macOS universal binary (x86_64 + ARM64)
- [x] Windows application metadata (icon, company, description)
- [x] Linux x86_64 and ARM64 export presets
- [x] Version tag validation against `project.godot`
- [x] Sentry DSN injection for production error reporting
- [x] Custom export template configured for Linux (missing templates auto-cleared for stock fallback)
- [x] Windows code signing (conditional on `WINDOWS_CERT_BASE64` secret)
- [x] macOS code signing (conditional on `APPLE_CERTIFICATE_BASE64` secret)
- [x] macOS notarization (conditional on `APPLE_ID` secret)
- [x] Linux `.desktop` file and icon included in release artifacts
- [x] AccordStream native binaries downloaded from releases (continue-on-error)
- [x] ARM64 Linux build in matrix
- [x] Integration tests in CI (continue-on-error until seed bug is fixed)
- [x] macOS build runs on native `macos-latest` runner
- [ ] Custom export templates for Windows and macOS (referenced in presets but not yet built — stock fallback used)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Windows code signing not yet active | Medium | Workflow step exists but requires `WINDOWS_CERT_BASE64` and `WINDOWS_CERT_PASSWORD` secrets. Users will see SmartScreen/Defender warnings until a certificate is purchased and configured. |
| macOS signing/notarization not yet active | Medium | Workflow steps exist but require Apple Developer account secrets (`APPLE_CERTIFICATE_BASE64`, `APPLE_ID`, etc.). Gatekeeper will block the app until secrets are configured. |
| Missing Windows and macOS custom templates | Medium | `export_presets.cfg` references custom templates that don't exist yet. The workflow auto-clears missing paths so Godot falls back to stock templates, inflating those binaries. See [Reducing Build Size](reducing_build_size.md). |
| Changelog only has `[Unreleased]` | Medium | `CHANGELOG.md` has no versioned sections yet. The first `v*` tag push will produce a release with the fallback body `"Release v0.1.0"` instead of real notes. |
| Integration tests are continue-on-error | Low | The `/test/seed` endpoint returns 500 after the first test file runs, causing cascading failures. Integration test job won't block PRs until the seed bug is fixed server-side. |
| ARM64 Linux cross-compilation | Low | ARM64 builds cross-compile from `ubuntu-latest` (x86_64). Godot handles this via export templates, but edge cases may surface. No ARM64 custom template exists yet. |
