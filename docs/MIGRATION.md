# Migrating to the public `DaccordProject/daccord` URL (hard cutover)

Tracks issue #86. The Flutter client (this repo) ships under the **existing
public URL** `github.com/DaccordProject/daccord` — already shared widely — rather
than from a new/second repo, with a **hard cutover** for existing users (no
auto-update bridge from the old Godot client).

## Why a hard cutover, not an auto-update migration

The Godot client's deployed auto-updater can't safely install a Flutter desktop
build: its apply step copies only flat files next to the binary and skips
subdirectories. A Flutter desktop bundle is a tree (`data/flutter_assets/`, etc.),
so those directories would be dropped and the updated app would launch broken.
Bridging would require single-file packaging or a rewritten recursive-copy
updater in a "bridge" Godot release. We skip all of that and announce manually.

> The Flutter self-updater added in #87 copies the **whole bundle tree**, fixing
> the flat-copy bug for everyone who is already on a Flutter build.

## Cutover checklist

- [ ] Freeze the Godot client in `DaccordProject/daccord`: branch current `main`
      → `legacy-godot` and tag it (e.g. `godot-final`). History stays in place.
- [ ] Move this Flutter codebase onto `main` of `DaccordProject/daccord`.
- [ ] Leave existing Godot GitHub Releases untouched — they stay downloadable
      (releases attach to the repo, not a branch).
- [ ] First Flutter release tag must be strictly higher than the last Godot tag
      (`0.1.21`) so GitHub treats it as **Latest**. This repo is at `0.2.0`.
- [ ] Confirm the release workflow's asset names and self-updater target
      (`kGithubRepo = DaccordProject/daccord` in `lib/shared/app_info.dart`).
- [ ] Post the Discord announcement: "If you installed before <DATE>, download
      the new version here: <LINK>."

## Release artifacts the updater expects

`.github/workflows/release.yml` publishes, per tag `v<version>` (must match
`pubspec.yaml`):

| Platform | Asset | Self-update path |
|----------|-------|------------------|
| Windows  | `daccord-windows-x86_64.zip`, `daccord-windows-x86_64-setup.exe` | in-place binary swap (#87) |
| macOS    | `daccord-macos-universal.dmg` | replace `.app`, strip quarantine (#87) |
| Linux    | `daccord-linux-x86_64.tgz`, `daccord-linux-x86_64.deb` | replace bundle tree (#87), or `pkexec dpkg -i` for a system install (#178) |
| Android  | `daccord-android.apk` | system installer (#88) |
| Web      | `daccord-web.zip` | service-worker reload (#91) |
| All      | `SHA256SUMS.txt` | integrity check before swap (#87) |

The Linux portable bundle ships as `.tgz` and releases must **never** publish an
asset ending in `.tar.gz` (the release workflow fails if one appears). Clients at
v0.2.6 and earlier select a `.tar.gz` on Linux without checking that the install
root is writable, so a `.deb` install downloads it, attempts a swap into
root-owned `/opt` that cannot succeed, and relaunches the old build with nothing
shown to the user. Those clients can't be fixed in code — withholding the suffix
they key on is what routes them to the `.deb` download instead.

Code signing / notarization (#90) and an iOS distribution path (#89) are tracked
separately and are **not** part of this cutover.

## Notes

- License stays GPL-3.0.
- Self-update to a system-protected install location (e.g. Windows
  `Program Files`, system `/opt`) needs elevation and may fail without it — the
  same limitation the Godot updater had. Per-user installs update cleanly.
