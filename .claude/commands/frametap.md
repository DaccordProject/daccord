---
description: Edit frametap C++ source, build, and update godot-livekit
argument-hint: <description of change>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(cd "/home/krazy/Documents/GitHub/frametap" && scons:*), Bash(cp:*), Bash(ls:*), Bash(scons:*), Bash(gh:*), Bash(git:*), Bash(cd:*), Bash(find:*), Bash(pkg-config:*), Task, Skill
---

You are editing **frametap** — a cross-platform C++ screen capture library that provides monitor/window enumeration and frame grabbing. After making changes, you will build frametap, copy the artifacts into godot-livekit, then invoke the `/godot-livekit` skill to rebuild the GDExtension and copy binaries into daccord.

## Arguments

`$ARGUMENTS` describes the change to make (e.g., "trap X11 BadWindow errors during cleanup", "add frame rate limiting").

## Repository Layout

**Source repo:** `/home/krazy/Documents/GitHub/frametap/`
**GitHub:** https://github.com/krazyjakee/frametap (private)

### Key paths

| Path | Purpose |
|------|---------|
| `include/frametap/frametap.h` | Public API — `FrameTap` class, factory functions, `CaptureError` |
| `include/frametap/types.h` | Public types — `Monitor`, `Window`, `Rect`, `ImageData`, `Frame` |
| `include/frametap/queue.h` | Thread-safe queue utility |
| `src/frametap.cpp` | Core `FrameTap` implementation (pimpl `Impl` struct), dispatches to platform backend |
| `src/backend.h` | Abstract `Backend` interface that platform backends implement |
| `src/platform/linux/linux_backend.cpp` | Linux runtime dispatch — picks X11 or Wayland backend |
| `src/platform/linux/linux_backend.h` | Linux backend header |
| `src/platform/linux/x11/x11_backend.cpp` | X11 async capture backend (XShm, XDamage) |
| `src/platform/linux/x11/x11_screenshot.cpp` | X11 synchronous screenshot (XGetImage / XShmGetImage) |
| `src/platform/linux/x11/x11_enumerate.cpp` | X11 monitor/window enumeration |
| `src/platform/linux/x11/x11_backend.h` | X11 backend header |
| `src/platform/linux/wayland/wl_backend.cpp` | Wayland capture via PipeWire + XDG Desktop Portal |
| `src/platform/linux/wayland/wl_portal.cpp` | D-Bus portal session management |
| `src/platform/linux/wayland/wl_enumerate.cpp` | Wayland monitor/window enumeration |
| `src/platform/macos/macos_backend.mm` | macOS ScreenCaptureKit backend |
| `src/platform/windows/windows_backend.cpp` | Windows DXGI Desktop Duplication backend |
| `src/platform/windows/windows_screenshot.cpp` | Windows synchronous screenshot |
| `src/platform/windows/windows_enumerate.cpp` | Windows monitor/window enumeration |
| `src/util/color.h` | Pixel format conversion utilities |
| `src/util/safe_alloc.h` | Safe memory allocation wrapper |
| `SConstruct` | SCons build configuration |
| `tests/` | Catch2 unit tests |

### Architecture

`FrameTap` uses a pimpl pattern (`Impl` in `src/frametap.cpp`). The `Impl` holds a platform-specific `Backend` (from `src/backend.h`). On Linux, `LinuxBackend` dispatches to either `X11Backend` or `WaylandBackend` at runtime based on `$XDG_SESSION_TYPE`.

**Capture modes:**
- **Synchronous** (`screenshot()`): One-shot grab, returns `ImageData` directly. Used by godot-livekit every frame in `_process()`.
- **Asynchronous** (`start_async()` + `on_frame()` callback): Background thread delivers frames via callback. Not currently used by godot-livekit on Linux (X11 callback doesn't fire reliably).

### Linux dependencies (system packages)

| Library | Package | Purpose |
|---------|---------|---------|
| X11, Xext, Xfixes, Xinerama | `libx11-dev`, `libxext-dev`, `libxfixes-dev`, `libxinerama-dev` | X11 capture |
| PipeWire | `libpipewire-0.3-dev` | Wayland screen capture |
| libsystemd (sd-bus) | `libsystemd-dev` | Portal D-Bus communication |
| wayland-client | `libwayland-dev` | Wayland monitor enumeration |
| Catch2 (tests only) | `catch2` | Unit test framework |

## Build Process

### Build the static library (Linux)

```bash
cd "/home/krazy/Documents/GitHub/frametap" && scons
```

This produces `libframetap.a` in the repo root.

Other platforms: builds natively on macOS (`scons`) and Windows (`scons`).

### Build options

- `scons sanitize=address` — AddressSanitizer
- `scons sanitize=thread` — ThreadSanitizer
- `scons test` — Build and run Catch2 tests
- `scons cli` — Build the CLI tool (`cli/frametap`)

### Copy artifacts to godot-livekit

After a successful build, copy the library and headers:

```bash
cp "/home/krazy/Documents/GitHub/frametap/libframetap.a" \
   "/home/krazy/Documents/GitHub/godot-projects/godot-livekit/frametap/lib/libframetap.a"

cp "/home/krazy/Documents/GitHub/frametap/include/frametap/"*.h \
   "/home/krazy/Documents/GitHub/godot-projects/godot-livekit/frametap/include/frametap/"
```

### Rebuild godot-livekit

After copying, invoke the godot-livekit skill to rebuild the GDExtension:

```
/godot-livekit rebuild after frametap update
```

## GDExtension Integration

godot-livekit wraps frametap via `src/livekit_screen_capture.cpp`:
- `LiveKitScreenCapture::create_for_monitor()` → `FrameTap(Monitor)`
- `LiveKitScreenCapture::create_for_window()` → `FrameTap(Window)`
- `LiveKitScreenCapture::screenshot()` → `tap_->screenshot()`
- `LiveKitScreenCapture::start()` → `tap_->start_async()` with `on_frame()` callback
- `LiveKitScreenCapture::close()` → `tap_->stop()` + `tap_.reset()`

Changes to frametap's public API may require corresponding updates to `livekit_screen_capture.cpp`.

## Task

1. Read the relevant source files in the frametap repo
2. Make the requested changes based on `$ARGUMENTS`
3. Build: `cd "/home/krazy/Documents/GitHub/frametap" && scons`
4. If the build fails, fix the errors and rebuild
5. Copy `libframetap.a` and headers to godot-livekit
6. Invoke `/godot-livekit rebuild after frametap update` to rebuild the GDExtension and copy binaries to daccord
7. Summarize what was changed (frametap files, C++ API changes if any, binary copied)
