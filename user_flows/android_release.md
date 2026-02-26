# Android Release

## Overview

This flow documents the plan and implementation status for building and releasing daccord as an Android APK/AAB. Godot 4.5 supports Android export natively via the GL Compatibility renderer, which daccord already uses. The project has several Android-ready foundations (ETC2/ASTC texture compression, touch input handling, compact layout mode, Sentry Android binaries) but lacks an Android export preset, CI pipeline entry, and Play Store/sideload distribution.

## User Steps

### Building an Android Release (Developer)

1. Developer installs the Android SDK, NDK, and a debug/release keystore (Godot's Editor Settings > Export > Android).
2. Developer adds an "Android" export preset to `export_presets.cfg` with architecture `arm64`, texture format `etc2_astc`, and a package name (e.g., `com.daccord_projects.daccord`).
3. Developer exports locally: `godot --headless --export-release "Android"` (produces `.apk` or `.aab`).
4. For CI: developer adds an `android` matrix entry to `.github/workflows/release.yml` with keystore secrets.
5. Tag push (`v*`) triggers the release workflow, which builds the Android artifact alongside desktop platforms.
6. The signed APK/AAB is uploaded to the GitHub Release and optionally to the Google Play Store.

### Installing on Android (End User)

7. **Sideload:** User downloads the `.apk` from the GitHub Releases page and installs it (requires "Install unknown apps" permission).
8. **Play Store:** User searches for "daccord" on Google Play and installs it (once published).
9. App launches in compact/medium layout mode depending on screen width.

## Signal Flow

```
Developer pushes tag v*
  -> GitHub Actions triggers .github/workflows/release.yml

build job (matrix entry: android):
  -> actions/checkout@v4
  -> Validate version matches tag
  -> Install GUT + Sentry SDK (with caching)
  -> Install Java JDK (setup-java action)
  -> Install Android SDK + NDK (via Godot setup or manual step)
  -> Decode keystore from secret (base64 -> .keystore file)
  -> chickensoft-games/setup-godot@v2 (Godot 4.5 + export templates)
  -> godot --headless --import .
  -> [conditional] Inject Sentry DSN
  -> godot --headless --export-release "Android"
     reads export_presets.cfg:
       preset.N "Android" -> dist/build/android/daccord.apk (or .aab)
  -> Sign APK/AAB with keystore (if not done by Godot export)
  -> actions/upload-artifact@v4

release job:
  -> Download all artifacts (including android)
  -> Create GitHub Release with android artifact attached
```

## Key Files

| File | Role |
|------|------|
| `.github/workflows/release.yml` | Release CI pipeline. Currently has linux, linux-arm64, windows, macos matrix entries. Needs an `android` entry. |
| `export_presets.cfg` | Godot export presets. Currently has 4 presets (Linux, Windows, macOS, Linux ARM64). Needs an Android preset (preset.4). |
| `project.godot` | Project config. Already sets `renderer/rendering_method.mobile="gl_compatibility"` (line 64), `textures/vram_compression/import_etc2_astc=true` (line 65), and a minimum window size of 320x480 (lines 46-47). |
| `scripts/autoload/app_state.gd` | Tracks `LayoutMode` enum (`COMPACT` <500px, `MEDIUM` <768px, `FULL` >=768px). Android phones will typically use COMPACT mode (line 149). |
| `scripts/autoload/updater.gd` | Auto-update system. Uses `OS.get_name()` for platform detection (line 168). Needs an `"android"` branch for update asset matching and update mechanism (Play Store or in-app). |
| `scripts/long_press_detector.gd` | Touch long-press detector using `InputEventScreenTouch` and `InputEventScreenDrag`. Already used by `cozy_message.gd` and `collapsed_message.gd` for context menus. |
| `scenes/main/drawer_gestures.gd` | Edge-swipe gesture handler for opening/closing the sidebar drawer on touch devices. Handles `InputEventScreenTouch` and `InputEventScreenDrag`. |
| `scenes/main/main_window.gd` | Root window. Initializes `DrawerGestures` (line 63), handles backdrop touch dismiss (line 593), manages compact layout with hamburger button. |
| `scripts/autoload/single_instance.gd` | Lock-file based single-instance guard. Uses `OS.execute("kill")` on non-Windows, which won't work on Android — needs platform guard. |
| `addons/sentry/sentry.gdextension` | Sentry SDK. Already ships Android arm64/arm32/x86_64 `.so` binaries (lines 21-26) and the Android Godot plugin AARs. |
| `addons/godot-livekit/godot-livekit.gdextension` | LiveKit GDExtension. No Android binaries listed — voice/video will be unavailable on Android. |

## Implementation Details

### Android-Ready Foundations

**Renderer:** The project uses `gl_compatibility` for both desktop and mobile (project.godot lines 63-64). This is the correct renderer for Android — Vulkan Mobile is an alternative but GL Compatibility has broader device support.

**Texture compression:** `import_etc2_astc=true` is already set (project.godot line 65). The macOS preset and Linux ARM64 preset already use ETC2/ASTC. An Android preset would set `texture_format/etc2_astc=true` and `texture_format/s3tc_bptc=false`.

**Touch input:** Three pieces of touch infrastructure exist:
- `LongPressDetector` (scripts/long_press_detector.gd) — 0.5s long-press with 10px drag cancel threshold. Used by both message types for context menus.
- `DrawerGestures` (scenes/main/drawer_gestures.gd) — Edge swipe from left to open sidebar, swipe/tap backdrop to close. 20px edge zone, 80px threshold, velocity-based snapping.
- Backdrop touch dismiss (scenes/main/main_window.gd line 593) — `InputEventScreenTouch` closes the drawer overlay.

**Responsive layout:** `AppState.LayoutMode.COMPACT` activates below 500px viewport width (app_state.gd line 151). Most Android phones in portrait mode will be in COMPACT mode, which collapses the sidebar into a drawer overlay with a hamburger button. The minimum window size is 320x480 (project.godot lines 46-47), which accommodates small phone screens.

**Sentry SDK:** The Sentry Godot SDK ships Android binaries for arm64, arm32, and x86_64 (sentry.gdextension lines 21-26), plus Android plugin AARs (`sentry_android_godot_plugin.debug.aar` and `.release.aar`). Error reporting should work out of the box on Android.

### What Needs to Be Added

**Export preset:** An Android export preset in `export_presets.cfg` with:
- Platform: `"Android"`
- Package name: `com.daccord_projects.daccord`
- Min SDK: 24 (Android 7.0, Godot 4.5 minimum)
- Target SDK: 34 (current Play Store requirement)
- Architecture: `arm64` (or both `arm64` + `arm32`)
- Texture format: ETC2/ASTC only
- Screen orientation: full sensor (auto-rotate)
- Internet permission: required (chat client)
- Microphone permission: required for voice
- Camera permission: required for video chat
- Icon: adaptive icon from `dist/icons/`

**CI pipeline entry:** A new matrix entry in `release.yml`:
```yaml
- platform: android
  preset: Android
  artifact: daccord-android-arm64
  extension: apk
  os: ubuntu-latest
```

Plus build steps:
- Install Java JDK (`actions/setup-java@v4`)
- Install/configure Android SDK and NDK
- Decode keystore from `ANDROID_KEYSTORE_BASE64` secret
- Configure Godot's Android SDK path via editor settings or CLI flags
- Export with `godot --headless --export-release "Android"`
- Sign with `jarsigner` or `apksigner` if not done during export

**Updater platform support:** `updater.gd` `_parse_release()` (line 168) uses `OS.get_name().to_lower()` which returns `"android"` on Android. The asset matching loop needs an `elif platform_key == "android"` branch to find `.apk` assets. The `apply_update_and_restart()` method (line 434) replaces the binary on disk, which won't work on Android — updates should redirect to the Play Store or trigger an APK install intent.

**Single-instance guard:** `single_instance.gd` uses `OS.execute("kill", ["-0", str(pid)])` (line 38) which may not work on Android's restricted process model. This should be skipped or use Android-specific instance detection (e.g., single-task launch mode in the manifest).

**File paths:** `user://` paths resolve to Android's internal app storage directory, which is correct. No changes needed for `Config`, profile storage, or emoji cache paths. However, `OS.get_executable_path()` returns an empty or non-writable path on Android, breaking the updater's binary replacement strategy.

### LiveKit on Android

The `godot-livekit.gdextension` has no Android library entries. Voice and video features will be unavailable on Android builds. The release workflow's safety removal step (which removes the `.gdextension` when platform binaries are missing) will handle this gracefully — the extension file will be removed and LiveKit features will be disabled via null guards. Once an Android `.so` is built for godot-livekit, it would need entries like:
```
android.arm64 = "res://addons/godot-livekit/bin/libgodot-livekit.android.arm64.so"
```

### Android-Specific UX Considerations

**Back button:** Android's system back button emits `ui_cancel` in Godot. This should close open dialogs, the settings panel, the drawer, and navigate back through the UI stack.

**On-screen keyboard:** Text input fields (`TextEdit`, `LineEdit`) in the composer and search bar will trigger the Android virtual keyboard. The viewport may need to resize or scroll to keep the input field visible above the keyboard.

**Notifications:** Android push notifications are not implemented. The client only receives messages while connected to the gateway WebSocket. Background notification delivery would require Firebase Cloud Messaging (FCM) integration on both client and server.

**App lifecycle:** Android may kill background apps. The WebSocket gateway connection will drop when the app is backgrounded. The existing reconnection logic (documented in [Server Disconnects & Timeouts](server_disconnects_timeouts.md)) should handle this, but reconnect timing may need tuning for mobile network conditions.

### Distribution

**GitHub Releases (sideload):** The `.apk` artifact would be attached to GitHub Releases alongside desktop artifacts. Users enable "Install unknown apps" and install directly. The updater would need to open the release page or trigger an APK install intent for updates.

**Google Play Store:** Requires a Google Play Developer account ($25 one-time fee), app listing metadata (screenshots, description, privacy policy), and an AAB (Android App Bundle) instead of APK. The CI pipeline would need to upload to Play Store via the `google-github-actions/upload-cloud-storage` or Fastlane.

**F-Droid:** Open-source alternative app store. Requires reproducible builds and no proprietary dependencies. The Sentry SDK may need to be optional for F-Droid compliance.

## Implementation Status

- [x] GL Compatibility renderer configured for mobile (project.godot line 64)
- [x] ETC2/ASTC texture compression enabled (project.godot line 65)
- [x] Touch long-press for context menus (long_press_detector.gd)
- [x] Edge-swipe drawer open/close gestures (drawer_gestures.gd)
- [x] Compact layout mode for narrow viewports (app_state.gd line 149)
- [x] Minimum window size 320x480 suitable for phones (project.godot lines 46-47)
- [x] Sentry SDK ships Android binaries (sentry.gdextension lines 21-26)
- [x] LiveKit gracefully disabled when platform binary missing
- [ ] Android export preset in `export_presets.cfg`
- [ ] Android matrix entry in `release.yml`
- [ ] Java JDK + Android SDK/NDK setup in CI
- [ ] Keystore management (generation, secret storage, CI decode)
- [ ] Updater `_parse_release()` Android asset matching
- [ ] Updater Android update mechanism (Play Store redirect or APK install intent)
- [ ] Single-instance guard Android platform check
- [ ] Android back button navigation handling
- [ ] Adaptive icon for Android (foreground/background layers)
- [ ] Android manifest permissions (internet, microphone, camera)
- [ ] Google Play Store listing and AAB upload
- [ ] Push notifications via FCM
- [ ] LiveKit Android binary (voice/video on Android)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No Android export preset | High | `export_presets.cfg` has no Android entry. Godot needs this to produce APK/AAB output. Must define package name, SDK versions, permissions, and architecture. |
| No Android CI pipeline entry | High | `release.yml` matrix (lines 29-49) only includes linux, linux-arm64, windows, macos. Needs an `android` entry with Java/SDK setup steps. |
| Updater ignores Android | Medium | `_parse_release()` (updater.gd line 168) has no `"android"` branch in asset matching. `apply_update_and_restart()` (line 434) replaces the binary on disk, which is impossible on Android. Needs Play Store redirect or APK install intent. |
| Single-instance guard may break | Medium | `single_instance.gd` line 38 uses `kill -0` to check PIDs, which may fail on Android's restricted process model. Should skip or use manifest `singleTask` launch mode. |
| No Android back button handling | Medium | Android back button emits `ui_cancel` but no global handler maps it to close drawers, dialogs, or navigate back. |
| No LiveKit Android binary | Medium | `godot-livekit.gdextension` has no Android entry. Voice and video will be unavailable. Extension is safely removed at build time. |
| No keystore setup | Medium | Android APKs must be signed. Need to generate a release keystore, store it as a base64 GitHub secret, and decode it in CI. Unsigned APKs cannot be installed. |
| No push notifications | Low | Messages only arrive while the gateway WebSocket is connected. Background delivery requires FCM on both client and server. |
| No adaptive icon | Low | Android requires adaptive icons (foreground + background layers). Current icons in `dist/icons/` are standard PNGs. Need `res/mipmap-*` directories or Godot's icon override. |
| No Play Store distribution | Low | Sideload via APK is sufficient initially. Play Store requires developer account, AAB format, and listing metadata. |
| No F-Droid compliance | Low | F-Droid requires reproducible builds and no proprietary SDKs. Sentry may need to be optional. |
| On-screen keyboard viewport handling | Low | Virtual keyboard may obscure the composer `TextEdit`. May need viewport resize or scroll-into-view logic. |
