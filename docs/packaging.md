# Package-manager preparation

Daccord has review templates for WinGet, Scoop, Chocolatey, Homebrew Cask, and
Flatpak/AppStream under `dist/packaging/templates/`. **These are not published
catalog entries.** Issue #355 remains open until installations are verified and
external catalog submissions are accepted.

The included `reference/` snapshot describes GitHub release **v0.2.20**, published
2026-09-12. It anchors review URLs and checksums; that release predates the
package-manager updater opt-out and must not be submitted with these manifests.
No package-manager publishing token or Chocolatey API key is configured by this
change.

## Generate concrete manifests

Python 3.11 or later is required. The generator is offline and uses only its
standard library. It requires a stable `vMAJOR.MINOR.PATCH` GitHub release JSON
object with `published_at`, asset URLs, and GitHub SHA-256 digests, plus the exact
published `SHA256SUMS.txt` bytes. It checks that the checksum file matches its
GitHub digest, each selected asset agrees with both sources, and every download
URL points to the same versioned release tag. It rejects missing/duplicate
assets and checksums, path-bearing checksum names, and unexpected URLs.

```sh
python3 scripts/package_manifests.py \
  --release-json dist/packaging/reference/release.json \
  --checksums dist/packaging/reference/SHA256SUMS.txt \
  --output dist/packaging/generated
```

For a future release, download its GitHub metadata and checksum file first:

```sh
release_tag=v0.2.21  # Replace with an actually published stable release.
mkdir -p release-metadata
gh api "repos/DaccordProject/daccord/releases/tags/$release_tag" > release-metadata/release.json
gh release download "$release_tag" --repo DaccordProject/daccord \
  --pattern SHA256SUMS.txt --dir release-metadata
python3 scripts/package_manifests.py \
  --release-json release-metadata/release.json \
  --checksums release-metadata/SHA256SUMS.txt \
  --output dist/packaging/generated
```

Supply `--assets-dir DIRECTORY` to additionally hash downloaded selected assets
present there. Missing binaries are not silently reported as verified; the
metadata consistency checks still run, and package managers verify downloaded
bytes at installation. Supply `--check` to compare existing generated files
without writing. Editing templates rather than generated files keeps updates
repeatable. The generator deliberately records `publication_ready: false` in
`PREPARATION.json`; rendering manifests is not platform or catalog validation.

## Updater ownership

Manager-owned installations disable the application's self-updater using the
shared runtime/build contract:

| Manager | Opt-out mechanism |
| --- | --- |
| WinGet | Inno `/CURRENTUSER /PACKAGE_MANAGER=winget` installs the adjacent marker. |
| Chocolatey | Inno `/ALLUSERS /PACKAGE_MANAGER=chocolatey` installs the adjacent marker. |
| Scoop | A post-install hook writes `daccord.package-manager` beside `daccord.exe`. |
| Flatpak | The launcher exports `DACCORD_PACKAGE_MANAGER=flatpak`; runtime detection also recognizes its app ID. |
| Homebrew | A separately signed and notarized DMG built with `--dart-define=PACKAGE_MANAGER=true`. |

Do not modify `Daccord.app` after signing to add a marker. The cask has no bundle
mutation hook. When the managed DMG exists, regenerate with
`--macos-asset daccord-macos-universal-package-manager.dmg`; it must appear in the
same release metadata and checksum file. The default standard DMG remains useful
for reviewing the current download layout, but is not an approved Homebrew
release. The `PACKAGE_MANAGER` flag disables only self-update and does not make
the application an App Store build.

User data lives in `Documents/daccord/data`. Scoop does not declare `persist`,
move this data beside the executable, or delete it. Chocolatey delegates removal
to the exact Inno uninstall key and retains personal data. The cask's optional
`zap` removes only its application cache, never the Documents directory.

## Manager validation and submission

Run the generator's offline tests before manager-specific validation:

```sh
python3 -m unittest discover -s test/packaging -p 'test_*.py'
```

**WinGet:** validate the generated three-file directory with `winget validate
--manifest PATH`, then perform local install/update/uninstall checks on Windows.
Compare the installer-detected publisher, scope, AppId, switches, and installed
version with the manifest. The current Inno identity is `Daccord`, publisher
`daccord-projects`, AppId `{B8F3A2D1-7C4E-4A9B-8D5F-1E6C3B2A0F47}`. Submit to
`microsoft/winget-pkgs` only after those checks and a marker-aware release. The
manifest layout and Inno silent behavior follow Microsoft's
[manifest documentation](https://learn.microsoft.com/en-us/windows/package-manager/package/manifest).

**Scoop:** validate `scoop/daccord.json` with Scoop's manifest tests and install
it locally using `scoop install ./dist/packaging/generated/scoop/daccord.json`.
The release ZIP has `daccord.exe` at its root. Verify shortcuts, shim, upgrade,
and marker preservation. The autoupdate rule uses the stable GitHub release and
extracts the ZIP's hash from `SHA256SUMS.txt`, following the official
[manifest](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests) and
[autoupdate](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifest-Autoupdate)
contracts. Extras submission is still pending; the portable manifest does not
claim to register Windows deep links.

**Chocolatey:** run `choco pack` in the generated `chocolatey/` directory, inspect
the `.nupkg`, and test installation, upgrade, and uninstallation in a disposable
Windows environment. The wrapper downloads the signed Inno installer with an
explicit SHA-256 checksum and uses
[Install-ChocolateyPackage](https://docs.chocolatey.org/en-us/create/functions/install-chocolateypackage/).
Account ownership, moderation, an API key, and approved publishing automation
remain outstanding. No `choco push` runs automatically.

**Homebrew:** validate and test the cask in a project-owned tap on both Intel and
Apple Silicon, including Gatekeeper/notarization and updater opt-out. The app
artifact is `Daccord.app`, bundle ID `com.cattrall.daccord`; the cask declares the
source deployment target, macOS Catalina or later. Package review must verify
that minimum against the actual built dependencies. Homebrew's
[cask cookbook](https://docs.brew.sh/Cask-Cookbook) describes the stanza contract.
The project currently falls below the official repository's
[notability criteria](https://docs.brew.sh/Acceptable-Casks); a personal/project
tap and its ownership must be established before advertising an install command.

**Flatpak:** the proposed app ID is `io.github.DaccordProject.daccord`, matching
the GitHub repository name. It uses GNOME runtime/SDK 49 and only the published
x86_64 bundle. The draft builds pinned FFmpeg, libass, libplacebo, and libmpv
modules, then copies the Flutter bundle without stripping its root directory.
GNOME supplies GTK and libsecret; no host libmpv is assumed. Dependency pins and
build options need a real sandbox build and ABI audit before submission. In
particular, inspect every bundled plugin's dynamic dependencies and confirm the
runtime's compiler, media codec coverage, EGL rendering, and libmpv ABI.

```sh
flatpak-builder --user --install-deps-from=flathub --force-clean \
  build-flatpak dist/packaging/generated/flatpak/io.github.DaccordProject.daccord.json
flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest \
  dist/packaging/generated/flatpak/io.github.DaccordProject.daccord.json
flatpak run --command=flatpak-builder-lint org.flatpak.Builder appstream \
  dist/packaging/generated/flatpak/io.github.DaccordProject.daccord.metainfo.xml
```

These are proposed validation commands; they have not established that the draft
builds. Review [Flatpak manifests](https://docs.flatpak.org/en/latest/manifests.html)
and [sandbox permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html)
when adjusting dependencies or access. Network, PulseAudio, camera/device,
Wayland/fallback X11, PipeWire, and Secret Service access support the existing
voice/video/credential features. The filesystem grant is limited to Daccord's
Documents subdirectory. Portal file picking and screen capture need actual
Wayland/X11 tests; no broad session-bus or home-directory permission is granted.
The desktop entry registers `daccord://` links.

AppStream includes truthful application metadata, a release entry, and a
version-pinned existing tablet screenshot. **Replace that screenshot with a
current native Linux desktop capture before Flathub submission.** Validate the
OARS rating, screenshot quality, app ID, permissions, redistribution/source
obligations for the binary bundle, and all launch behavior against
[Flathub requirements](https://docs.flathub.org/docs/for-app-authors/requirements)
and [metadata guidelines](https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines).
`x-checker-data` proposes future release updates, but does not replace these
reviews. Catalog submission and moderation are external steps described in
[Flathub's submission guide](https://docs.flathub.org/docs/for-app-authors/submission).

## Advisory release artifacts

`.github/workflows/package-manifests.yml` supports `workflow_call` and manual
`workflow_dispatch`, both requiring a published stable tag. The release workflow
calls it after successful publication. A `release: published` event alone is
insufficient when the release was created using `GITHUB_TOKEN`.

The workflow uses a read-only repository token, downloads metadata/checksums,
generates manifests, runs offline tests, and uploads review artifacts for 30 days.
Its job has `continue-on-error: true`, so packaging preparation is advisory. It
does not check out untrusted release-tag source, submit catalog PRs, push
packages, or request publishing credentials. Automatic catalog updates should be
added only after the first approved submission, using manager-specific accounts
and narrowly scoped secrets.
