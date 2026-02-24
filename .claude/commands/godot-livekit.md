---
description: Edit godot-livekit C++ source, build, and update the addon in this repo
argument-hint: <description of change>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(cd "/home/krazy/Documents/GitHub/Godot Projects/godot-livekit" && ./build.sh:*), Bash(cp:*), Bash(ls:*), Bash(scons:*), Bash(gh:*), Bash(git:*), Bash(cd:*), Task
---

You are editing the **godot-livekit** GDExtension — a C++ wrapper around the LiveKit SDK that exposes real-time voice, video, and data APIs to GDScript. After making changes, you will build the extension and copy the updated binaries into the daccord project.

## Arguments

`$ARGUMENTS` describes the change to make (e.g., "make disconnect non-blocking", "add a new signal for track quality").

## Repository Layout

**Source repo:** `/home/krazy/Documents/GitHub/Godot Projects/godot-livekit/`
**GitHub:** https://github.com/NodotProject/godot-livekit (public, MIT)
**Latest release:** v0.3.2

### Key paths

| Path | Purpose |
|------|---------|
| `src/` | All C++ source files (.h and .cpp pairs) |
| `src/livekit_room.cpp` | Room connection, disconnect, participant management |
| `src/livekit_participant.cpp` | Local/Remote participant, publish/unpublish tracks, RPC |
| `src/livekit_track.cpp` | Track hierarchy (local/remote, audio/video) |
| `src/livekit_track_publication.cpp` | Track publication wrappers |
| `src/livekit_video_stream.cpp` | Video frame reception with background reader thread |
| `src/livekit_audio_stream.cpp` | Audio frame reception with background reader thread |
| `src/livekit_video_source.cpp` | Video capture from Godot Images |
| `src/livekit_audio_source.cpp` | Audio capture from float buffers |
| `src/livekit_e2ee.cpp` | E2EE classes (Linux only, opt-in) |
| `src/register_types.cpp` | GDExtension class registration |
| `SConstruct` | SCons build configuration |
| `build.sh` | Cross-platform build script |
| `addons/godot-livekit/` | Built addon (binaries + .gdextension) |
| `test/unit/` | GUT unit tests |
| `docs/` | Jekyll docs (API reference, quickstart, installation) |

### Dependencies (fetched automatically by build.sh)

- **godot-cpp** (prebuilt): `godot-4.5-stable` from NodotProject/godot-cpp-builds
- **LiveKit C++ SDK** (prebuilt): v0.3.1 from livekit/client-sdk-cpp

## Build Process

### Build for the current platform (Linux)

```bash
cd "/home/krazy/Documents/GitHub/Godot Projects/godot-livekit" && ./build.sh linux
```

This runs `scons platform=linux arch=x86_64 target=template_release`, producing:
- `addons/godot-livekit/bin/libgodot-livekit.linux.x86_64.so`

Other platforms: `./build.sh macos` (universal), `./build.sh windows` (x86_64 cross-compile).

### Copy the updated addon to daccord

After a successful build, copy the `.so` and dependency libraries:

```bash
cp "/home/krazy/Documents/GitHub/Godot Projects/godot-livekit/addons/godot-livekit/bin/libgodot-livekit.linux.x86_64.so" \
   "/home/krazy/Documents/GitHub/daccord-projects/daccord/addons/godot-livekit/bin/libgodot-livekit.linux.x86_64.so"
```

If the LiveKit shared libraries were also updated:
```bash
cp "/home/krazy/Documents/GitHub/Godot Projects/godot-livekit/addons/godot-livekit/bin/liblivekit_ffi.so" \
   "/home/krazy/Documents/GitHub/daccord-projects/daccord/addons/godot-livekit/bin/liblivekit_ffi.so"
cp "/home/krazy/Documents/GitHub/Godot Projects/godot-livekit/addons/godot-livekit/bin/liblivekit.so" \
   "/home/krazy/Documents/GitHub/daccord-projects/daccord/addons/godot-livekit/bin/liblivekit.so"
```

## E2EE Exclusion

E2EE (end-to-end encryption) is **opt-in** and **Linux-only**. It requires a LiveKit SDK build that includes E2EE symbols.

- The SConstruct flag is `e2ee=yes` (default: `no`)
- When disabled, all E2EE code is excluded via `#ifdef LIVEKIT_E2EE_SUPPORTED`
- `register_types.cpp` conditionally registers E2EE classes
- `livekit_e2ee.cpp` is conditionally added to the source list in SConstruct
- **Do NOT enable E2EE** for local builds or CI unless specifically needed — the prebuilt LiveKit SDK may not include the required symbols, causing linker errors or Godot load failures

Both CI workflows (`build_and_test.yml`, `build_release.yml`) call `./build.sh <platform>` without `e2ee=yes`. Local builds must match: never pass `e2ee=yes` to `scons` unless you have a compatible SDK.

## GitHub Actions

**Repo:** https://github.com/NodotProject/godot-livekit/actions

### build_and_test.yml (on PR / manual)
- Matrix: Linux, Windows, macOS
- Steps: checkout → install SCons → `./build.sh <platform>` → download Godot 4.5 → import project → run tests (Linux/macOS only)
- Tests use 30s timeout (known Godot/GUT cleanup hang)

### build_release.yml (on tag push `v*.*.*` / manual)
- Matrix: Linux, Windows, macOS
- Steps: checkout → install SCons → `./build.sh <platform>` → package addon → upload artifact
- Combines per-platform artifacts into `godot-livekit-release.zip`
- Creates a GitHub Release with the zip attached

### deploy_docs.yml
- Deploys Jekyll docs to GitHub Pages

## Releases

Releases are created by pushing a tag matching `v*.*.*`:
```bash
git tag v0.3.3 && git push origin v0.3.3
```

The `build_release.yml` workflow builds all platforms and creates a release with `godot-livekit-release.zip`. The daccord release CI (`release.yml`) downloads the **latest** godot-livekit release via `gh release download --repo NodotProject/godot-livekit --pattern "godot-livekit-addon.zip"`.

## GDScript Adapter

The daccord project wraps the GDExtension with a GDScript adapter:
- **`scripts/autoload/livekit_adapter.gd`** — bridges LiveKitRoom signals to the signal surface that `client_voice.gd` expects (session state, peer join/leave, track received, audio levels)

Changes to the C++ API may require corresponding updates to the adapter.

## Threading Notes

Several C++ methods involve background threads:
- `LiveKitRoom::connect_to_room()` — runs `Room::Connect()` on a background thread
- `LiveKitRoom::disconnect_from_room()` — runs room destruction on a background thread
- `LiveKitVideoStream` / `LiveKitAudioStream` — background reader threads with 20ms join timeout then detach
- `LiveKitLocalParticipant::perform_rpc()` — runs SDK call on a background thread
- `LiveKitLocalParticipant::unpublish_track()` — **synchronous**, calls SDK directly on calling thread (can block)

When adding new SDK calls, always consider whether they might block and should run on a background thread with `call_deferred` for the result.

## Task

1. Read the relevant source files in the godot-livekit repo
2. Make the requested changes based on `$ARGUMENTS`
3. Build: `cd "/home/krazy/Documents/GitHub/Godot Projects/godot-livekit" && ./build.sh linux`
4. If the build fails, fix the errors and rebuild
5. Copy the updated `.so` to the daccord project
6. If the change affects the GDScript API surface, update `scripts/autoload/livekit_adapter.gd` in daccord
7. Summarize what was changed (C++ files, GDScript files, binary copied)
