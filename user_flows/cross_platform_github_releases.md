# Cross-Platform GitHub Releases

*Last touched: 2026-02-18 21:30*

## Overview

This flow documents how daccord builds cross-platform release artifacts (Linux, Windows, macOS) via GitHub Actions and publishes them as GitHub Releases. When a version tag (e.g., `v0.1.0`) is pushed, a CI pipeline exports the Godot project for all three platforms in parallel, packages each artifact, and creates a GitHub Release with changelog notes extracted from `CHANGELOG.md`.

## User Steps

### Tagging a Release

1. Developer updates `CHANGELOG.md` with a new version section (e.g., `## [0.2.0]`) following Keep a Changelog format.
2. Developer updates `config/version` in `project.godot` (currently `"0.1.0"`, line 18).
3. Developer commits the changes and pushes to `master`.
4. Developer creates and pushes a git tag: `git tag v0.2.0 && git push origin v0.2.0`.
5. The `v*` tag push triggers the Release workflow (`.github/workflows/release.yml`, line 6).

### What Happens in CI

6. Three parallel build jobs start — one per platform (Linux, Windows, macOS).
7. Each build job checks out the main repo with LFS, then checks out `accordkit` and `accordstream` addons into `.accordkit_repo/` and `.accordstream_repo/` respectively, and symlinks them into `addons/`.
8. Godot 4.6 is installed via `chickensoft-games/setup-godot@v2` with export templates included.
9. The project is imported headlessly (`godot --headless --import .`), then exported with `godot --headless --export-release "<Preset>"`.
10. Platform-specific packaging runs: `tar.gz` for Linux, `zip` for Windows, and the macOS export's built-in `.zip` is copied directly.
11. Packaged artifacts are uploaded via `actions/upload-artifact@v4`.

### Release Creation

12. After all three builds succeed, the release job downloads all artifacts.
13. The job extracts changelog notes for the tagged version from `CHANGELOG.md` using `awk`.
14. If no matching changelog section is found, the release body falls back to `"Release <tag>"`.
15. A GitHub Release is created via `softprops/action-gh-release@v2` with the tag name as the release title, changelog as the body, and all three platform artifacts attached.
16. If the tag contains a hyphen (e.g., `v0.2.0-beta`), the release is automatically marked as a prerelease (line 130).

### Downloading a Release (End User)

17. End user visits the GitHub Releases page.
18. User downloads the artifact matching their platform:
    - **Linux:** `daccord-linux-x86_64.tar.gz` — extract and run `daccord.x86_64`.
    - **Windows:** `daccord-windows-x86_64.zip` — extract and run `daccord.exe`.
    - **macOS:** `daccord-macos.zip` — extract and open `daccord.app`.

## Signal Flow

```
Developer pushes tag v*
  -> GitHub Actions triggers .github/workflows/release.yml

build job (matrix: linux, windows, macos) — runs in parallel:
  -> actions/checkout@v4 (main repo + LFS)
  -> actions/checkout@v4 (accordkit -> .accordkit_repo/)
  -> actions/checkout@v4 (accordstream -> .accordstream_repo/)
  -> ln -sf symlinks into addons/
  -> chickensoft-games/setup-godot@v2 (Godot 4.6 + export templates)
  -> godot --headless --import .
  -> godot --headless --export-release "<Preset>"
     reads export_presets.cfg:
       preset.0 "Linux"   -> dist/build/linux/daccord.x86_64
       preset.1 "Windows" -> dist/build/windows/daccord.exe
       preset.2 "macOS"   -> dist/build/macos/daccord.zip
  -> Platform packaging:
       linux:   tar czf daccord-linux-x86_64.tar.gz
       windows: zip -r daccord-windows-x86_64.zip
       macos:   cp daccord.zip daccord-macos.zip
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
| `.github/workflows/release.yml` | Release CI pipeline. Builds all three platforms in parallel, packages artifacts, creates GitHub Release. |
| `.github/workflows/ci.yml` | CI pipeline (lint + unit tests). Runs on push/PR to `master`. Does not produce release artifacts but shares the same addon checkout and Godot setup pattern. |
| `export_presets.cfg` | Godot export presets for Linux (preset.0), Windows (preset.1), macOS (preset.2). Defines output paths, architectures, and platform-specific options. |
| `project.godot` | Project config. Declares version (`config/version="0.1.0"`, line 18), renderer (GL Compatibility, line 51), and autoloads. |
| `CHANGELOG.md` | Keep a Changelog format. The release job extracts notes for the tagged version from this file. |
| `dist/icons/daccord.ico` | Windows application icon referenced by the Windows export preset (line 71 of `export_presets.cfg`). |
| `dist/icons/icon_512x512.png` | macOS application icon referenced by the macOS export preset (line 137 of `export_presets.cfg`). |
| `dist/daccord.desktop` | Linux desktop entry file. Not currently included in the Linux export artifact. |

## Implementation Details

### Release Workflow (`.github/workflows/release.yml`)

**Trigger:** Push of a tag matching `v*` (line 6). The workflow requires `contents: write` permission (line 12) to create releases.

**Environment:** `GODOT_VERSION: "4.6"` (line 9) — used by the `setup-godot` action.

**Build matrix** (lines 19-32): Three entries defining platform, preset name, artifact name, and file extension:

| Platform | Preset | Artifact | Extension |
|----------|--------|----------|-----------|
| `linux` | `Linux` | `daccord-linux-x86_64` | `x86_64` |
| `windows` | `Windows` | `daccord-windows-x86_64` | `exe` |
| `macos` | `macOS` | `daccord-macos` | `zip` |

All three jobs run on `ubuntu-latest` (line 16). Windows and macOS builds are cross-compiled from Linux using Godot's export templates.

**Addon checkout** (lines 39-54): The `accordkit` and `accordstream` addons live in separate repositories (`daccord-projects/accordkit`, `daccord-projects/accordstream`). They are checked out into `.accordkit_repo/` and `.accordstream_repo/` within the workspace, then symlinked into `addons/` so Godot can find them. The symlinks use `$GITHUB_WORKSPACE` as the base path (lines 53-54).

**Godot setup** (lines 56-61): Uses `chickensoft-games/setup-godot@v2` with `include-templates: true`. This downloads the stock Godot export templates for all platforms. The `use-dotnet: false` flag skips the .NET/C# variant.

**Import step** (line 64): `godot --headless --import . || true` — the `|| true` prevents the workflow from failing if the import produces warnings (common with headless Godot imports). 2-minute timeout.

**Export step** (line 71): `godot --headless --export-release "${{ matrix.preset }}"` runs the export. The output path comes from `export_presets.cfg` (e.g., `dist/build/linux/daccord.x86_64`). 10-minute timeout.

**Packaging** (lines 74-89):
- **Linux** (lines 74-78): `tar czf` from inside `dist/build/linux/`, producing `daccord-linux-x86_64.tar.gz` in the workspace root.
- **Windows** (lines 80-84): `zip -r` from inside `dist/build/windows/`, producing `daccord-windows-x86_64.zip`.
- **macOS** (lines 86-89): Godot's macOS export already produces a `.zip` (containing the `.app` bundle). This is simply copied to `daccord-macos.zip`.

**Artifact upload** (lines 91-95): Each build uploads its packaged archive. The `path` glob `${{ matrix.artifact }}.*` matches the `.tar.gz` or `.zip` file.

### Release Job (lines 97-131)

**Artifact download** (lines 104-108): `merge-multiple: true` merges all three platform artifacts into a single `artifacts/` directory.

**Changelog extraction** (lines 110-122): Uses `awk` to extract the section between `## [<version>]` and the next `## [` heading. The version is derived from the tag by stripping the `v` prefix. Falls back to `"Release <tag>"` if no matching section exists.

**Release creation** (lines 124-131): Uses `softprops/action-gh-release@v2`:
- `name`: The tag ref name (e.g., `v0.2.0`).
- `body`: Extracted changelog notes.
- `draft: false`: Released immediately.
- `prerelease`: `true` if the tag contains a hyphen (line 130), supporting tags like `v0.2.0-beta`.
- `files: artifacts/*`: Attaches all downloaded artifacts.

### Export Presets (`export_presets.cfg`)

**Linux** (preset.0, lines 1-37):
- Output: `dist/build/linux/daccord.x86_64` (line 11).
- Architecture: `x86_64` (line 25).
- PCK embedding disabled (`embed_pck=false`, line 22) — the `.pck` file ships alongside the binary.
- Texture format: S3TC/BPTC only (line 23), ETC2/ASTC disabled (line 24) — desktop-only textures.

**Windows** (preset.1, lines 39-100):
- Output: `dist/build/windows/daccord.exe` (line 49).
- Architecture: `x86_64` (line 63).
- Application metadata set: icon (`dist/icons/daccord.ico`, line 71), company name (`daccord-projects`, line 76), product name (`daccord`, line 77), description (line 78), copyright (line 79).
- Code signing disabled (`codesign/enable=false`, line 64).
- D3D12 Agility SDK multiarch enabled (line 81).

**macOS** (preset.2, lines 102-157):
- Output: `dist/build/macos/daccord.zip` (line 112) — Godot exports macOS as a `.zip` containing the `.app` bundle.
- Architecture: `universal` (line 124) — fat binary with both x86_64 and ARM64.
- Code signing: ad-hoc (`codesign/codesign=1`, line 127) — signed but not with a developer identity.
- Notarization disabled (`notarization/notarization=0`, line 136).
- Bundle identifier: `com.daccord-projects.daccord` (line 138).
- Category: `public.app-category.social-networking` (line 140).
- Minimum macOS version: `10.15` (line 144).
- High-DPI enabled (`display/high_res=true`, line 145).
- OpenXR disabled (line 146).

### CI Workflow (`.github/workflows/ci.yml`)

The CI workflow shares the same addon checkout and Godot setup pattern but does not export or create releases:
- Triggered on push/PR to `master` (lines 4-6).
- **Lint job** (lines 13-30): Installs `gdtoolkit` via pip, runs `gdlint scripts/ scenes/`.
- **Test job** (lines 32-79): Checks out addons, sets up Godot (without templates: `include-templates: false`, line 62), runs GUT unit tests from `tests/unit/`.

### Changelog Format (`CHANGELOG.md`)

Uses [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format with Semantic Versioning. Currently has only an `[Unreleased]` section (line 8). When cutting a release, the developer should:
1. Rename `[Unreleased]` to `[0.x.0]` with a date.
2. Add a new empty `[Unreleased]` section above it.
3. The `awk` command in the release job expects headers like `## [0.2.0]` (without a date suffix in the regex match, but dates are harmless as they follow the version bracket).

### Platform Distribution Assets

The `dist/` directory contains platform-specific distribution files:
- `dist/icons/` — App icons at multiple resolutions (16x16 through 512x512 PNG, plus `.ico` for Windows).
- `dist/daccord.desktop` — Linux FreeDesktop entry file for application menus.

### Version Management

The project version is set in `project.godot` at `config/version="0.1.0"` (line 18). This is the only source of truth for the version number. However:
- The version in `project.godot` is not automatically synced with git tags.
- There is no `APP_VERSION` constant in client code — `client.gd` and `config.gd` have no version references.
- The release workflow does not validate that the tag matches `project.godot`'s version.

## Implementation Status

- [x] Release workflow triggered by `v*` tag push
- [x] Parallel cross-platform build matrix (Linux, Windows, macOS)
- [x] Addon checkout and symlinking for accordkit and accordstream
- [x] Godot 4.6 setup with export templates
- [x] Headless project import before export
- [x] Platform-specific artifact packaging (tar.gz, zip)
- [x] Artifact upload between jobs
- [x] Changelog extraction from `CHANGELOG.md`
- [x] Automatic prerelease detection from tag hyphens
- [x] GitHub Release creation with artifacts and notes
- [x] CI pipeline (lint + unit tests) on push/PR
- [x] Export presets configured for all three platforms
- [x] macOS universal binary (x86_64 + ARM64)
- [x] Windows application metadata (icon, company, description)
- [x] Linux export preset
- [ ] Code signing for Windows (disabled, `codesign/enable=false`)
- [ ] macOS notarization (disabled, `notarization/notarization=0`)
- [ ] macOS developer identity signing (ad-hoc only)
- [ ] Custom export templates for reduced build size (stock templates used)
- [ ] Version tag validation against `project.godot`
- [ ] Linux `.desktop` file included in release artifact
- [ ] AccordStream native binaries included in export
- [ ] ARM64 Linux build
- [ ] Integration/e2e tests in CI (only unit tests run)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No Windows code signing | High | `export_presets.cfg` has `codesign/enable=false` (line 64). Users will see SmartScreen/Defender warnings when running the unsigned `.exe`. Requires a code signing certificate. |
| No macOS notarization | High | `notarization/notarization=0` (line 136) and ad-hoc signing only (`codesign/codesign=1`, line 127). macOS Gatekeeper will block the app for most users. Requires an Apple Developer account ($99/year) and notarization workflow. |
| No version tag-to-project validation | Medium | The release workflow does not check that the pushed tag (e.g., `v0.2.0`) matches `config/version` in `project.godot` (currently `"0.1.0"`, line 18). A mismatch means the running app would report a different version than the release. Could add a CI step to validate. |
| Changelog only has `[Unreleased]` | Medium | `CHANGELOG.md` has no versioned sections yet (line 8). The first `v*` tag push will produce a release with the fallback body `"Release v0.1.0"` instead of real notes. |
| Linux `.desktop` file not in artifact | Low | `dist/daccord.desktop` exists but is not included in the `daccord-linux-x86_64.tar.gz` package. The `tar` command packages only `dist/build/linux/*` (line 78), which doesn't include the desktop entry or icons. |
| AccordStream addon may be missing | Medium | The `accordstream` addon is symlinked for the build, but no `.gdextension` file was found in the repo. If the native binary (`.so`/`.dll`/`.dylib`) is not present in the symlinked addon at export time, voice/audio features will be missing from release builds. |
| Stock export templates inflate binary size | Medium | All presets use empty `custom_template/release` (lines 19, 58, 121), meaning stock Godot templates with full 3D, Vulkan, and OpenXR. See [Reducing Build Size](reducing_build_size.md) for optimization plan. |
| No ARM64 Linux build | Low | Only `x86_64` Linux architecture is exported (line 25). ARM64 Linux users (e.g., Raspberry Pi, some Chromebooks) cannot run the release. Would require adding a matrix entry. |
| Only unit tests in CI | Low | The CI workflow (`ci.yml`) runs only `tests/unit` (line 78). Integration and e2e tests are not part of the gate before release. A failing integration test would not block a release tag. |
| Cross-compilation from `ubuntu-latest` | Low | All three platforms build on `ubuntu-latest` (line 16). Godot's cross-compilation is generally reliable, but macOS-specific issues (e.g., universal binary linking, entitlements) may not surface until a user runs the artifact on real hardware. Consider using `macos-latest` runner for the macOS build. |
