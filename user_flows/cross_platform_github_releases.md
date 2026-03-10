# Cross-Platform GitHub Releases

Last touched: 2026-03-05
Priority: 40
Depends on: Continuous Integration

## Overview

This flow documents how daccord builds release artifacts via GitHub Actions and publishes them as GitHub Releases. When a version tag (e.g., `v0.1.8`) is pushed, a CI pipeline first runs lint + tests (reusable workflow), then validates the tag against `project.godot`, installs all required addons (GUT, Sentry SDK, godot-livekit), downloads GodotLite custom templates for reduced binary size, exports the Godot project for all enabled platforms, optionally injects a production Sentry DSN, packages each artifact (with `.desktop` file for Linux, DMG for macOS), optionally signs/notarizes (when secrets are configured), builds a Windows installer via Inno Setup, and creates a GitHub Release with changelog notes extracted from `CHANGELOG.md`. Linux x86_64, ARM64, Windows, macOS, and Android are enabled. All platforms work without LiveKit because all GDExtension type references have been replaced with dynamic lookups that are parse-safe when the extension is unavailable. The workflow removes the `.gdextension` file when the platform binary is missing, preventing crashes (including the macOS `NSException` from loading a nil dylib URL). On macOS, LiveKit dylibs are stashed before Godot import to avoid an AVFoundation crash on headless runners, then injected back into the exported `.app` bundle.

## User Steps

### Tagging a Release

1. Developer updates `CHANGELOG.md` with a new version section (e.g., `## [0.2.0]`) following Keep a Changelog format.
2. Developer updates `config/version` in `project.godot` (currently `"0.1.8"`, line 18).
3. Developer commits the changes and pushes to `master`.
4. Developer creates and pushes a git tag: `git tag v0.2.0 && git push origin v0.2.0`.
5. The `v*` tag push triggers the Release workflow (`.github/workflows/release.yml`, line 6).

### What Happens in CI

6. The CI job runs first (line 18-21) as a reusable workflow call to `.github/workflows/ci.yml`, inheriting secrets. This runs lint, unit tests, integration tests, and GodotLite export validation. Build jobs wait for CI to pass (`needs: ci`, line 25).
7. Build jobs run in the `default` GitHub environment (line 27) for each enabled platform: Linux x86_64, ARM64, and Windows on `ubuntu-latest`, macOS on `macos-latest`, and Android on `ubuntu-latest`.
8. Each build job validates that the git tag matches the version in `project.godot`. If they differ, the build fails immediately.
9. Audio libraries (`libasound2-dev`, `libpulse-dev`, `libopus-dev`, `libpipewire-0.3-dev`) are installed on Linux runners (lines 71-75).
10. Android builds set up Java JDK 17 (lines 77-82), Android SDK/NDK (lines 84-95), and decode/generate a keystore (lines 97-118).
11. GUT 9.5.0 addon is installed with caching (lines 120-133). Uses `curl` instead of `wget` for macOS compatibility.
12. Sentry SDK 1.3.2 addon is installed with caching (lines 135-151). Downloaded from `getsentry/sentry-godot` releases using `GH_PAT` secret.
13. The godot-livekit addon is downloaded from the latest NodotProject/godot-livekit release (`godot-livekit-release.zip`) and installed into `addons/godot-livekit` (lines 153-168).
14. A safety step checks whether the godot-livekit native binary exists for the current platform (lines 171-192). If missing, the `.gdextension` file is removed to prevent Godot from crashing.
15. On macOS, an additional step stashes all LiveKit dylibs to a temp directory before Godot import (lines 194-229). This prevents the Godot editor from loading the LiveKit C++ SDK, which triggers AVFoundation camera device enumeration and crashes on macOS 14+ headless runners with "Pure virtual function called!". The stashed dylibs are injected back post-export.
16. Godot 4.5 is installed via `chickensoft-games/setup-godot@v2` with export templates included (lines 231-236).
17. Godot import cache is restored/saved per platform (lines 238-244).
18. The project is imported headlessly (`godot --headless --import .`, line 247).
19. If the `SENTRY_DSN` secret is configured, the Sentry DSN in `project.godot` is replaced with the production value (lines 250-256).
20. GodotLite custom templates are downloaded from `NodotProject/GodotLite` releases for Linux x86_64, Windows, and macOS (lines 258-314). ARM64 and Android skip this step and use stock templates. macOS requires special handling: the GodotLite binary is extracted and inserted into the stock template's `.app` structure (preserving Info.plist placeholders), with an `NSCameraUseContinuityCameraDeviceType` plist key added to prevent LiveKit AVFoundation crashes.
21. Custom template paths in `export_presets.cfg` are checked — if a referenced template file doesn't exist, the path is cleared so Godot falls back to stock templates (lines 316-329).
22. Android builds configure the Godot editor settings with SDK/NDK paths (lines 331-343) and inject keystore credentials into `export_presets.cfg` (lines 345-356).
23. The build output directory is created, then the project is exported with `godot --headless --export-release "<Preset>"` (lines 358-363).
24. On macOS, stashed LiveKit dylibs are injected into the exported `.app` bundle's `Contents/Frameworks/` directory, ad-hoc signed, and the Info.plist is updated with the camera key (lines 365-409).
25. Platform-specific packaging runs (lines 411-459):
    - **Linux (x86_64 and ARM64):** `tar.gz` archive including the `.desktop` file and icon.
    - **Windows:** `zip` archive. If `WINDOWS_CERT_BASE64` secret is set, the `.exe` is signed with `osslsigncode`.
    - **Android:** `.apk` copied to artifact name.
    - **macOS:** `.zip` from Godot's export. If `APPLE_CERTIFICATE_BASE64` is set, the app bundle is code-signed. If `APPLE_ID` is set, the app is notarized and stapled.
26. A macOS DMG is created with an Applications symlink for drag-and-drop installation (lines 520-534).
27. Packaged artifacts are uploaded via `actions/upload-artifact@v4`.

### Windows Installer

28. After the build job completes, a separate `windows-installer` job runs on `blacksmith-4vcpu-windows-2025` (line 544).
29. The job downloads the `daccord-windows-x86_64` zip artifact from the build job and extracts it into `dist/build/windows/`.
30. Inno Setup is installed via `choco install innosetup` (lines 569-571).
31. The version is extracted from `project.godot` and passed to the Inno Setup compiler (`iscc`) which compiles `dist/installer.iss` into `daccord-windows-x86_64-setup.exe` (lines 573-575).
32. If `WINDOWS_CERT_BASE64` is configured, the installer is code-signed with `signtool` (native Windows signing, lines 578-588).
33. The installer artifact is uploaded separately.

### Release Creation

34. After both the build and windows-installer jobs succeed, the release job runs on `blacksmith-4vcpu-ubuntu-2404` (line 599) and downloads all artifacts.
35. The job extracts changelog notes for the tagged version from `CHANGELOG.md` using `awk`.
36. If no matching changelog section is found, the release body falls back to `"Release <tag>"`.
37. A GitHub Release is created via `softprops/action-gh-release@v2` with the tag name as the release title, changelog as the body, and all platform artifacts attached (including the Windows installer and macOS DMG).
38. If the tag contains a hyphen (e.g., `v0.2.0-beta`), the release is automatically marked as a prerelease.

### Downloading a Release (End User)

39. End user visits the GitHub Releases page.
40. User downloads the artifact matching their platform:
    - **Linux x86_64:** `daccord-linux-x86_64.tar.gz` — extract and run `daccord.x86_64`. Includes `daccord.desktop` and `daccord.png` for desktop integration.
    - **Linux ARM64:** `daccord-linux-arm64.tar.gz` — extract and run `daccord.arm64`. Includes `daccord.desktop` and `daccord.png` for desktop integration.
    - **Windows (installer):** `daccord-windows-x86_64-setup.exe` — run the installer. Installs to `Program Files`, creates Start Menu shortcuts, registers `daccord://` URL protocol, and optionally creates a desktop shortcut. Supports per-user install without admin rights.
    - **Windows (portable):** `daccord-windows-x86_64.zip` — extract and run `daccord.exe`. No installation required.
    - **macOS (DMG):** `daccord-macos.dmg` — open the disk image and drag `daccord.app` to Applications.
    - **macOS (zip):** `daccord-macos.zip` — extract and open `daccord.app`.
    - **Android:** `daccord-android-arm64.apk` — sideload the APK (requires "Install unknown apps" permission).

## Signal Flow

```
Developer pushes tag v*
  -> GitHub Actions triggers .github/workflows/release.yml

ci job (reusable workflow call, line 18):
  -> .github/workflows/ci.yml (lint, unit tests, integration tests, GodotLite validation)
  -> All CI jobs must pass before build starts

build job (matrix: linux, linux-arm64, windows, macos, android — needs: ci):
  -> actions/checkout@v4 (main repo + LFS)
  -> Validate version matches tag
       strips "v" prefix from tag, compares to project.godot config/version
       fails build on mismatch
  -> [Linux only] Install audio libraries (libasound2-dev, libpulse-dev, libopus-dev, libpipewire-0.3-dev)
  -> [Android only] Set up Java JDK 17, Android SDK/NDK, decode/generate keystore
  -> Cache + Install GUT 9.5.0 (curl for macOS compat)
  -> Cache + Install Sentry SDK 1.3.2 (gh release download from getsentry/sentry-godot, uses GH_PAT)
  -> Install godot-livekit addon (latest release)
       gh release download from NodotProject/godot-livekit
       extracts addons/godot-livekit into workspace
  -> Remove godot-livekit if platform binary missing
       checks for libgodot-livekit.linux.x86_64.so/.dll/.dylib/.android.arm64.so per platform
       removes .gdextension file if missing (prevents macOS NSException crash)
  -> [macOS only] Stash LiveKit dylibs to prevent editor crash
       moves all .dylib files to $RUNNER_TEMP/livekit_dylibs
       prevents AVFoundation device enumeration crash on headless macOS 14+ runners
  -> chickensoft-games/setup-godot@v2 (Godot 4.5 + export templates)
  -> Cache Godot import (per-platform key)
  -> godot --headless --import .
  -> [conditional] Inject Sentry DSN (sed -i.bak for macOS compat)
       if SENTRY_DSN secret is set:
         replaces config/dsn in project.godot with production DSN
  -> [linux, windows, macos only] Download GodotLite template
       gh release download from NodotProject/GodotLite
       linux:   godotlite-v4.5-linux-x86_64 -> dist/templates/godot.linuxbsd.template_release.x86_64
       windows: godotlite-v4.5-windows-x86_64.exe -> dist/templates/godot.windows.template_release.x86_64.exe
       macos:   godotlite-v4.5-macos-universal -> extract binary, merge into stock template .app, add camera plist key
  -> Clear missing custom templates (sed -i.bak for macOS compat)
       scans export_presets.cfg for custom_template/release paths
       clears any paths where the file doesn't exist (stock fallback)
  -> [Android only] Configure Godot Android SDK path, inject keystore into export preset
  -> mkdir -p dist/build/<platform>
  -> godot --headless --export-release "<Preset>"
     reads export_presets.cfg (uses GodotLite templates where available):
       preset.0 "Linux"       -> dist/build/linux/daccord.x86_64
       preset.1 "Windows"     -> dist/build/windows/daccord.exe
       preset.2 "macOS"       -> dist/build/macos/daccord.zip
       preset.3 "Linux ARM64" -> dist/build/linux-arm64/daccord.arm64
       preset.4 "Android"     -> dist/build/android/daccord.apk
  -> [macOS only] Inject stashed LiveKit dylibs into exported .app bundle
       copies dylibs to Contents/Frameworks/
       adds NSCameraUseContinuityCameraDeviceType plist key
       ad-hoc signs each dylib
  -> Platform packaging:
       linux*:  copy .desktop + icon, tar czf daccord-linux-*.tar.gz
       windows: zip -r daccord-windows-x86_64.zip
       android: cp daccord.apk daccord-android-arm64.apk
       macos:   cp daccord.zip daccord-macos.zip
  -> [conditional] Windows code signing (if WINDOWS_CERT_BASE64 secret)
       osslsigncode signs daccord.exe, re-packages zip
  -> [conditional] macOS code signing (if APPLE_CERTIFICATE_BASE64 secret)
       imports .p12 into temp keychain, codesign --deep --force --options runtime
  -> [conditional] macOS notarization (if APPLE_ID secret)
       xcrun notarytool submit + xcrun stapler staple
  -> [macOS] Create DMG with Applications symlink (hdiutil create)
  -> actions/upload-artifact@v4

windows-installer job (needs: build, runs-on: blacksmith-4vcpu-windows-2025):
  -> actions/checkout@v4
  -> actions/download-artifact@v4 (daccord-windows-x86_64)
  -> Expand-Archive into dist/build/windows/
  -> Extract APP_VERSION from project.godot
  -> choco install innosetup
  -> iscc /DMyAppVersion=<version> dist\installer.iss
       reads dist/installer.iss (Inno Setup script)
       packages dist/build/windows/* into setup exe
       outputs dist/daccord-windows-x86_64-setup.exe
  -> [conditional] Sign installer with signtool (if WINDOWS_CERT_BASE64 secret)
  -> actions/upload-artifact@v4

release job (needs: [build, windows-installer], runs-on: blacksmith-4vcpu-ubuntu-2404):
  -> actions/checkout@v4
  -> actions/download-artifact@v4 (pattern: daccord-*, merge-multiple: true)
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
| `.github/workflows/release.yml` | Release CI pipeline. Calls CI as reusable workflow, installs GUT/Sentry/audio libs/godot-livekit, validates version tag, downloads GodotLite templates, stashes/injects macOS LiveKit dylibs, builds all 5 platforms in parallel, clears missing custom templates, packages with .desktop files and DMG, optionally signs/notarizes, creates GitHub Release. |
| `.github/workflows/ci.yml` | CI pipeline (lint + unit tests + integration tests + GodotLite validation). Runs on PR to `master` and as reusable `workflow_call`. Four jobs on `blacksmith-4vcpu-ubuntu-2404` runners. |
| `export_presets.cfg` | Godot export presets for Linux x86_64 (preset.0), Windows (preset.1), macOS (preset.2), Linux ARM64 (preset.3), Android (preset.4). Defines output paths, architectures, custom templates, and platform-specific options. |
| `project.godot` | Project config. Declares version (`config/version="0.1.8"`, line 18), Sentry DSN (`sentry/config/dsn`), renderer (GL Compatibility), and autoloads. |
| `CHANGELOG.md` | Keep a Changelog format. The release job extracts notes for the tagged version from this file. Latest release: `[0.1.8] - 2026-03-02`. |
| `.gitignore` | Excludes `dist/build/` and `dist/templates/` but tracks `dist/icons/` and `dist/daccord.desktop`. |
| `dist/installer.iss` | Inno Setup script for the Windows installer. Defines app metadata, install directory, Start Menu/desktop shortcuts, `daccord://` URL protocol registry entries, and file sources. Version is injected at build time via `/DMyAppVersion`. |
| `dist/icons/daccord.ico` | Windows application icon referenced by the Windows export preset and installer. |
| `dist/icons/icon_1024x1024.png` | macOS application icon referenced by the macOS export preset (line 137). |
| `dist/icons/icon_128x128.png` | Linux icon bundled into release artifacts as `daccord.png`. |
| `dist/templates/` | GodotLite custom export templates for reduced binary size. Gitignored. Downloaded at build time from NodotProject/GodotLite releases. The workflow clears missing template paths so Godot falls back to stock templates. See [Reducing Build Size](reducing_build_size.md). |
| `dist/daccord.desktop` | Linux desktop entry file. Includes `daccord://` URL protocol handler (`MimeType=x-scheme-handler/daccord;`). Included in both Linux x86_64 and ARM64 release artifacts. |
| `scripts/autoload/error_reporting.gd` | Sentry SDK integration. Delegates to `SentrySceneTree` for SDK initialization — the DSN is injected into `project.godot` by the release workflow. |

## Implementation Details

### Release Workflow (`.github/workflows/release.yml`)

**Trigger:** Push of a tag matching `v*` (line 6). The workflow requires `contents: write` permission (line 15) to create releases. Build jobs use the `default` GitHub environment (line 27) for access to environment secrets.

**CI gate** (lines 18-21): Before any builds start, the release workflow calls `.github/workflows/ci.yml` as a reusable workflow (`uses: ./.github/workflows/ci.yml`) with `secrets: inherit`. This runs lint, unit tests, integration tests, and GodotLite export validation. The build job depends on CI passing (`needs: ci`, line 25).

**Environment variables** (lines 8-12):
- `GODOT_VERSION: "4.5.0"` — Godot engine version for setup-godot action.
- `GODOTLITE_TAG: "v4.5"` — GodotLite release tag for custom template downloads.
- `GUT_VERSION: "9.5.0"` — GUT test framework version (required as enabled plugin in project.godot).
- `SENTRY_VERSION: "1.3.2"` — Sentry SDK version (required for error reporting autoload).

**Build matrix** (lines 28-55): Five active entries for all platforms:

| Platform | Preset | Artifact | Extension | Runner | Status |
|----------|--------|----------|-----------|--------|--------|
| `linux` | `Linux` | `daccord-linux-x86_64` | `x86_64` | `ubuntu-latest` | Active |
| `linux-arm64` | `Linux ARM64` | `daccord-linux-arm64` | `arm64` | `ubuntu-latest` | Active |
| `windows` | `Windows` | `daccord-windows-x86_64` | `exe` | `ubuntu-latest` | Active |
| `macos` | `macOS` | `daccord-macos` | `zip` | `macos-latest` | Active |
| `android` | `Android` | `daccord-android-arm64` | `apk` | `ubuntu-latest` | Active |

**How builds work without LiveKit:** All GDExtension type annotations (`AccordMediaTrack`, `AccordVoiceSession`) have been replaced with base types or untyped variants. The `LiveKit` singleton is resolved dynamically via `Engine.get_singleton()` at runtime, so scripts parse successfully even when the GDExtension is absent. Voice/video features are disabled gracefully (null guards). Test files referencing LiveKit types are excluded from export via `exclude_filter="tests/*"` in `export_presets.cfg`. On macOS, Godot throws a fatal `NSInvalidArgumentException` if a GDExtension references a missing `.dylib`, so the workflow removes the `.gdextension` file entirely when the platform binary is absent.

**Audio library installation** (lines 71-75): Linux runners install `libasound2-dev`, `libpulse-dev`, `libopus-dev`, and `libpipewire-0.3-dev` needed by LiveKit. Conditional on `runner.os == 'Linux'` so it's skipped on macOS.

**Android build setup** (lines 77-118):
- **Java JDK 17** (lines 77-82): Uses `actions/setup-java@v4` with Temurin distribution.
- **Android SDK** (lines 84-95): Uses `android-actions/setup-android@v3` with cmdline-tools 11076708. Installs `platform-tools`, `build-tools;34.0.0`, `platforms;android-34`, `ndk;23.2.8568313`. Sets `ANDROID_SDK_ROOT` and `ANDROID_NDK_ROOT` environment variables.
- **Keystore** (lines 97-118): Decodes `ANDROID_KEYSTORE_BASE64` from GitHub secrets. If unavailable, generates a debug keystore as fallback with default credentials (`androiddebugkey`/`android`).

**Addon installation:**
- **GUT** (lines 120-133): Cached by version. Downloaded via `curl -sL` (not `wget`, for macOS compatibility).
- **Sentry SDK** (lines 135-151): Cached by version. Downloaded from `getsentry/sentry-godot` releases via `gh release download`. Uses `GH_PAT` secret for authentication (line 151).

Both are required because `project.godot` lists them as enabled plugins.

**godot-livekit addon download** (lines 153-168): A `gh release download` step fetches the latest `godot-livekit-release.zip` from the `NodotProject/godot-livekit` repository and replaces `addons/godot-livekit` with the extracted addon so release builds use the released addon contents.

**godot-livekit safety removal** (lines 171-192): After the download step, a per-platform check determines whether the expected native library exists. The case statement maps each platform:
- `linux`: `libgodot-livekit.linux.x86_64.so`
- `linux-arm64`: `libgodot-livekit.linux.x86_64.so` (cross-compiled, uses x86_64 binary)
- `windows`: `libgodot-livekit.windows.x86_64.dll`
- `macos`: `libgodot-livekit.macos.arm64.dylib`
- `android`: `libgodot-livekit.android.arm64.so`

If missing, the entire `.gdextension` file (and its `.uid`) is removed.

**macOS LiveKit dylib stash** (lines 194-229): The LiveKit C++ SDK triggers AVFoundation camera device enumeration on load, which crashes with "Pure virtual function called!" on macOS 14+ headless runners. Before Godot import, this step moves all `.dylib` files from `addons/godot-livekit/bin/` (both top-level and arch-specific `macos-*/` subdirectories) to `$RUNNER_TEMP/livekit_dylibs`. The stash path is exported as `LIVEKIT_DYLIB_STASH` for the post-export injection step.

**GodotLite template download** (lines 258-314): Downloads pre-built minimal export templates from `NodotProject/GodotLite` releases, tagged with `GODOTLITE_TAG` (currently `v4.5`). Skipped for `linux-arm64` and `android` (no GodotLite templates available — stock fallback). Platform handling:
- **Linux x86_64:** Direct binary download, `chmod +x`.
- **Windows:** Direct binary download, `chmod +x`.
- **macOS:** The GodotLite release asset is a zip containing `macos_template.app/`. The step extracts the universal binary from it, then copies it into the stock Godot template's `.app` structure (preserving the stock `Info.plist` with its `$binary`/`$name` placeholders). An `NSCameraUseContinuityCameraDeviceType` plist key is added to prevent LiveKit AVFoundation crashes. The result is zipped to `dist/templates/godot.macos.template_release.universal`.

**Version validation** (lines 62-69): Strips the `v` prefix from the git tag and compares it against `config/version` in `project.godot`. If they differ, the step emits a `::error::` annotation and exits with code 1.

**AccordKit:** The `accordkit` addon is developed in-tree under `addons/accordkit/` (no separate checkout needed). Previous versions checked out accordkit from a separate repo — this is no longer the case.

**Custom template fallback** (lines 316-329): Before export, a step scans `export_presets.cfg` for `custom_template/release` paths and checks if each referenced file exists. If a template is missing, the path is cleared via `sed -i.bak` so Godot falls back to stock templates.

**Godot import caching** (lines 238-244): The `.godot/imported` directory is cached per platform and content hash. The cache key includes `matrix.platform` to prevent cross-platform cache pollution. Restore keys allow partial matches on the Godot version + platform prefix.

**Godot setup** (lines 231-236): Uses `chickensoft-games/setup-godot@v2` with `include-templates: true`. This downloads the stock Godot export templates for all platforms. The `use-dotnet: false` flag skips the .NET/C# variant.

**Import step** (line 247): `godot --headless --import . || true` — the `|| true` prevents the workflow from failing if the import produces warnings. 2-minute timeout.

**Sentry DSN injection** (lines 250-256): Conditionally replaces the `config/dsn` value in `project.godot` with the production Sentry DSN from the `SENTRY_DSN` GitHub secret. Uses `sed -i.bak` + `rm -f *.bak` for macOS compatibility. Only runs if the secret is non-empty.

**Android Godot configuration** (lines 331-356): Two Android-specific steps:
- **SDK path config** (lines 331-343): Creates `$HOME/.config/godot/editor_settings-4.tres` with `export/android/android_sdk_path` and `export/android/java_sdk_path` so Godot can find the toolchain.
- **Keystore injection** (lines 345-356): Updates `export_presets.cfg` with keystore path, user, and password via `sed`. Falls back to debug keystore environment variables if release secrets are unavailable.

**Export step** (lines 361-363): `godot --headless --export-release "${{ matrix.preset }}"` runs the export. The output path comes from `export_presets.cfg`. 10-minute timeout.

**macOS LiveKit dylib injection** (lines 365-409): After export, if dylibs were stashed, this step:
1. Unzips the exported `.app` from `dist/build/macos/daccord.zip`.
2. Creates `Contents/Frameworks/` and copies all stashed dylibs (including arch-specific subdirectories).
3. Adds `NSCameraUseContinuityCameraDeviceType` to the app's `Info.plist`.
4. Ad-hoc signs each injected dylib with `codesign --force --sign -`.
5. Re-zips the `.app` bundle.

**Packaging**:
- **Linux** (lines 411-418, both x86_64 and ARM64): Copies `dist/daccord.desktop` and `dist/icons/icon_128x128.png` (as `daccord.png`) into the build directory, then creates a `tar.gz` archive.
- **Windows** (lines 420-449): Creates a `zip` archive. If the `WINDOWS_CERT_BASE64` secret is configured, a subsequent step installs `osslsigncode`, extracts the zip, signs `daccord.exe` with the PFX certificate, and re-packages.
- **Android** (lines 451-454): Copies `dist/build/android/daccord.apk` to `daccord-android-arm64.apk`.
- **macOS** (lines 456-518): Godot's macOS export produces a `.zip` containing the `.app` bundle. If `APPLE_CERTIFICATE_BASE64` is configured, the app is unzipped, code-signed with `codesign --deep --force --options runtime`, and re-zipped. If `APPLE_ID` is configured, the app is submitted for notarization via `xcrun notarytool`, then stapled with `xcrun stapler`.
- **macOS DMG** (lines 520-534): Creates a `.dmg` disk image using `hdiutil create` with UDZO compression. The image contains `daccord.app` and an `Applications` symlink for drag-and-drop installation.

**Artifact upload** (lines 535-539): Each build uploads its packaged archive. The `path` glob `${{ matrix.artifact }}.*` matches the `.tar.gz`, `.zip`, `.apk`, or `.dmg` file.

### Windows Installer Job

The `windows-installer` job runs on `blacksmith-4vcpu-windows-2025` (line 544) after the build job completes.

**Why a separate job:** Inno Setup is a Windows-only tool. The Windows build itself cross-compiles on `ubuntu-latest` via Godot's export templates. Rather than running Inno Setup through Wine (which is fragile), a dedicated Windows runner provides native, reliable installer compilation.

**Inno Setup installation** (lines 569-571): Inno Setup is installed via `choco install innosetup` since it is not pre-installed on the Blacksmith Windows runner.

**Artifact flow:** The job downloads the `daccord-windows-x86_64` artifact (the zip from the build job), extracts it into `dist/build/windows/`, then runs `iscc` against `dist/installer.iss`. The script's `[Files]` section reads from `build\windows\*` relative to the `dist/` directory.

**Version injection:** The version is extracted from `project.godot` via PowerShell `Select-String` and passed to `iscc` as `/DMyAppVersion=<version>`. The `.iss` script uses `GetEnv('APP_VERSION')` as a fallback but the `/D` flag takes precedence.

**Installer features** (`dist/installer.iss`):
- Installs to `{autopf}\Daccord` (Program Files, auto-selects 64-bit path).
- Creates Start Menu group with app shortcut and uninstaller.
- Optional desktop shortcut (unchecked by default).
- "Launch daccord" checkbox on the finish page.
- `PrivilegesRequired=lowest` — installs per-user by default, with a dialog to elevate if desired.
- `ArchitecturesAllowed=x64compatible` — 64-bit Windows only.
- LZMA2 solid compression.
- Uses `dist/icons/daccord.ico` as the setup icon and uninstall display icon.
- Registers `daccord://` URL protocol via `[Registry]` entries (lines 51-55).

**Code signing:** If `WINDOWS_CERT_BASE64` is configured, the installer exe is signed with `signtool` (native Windows signing tool, more reliable than `osslsigncode` for installers). Timestamps via DigiCert's timestamp server.

### Release Job

The release job depends on both `build` and `windows-installer` (`needs: [build, windows-installer]`, line 598). Runs on `blacksmith-4vcpu-ubuntu-2404` (line 599).

**Artifact download**: Uses `pattern: daccord-*` and `merge-multiple: true` to merge all platform artifacts (including the Windows installer, macOS DMG, and Android APK) into a single `artifacts/` directory.

**Changelog extraction**: Uses `awk` to extract the section between `## [<version>]` and the next `## [` heading. Falls back to `"Release <tag>"` if no matching section exists.

**Release creation**: Uses `softprops/action-gh-release@v2`:
- `name`: The tag ref name (e.g., `v0.2.0`).
- `body`: Extracted changelog notes.
- `draft: false`: Released immediately.
- `prerelease`: `true` if the tag contains a hyphen, supporting tags like `v0.2.0-beta`.
- `files: artifacts/*`: Attaches all downloaded artifacts.

### Export Presets (`export_presets.cfg`)

All desktop presets reference GodotLite custom templates from `dist/templates/` for reduced binary size. GodotLite templates are downloaded at build time from [NodotProject/GodotLite](https://github.com/NodotProject/GodotLite) releases. The release workflow clears missing template paths so platforms without GodotLite templates fall back to stock. See [Reducing Build Size](reducing_build_size.md) for details.

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
- Application metadata set: icon (`dist/icons/daccord.ico`), company name (`daccord-projects`), product name (`Daccord`), description, copyright.
- Code signing disabled in preset (`codesign/enable=false`) — signing handled by the workflow when secrets are available.
- D3D12 Agility SDK multiarch enabled.

**macOS** (preset.2):
- Output: `dist/build/macos/daccord.zip` — Godot exports macOS as a `.zip` containing the `.app` bundle.
- Custom template: `res://dist/templates/godot.macos.template_release.universal`.
- Architecture: `universal` — fat binary with both x86_64 and ARM64.
- Texture format: S3TC/BPTC and ETC2/ASTC both enabled — required for universal builds.
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

**Android** (preset.4):
- Output: `dist/build/android/daccord.apk`.
- No custom template (uses stock Godot export templates).
- Architecture: `arm64-v8a` only (line 222).
- Texture format: ETC2/ASTC only (line 227).
- Package name: `com.daccord_projects.daccord` (line 228).
- Permissions: internet, access_network_state, record_audio, camera (lines 246-249).
- Min/target SDK left empty (using Godot defaults, lines 220-221).
- Version name: `0.1.8` (line 251).
- Keystore paths injected by workflow at build time (lines 252-257).

### CI Workflow (`.github/workflows/ci.yml`)

The CI workflow runs on PR to `master` and as a reusable `workflow_call` (lines 4-6). It has four jobs, all on `blacksmith-4vcpu-ubuntu-2404` runners:

- **Lint job** (line 15): Installs `gdtoolkit` via pip, runs `gdlint scripts/ scenes/`. Also runs `gdradon` complexity analysis and flags functions with grades C-F.
- **Unit test job** (line 47, needs lint): Installs godot-livekit, audio libraries, GUT and Sentry SDK (with caching), sets up Godot (without templates), validates project startup, caches Godot imports, runs GUT unit tests from `tests/unit/`. Also runs LiveKit tests with `continue-on-error` (may crash without audio hardware). Outputs test summaries to GitHub Step Summary.
- **Integration test job** (line 179, needs lint): Checks out accordserver from `DaccordProject/accordserver`, installs Rust via `dtolnay/rust-toolchain@stable`, sets up `sccache` with fallback, caches Rust builds, builds accordserver, starts it with `ACCORD_TEST_MODE=true` and SQLite database, waits for `/health` readiness. Runs AccordKit unit tests and REST integration tests. Uploads server logs as artifact.
- **GodotLite validation job** (line 380, needs lint): Downloads the GodotLite Linux x86_64 template, installs all addons, exports with the GodotLite template, and validates the exported binary starts without fatal errors (checks for `MainLoop type doesn't exist`, `SCRIPT ERROR`, etc.). Catches module-stripping regressions before they reach release builds.

### Changelog Format (`CHANGELOG.md`)

Uses [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format with Semantic Versioning. The latest release is `[0.1.8] - 2026-03-02`. When cutting a new release:
1. Rename `[Unreleased]` to `[0.x.0]` with a date.
2. Add a new empty `[Unreleased]` section above it.
3. The `awk` command in the release job expects headers like `## [0.2.0]`.

### Platform Distribution Assets

The `dist/` directory contains platform-specific distribution files:
- `dist/icons/` — App icons at multiple resolutions (16x16 through 1024x1024 PNG, plus `.ico` for Windows). Tracked in git.
- `dist/templates/` — GodotLite custom export templates for reduced binary size. Gitignored. Downloaded at build time from NodotProject/GodotLite releases.
- `dist/daccord.desktop` — Linux FreeDesktop entry file. Tracked in git. Includes `daccord://` URL protocol handler. Included in both Linux x86_64 and ARM64 release artifacts.

### Version Management

The project version is set in `project.godot` at `config/version="0.1.8"` (line 18). This is the only source of truth for the version number. The release workflow validates that the git tag matches this version, failing the build on mismatch.

- There is no `APP_VERSION` constant in client code — `client.gd` and `config.gd` have no version references.
- `error_reporting.gd` delegates to `SentrySceneTree` for SDK initialization, which reads the version from ProjectSettings at runtime.

### Sentry DSN Injection

The release workflow conditionally injects a production Sentry DSN into release builds:

1. `project.godot` contains a development DSN under `[sentry]` / `config/dsn` pointing to a local GlitchTip instance.
2. During CI, if the `SENTRY_DSN` GitHub secret is configured, the "Inject Sentry DSN" step uses `sed -i.bak` to replace the DSN value in `project.godot` before export.
3. At runtime, `SentrySceneTree` reads the DSN via ProjectSettings and passes it to `SentrySDK.init()`.
4. This ensures development builds report to the local instance while release builds report to production.

### Code Signing and Notarization

Signing and notarization are conditional on GitHub secrets being configured. Without secrets, builds proceed unsigned (no-op).

**Windows code signing** (requires `WINDOWS_CERT_BASE64` and `WINDOWS_CERT_PASSWORD` secrets):
- The build job uses `osslsigncode` on the Linux runner to sign `daccord.exe` with a PFX certificate, then re-packages the zip.
- The windows-installer job uses native `signtool` on the Windows runner to sign `daccord-windows-x86_64-setup.exe`.
- Both timestamp via DigiCert's timestamp server.
- Eliminates SmartScreen/Defender warnings for end users.

**macOS code signing** (requires `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, and `APPLE_IDENTITY` secrets):
- Imports a `.p12` certificate into a temporary keychain on the `macos-latest` runner.
- Signs with `codesign --deep --force --options runtime` for hardened runtime support.
- The temporary keychain is deleted after signing.

**macOS notarization** (requires `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID` secrets):
- Submits the signed `.zip` to Apple's notary service via `xcrun notarytool`.
- Waits for notarization to complete, then staples the ticket to the app bundle.
- Eliminates Gatekeeper warnings for end users.

### macOS DMG Creation

After signing/notarization, a DMG disk image is created (lines 520-534):
1. The signed `.zip` is extracted to a temp directory.
2. An `Applications` symlink is created alongside `daccord.app`.
3. `hdiutil create` produces `daccord-macos.dmg` with UDZO compression.
4. The DMG is uploaded alongside the `.zip` as a release artifact.

This provides a familiar drag-and-drop installation experience for macOS users.

## Implementation Status

- [x] Release workflow triggered by `v*` tag push
- [x] CI gate: lint + tests run before builds via reusable workflow call
- [x] Linux x86_64, ARM64, Windows, macOS, and Android builds active
- [x] AccordKit addon developed in-tree (no separate checkout needed)
- [x] godot-livekit addon installed from latest NodotProject/godot-livekit release
- [x] GUT addon installation with caching (required as enabled plugin)
- [x] Sentry SDK installation with caching (required for error reporting autoload)
- [x] Audio library installation for Linux runners (including libpipewire-0.3-dev)
- [x] godot-livekit safety removal when platform binary missing
- [x] macOS LiveKit dylib stash before import (prevents AVFoundation crash)
- [x] macOS LiveKit dylib injection post-export into .app bundle
- [x] Godot 4.5 setup with export templates
- [x] Godot import caching (per-platform keys)
- [x] Headless project import before export
- [x] GodotLite template download for Linux x86_64, Windows, and macOS
- [x] GodotLite export validation in CI (catches module-stripping regressions)
- [x] Platform-specific artifact packaging (tar.gz, zip, apk, dmg)
- [x] Artifact upload between jobs
- [x] Changelog extraction from `CHANGELOG.md`
- [x] Automatic prerelease detection from tag hyphens
- [x] GitHub Release creation with artifacts and notes
- [x] CI pipeline (lint + unit tests + integration tests + GodotLite validation) on PR
- [x] Export presets configured for all five platforms
- [x] macOS universal binary preset (x86_64 + ARM64) with ETC2/ASTC enabled
- [x] Windows application metadata (icon, company, description)
- [x] Version tag validation against `project.godot`
- [x] Sentry DSN injection for production error reporting
- [x] macOS-compatible `sed -i.bak` and `curl` throughout workflow
- [x] GitHub environment (`default`) configured for build jobs
- [x] Windows code signing step (conditional on `WINDOWS_CERT_BASE64` secret)
- [x] macOS code signing step (conditional on `APPLE_CERTIFICATE_BASE64` secret)
- [x] macOS notarization step (conditional on `APPLE_ID` secret)
- [x] macOS DMG creation with Applications symlink
- [x] Linux `.desktop` file and icon included in release artifacts
- [x] `dist/icons/` and `dist/daccord.desktop` tracked in git
- [x] ARM64 Linux build in matrix
- [x] Windows build (LiveKit types resolved dynamically; voice/video disabled without `.dll`)
- [x] Windows installer via Inno Setup (`dist/installer.iss`, built on `blacksmith-4vcpu-windows-2025`)
- [x] Windows installer with `daccord://` URL protocol registration
- [x] Windows installer code signing step (conditional on `WINDOWS_CERT_BASE64` secret, uses native `signtool`)
- [x] macOS build with LiveKit dylib stash/inject workflow
- [x] Android build with Java/SDK/NDK setup and keystore management
- [x] Blacksmith runners for Windows installer and release jobs
- [ ] GodotLite templates for Linux ARM64 and Android (no GodotLite builds available — stock fallback used)
- [ ] Android min/target SDK versions (export_presets.cfg lines 220-221 are empty, using Godot defaults)

## Tasks

### RELEASE-1: macOS LiveKit `.dylib` availability
- **Status:** partial
- **Impact:** 2
- **Effort:** 3
- **Tags:** ci, video, voice
- **Notes:** LiveKit GDExtension has macOS dylibs in the godot-livekit release. The release workflow stashes them before import and injects them post-export. Voice/video features are available when the dylibs are present.

### RELEASE-2: Windows code signing not yet active
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** config, security
- **Notes:** Workflow steps exist for both the exe (via `osslsigncode`) and the installer (via `signtool`) but require `WINDOWS_CERT_BASE64` and `WINDOWS_CERT_PASSWORD` secrets. Users will see SmartScreen/Defender warnings until a certificate is purchased and configured.

### RELEASE-3: macOS signing/notarization not yet active
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** config
- **Notes:** Workflow steps exist but require Apple Developer account secrets (`APPLE_CERTIFICATE_BASE64`, `APPLE_ID`, etc.). Gatekeeper will block the app until secrets are configured.

### RELEASE-4: Missing ARM64 and Android GodotLite templates
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** ci
- **Notes:** GodotLite only provides Linux x86_64, Windows, and macOS templates. ARM64 Linux and Android use stock Godot templates, resulting in larger binaries. GodotLite ARM64 and Android support would need to be added upstream at NodotProject/GodotLite.

### RELEASE-5: ARM64 Linux cross-compilation
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** ci, testing
- **Notes:** ARM64 builds cross-compile from `ubuntu-latest` (x86_64). Godot handles this via export templates, but edge cases may surface. No GodotLite ARM64 template exists yet.

### RELEASE-6: Android min/target SDK versions
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** ci, mobile
- **Notes:** `export_presets.cfg` lines 220-221 leave min SDK and target SDK empty, relying on Godot defaults. Should explicitly set min SDK 24 (Android 7.0, Godot 4.5 minimum) and target SDK 34 (current Play Store requirement).
