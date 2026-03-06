# Android Release

## Overview

This flow documents both the build/release pipeline and the end-user experience for daccord on Android. Godot 4.5 supports Android export natively via the GL Compatibility renderer, which daccord already uses. The project has an Android export preset, CI pipeline entry with keystore management, touch interaction (long-press, edge-swipe drawer), responsive layout modes, and LiveKit Android binaries in the GDExtension manifest.

## User Steps

### Building an Android Release (Developer)

1. Developer installs the Android SDK, NDK, and a debug/release keystore (Godot's Editor Settings > Export > Android).
2. Developer uses the existing "Android" export preset (preset.4) in `export_presets.cfg` with architecture `arm64`, texture format `etc2_astc`, and package name `com.daccord_projects.daccord`.
3. Developer exports locally: `godot --headless --export-release "Android"` (produces `.apk`).
4. For CI: tag push (`v*`) triggers the release workflow, which builds the Android artifact alongside desktop platforms.
5. The signed APK is uploaded to the GitHub Release.

### Installing on Android (End User)

6. **Sideload:** User downloads the `.apk` from the GitHub Releases page and installs it (requires "Install unknown apps" permission).
7. **Play Store:** User searches for "daccord" on Google Play and installs it (once published).
8. App launches in compact/medium layout mode depending on screen width.

### Using daccord on Android (End User)

9. **First launch:** App shows the welcome screen with an Add Server button. User taps it, enters the server URL, and authenticates (same flow as desktop).
10. **Navigating spaces/channels:** User taps the hamburger button (top-left) to open the sidebar drawer, or swipes from the left edge of the screen. The sidebar slides in with a dimmed backdrop. User taps a space icon, then a channel, and the drawer auto-closes.
11. **Reading messages:** Messages render in the main content area. The cozy/collapsed message layout adapts -- collapsed messages always show timestamps in compact mode (collapsed_message.gd line 82) since hover is not available on touch.
12. **Sending messages:** User taps the composer text input at the bottom. The Android virtual keyboard appears. User types a message and taps the Send button (or presses Enter on a hardware keyboard). Shift+Enter inserts a newline.
13. **Replying to a message:** User long-presses (0.5 seconds) on a message to open the context menu, then taps "Reply". A reply bar appears above the composer with the referenced author.
14. **Editing/deleting a message:** User long-presses their own message, then taps "Edit" or "Delete" from the context menu. Edit enters inline editing mode; Delete shows a confirmation dialog.
15. **Adding reactions:** User long-presses a message and taps "Add Reaction" from the context menu. The emoji picker opens above the composer area.
16. **Closing the sidebar drawer:** User taps the dimmed backdrop area, swipes the sidebar to the left, or taps a channel (which auto-closes the drawer).
17. **Viewing images:** User taps an inline image to open the image lightbox. Taps the close button to dismiss (backdrop touch dismiss not yet implemented).
18. **Switching spaces:** User opens the sidebar drawer, taps a different space icon in the guild bar, selects a channel.
19. **Direct messages:** User opens the sidebar drawer, taps the DM button in the guild bar, selects a DM conversation.
20. **Rotating the device:** Layout may switch between COMPACT (<500px) and MEDIUM (<768px) modes. In MEDIUM mode, the sidebar is inline (no drawer), and the channel panel auto-hides/shows on selection.

## Signal Flow

### Build & Release

```
Developer pushes tag v*
  -> GitHub Actions triggers .github/workflows/release.yml

build job (matrix entry: android, lines 51-54):
  -> actions/checkout@v4
  -> Validate version matches tag
  -> Install GUT + Sentry SDK (with caching)
  -> Install Java JDK 17 (setup-java action, lines 77-82)
  -> Install Android SDK + NDK via android-actions/setup-android@v3 (lines 84-95)
     installs: platform-tools, build-tools;34.0.0, platforms;android-34, ndk;23.2.8568313
  -> Decode keystore from ANDROID_KEYSTORE_BASE64 secret (lines 97-103)
     fallback: generate debug keystore (lines 105-118)
  -> chickensoft-games/setup-godot@v2 (Godot 4.5 + export templates)
  -> Configure Godot Android SDK path in editor_settings-4.tres (lines 331-343)
  -> Inject keystore into export_presets.cfg (lines 345-356)
  -> godot --headless --import .
  -> [conditional] Inject Sentry DSN
  -> godot --headless --export-release "Android"
     reads export_presets.cfg preset.4 -> dist/build/android/daccord.apk
  -> Package: copy to daccord-android-arm64.apk (lines 451-454)
  -> actions/upload-artifact@v4

release job:
  -> Download all artifacts (including android)
  -> Create GitHub Release with android artifact attached
```

### Android User Interaction

```
App launch
  -> SingleInstance._ready() checks lock file
     (kill -0 may fail on Android -- needs platform guard)
  -> Config._ready() loads user://profiles/<slug>/config.cfg
     (user:// maps to Android internal app storage)
  -> Client._ready() checks Config.has_servers()
     -> No servers: show welcome screen
     -> Has servers: connect_server() for each, enter LIVE mode

User taps hamburger button (COMPACT mode)
  -> main_window._on_hamburger_pressed()
  -> AppState.toggle_sidebar_drawer()
  -> AppState.sidebar_drawer_toggled signal
  -> MainWindowDrawer.open_drawer()
     -> sidebar slides in from left (tween, 0.2s ease-out)
     -> drawer_backdrop fades to alpha 1.0

User swipes from left edge (COMPACT mode)
  -> main_window._input(event)
  -> DrawerGestures.handle_input(event)
  -> InputEventScreenTouch: start tracking if x <= 20px (EDGE_SWIPE_ZONE)
  -> InputEventScreenDrag: progress sidebar position proportionally
  -> Release: velocity-based snap decision
     -> |velocity| > 400px/s: snap in direction of velocity
     -> else: snap open if progress >= 50%

User long-presses a message (0.5s)
  -> LongPressDetector._on_timer_timeout()
  -> cozy_message/collapsed_message.context_menu_requested signal
  -> message_view_actions.on_context_menu_requested()
  -> PopupMenu shown at touch position
     items: Reply, Edit, Delete, Add Reaction, Remove All Reactions, Start Thread
     (Edit/Delete only enabled for own messages)

User taps backdrop to close drawer
  -> main_window._on_backdrop_input(InputEventScreenTouch)
  -> AppState.close_sidebar_drawer()
  -> MainWindowDrawer.close_drawer()
     -> sidebar slides out (tween, 0.2s ease-in)
     -> drawer_backdrop fades to alpha 0.0

User selects a channel (COMPACT mode)
  -> sidebar._on_channel_selected()
  -> AppState.close_sidebar_drawer()  (auto-close drawer)
  -> AppState.select_channel()
  -> message_view loads messages

Viewport resize (rotation / split-screen)
  -> main_window._on_viewport_resized()
  -> AppState.update_layout_mode(viewport_width)
     -> < 500px: COMPACT (drawer mode, hamburger button)
     -> < 768px: MEDIUM (inline sidebar, channel panel toggles)
     -> >= 768px: FULL (inline sidebar + member list)

Thread opened (COMPACT mode)
  -> AppState.open_thread()
  -> main_window._on_thread_opened()
  -> message_view.visible = false  (thread replaces message view)
  -> Thread closed: message_view.visible = true
```

## Key Files

| File | Role |
|------|------|
| `.github/workflows/release.yml` | Release CI pipeline. Has linux, linux-arm64, windows, macos, android matrix entries (lines 31-54). Android entry sets up Java JDK 17 (lines 77-82), Android SDK/NDK (lines 84-95), decodes keystore from secrets (lines 97-103) with debug fallback (lines 105-118), configures Godot editor settings (lines 331-343), and injects keystore into export preset (lines 345-356). LiveKit safety removal at lines 171-192 includes android case (line 185). |
| `export_presets.cfg` | Godot export presets. Has 5 presets: Linux (preset.0), Windows (preset.1), macOS (preset.2), Linux ARM64 (preset.3), Android (preset.4, line 159). Android preset targets arm64 (line 222), ETC2/ASTC textures (line 227), package name `com.daccord_projects.daccord` (line 228), with internet/microphone/camera permissions (lines 246-248). Min/target SDK left empty (Godot defaults, lines 220-221). |
| `project.godot` | Project config. Sets `renderer/rendering_method="gl_compatibility"` (line 65), mobile variant (line 66), `textures/vram_compression/import_etc2_astc=true` (line 67), minimum window size 320x480 (lines 48-49), `run/low_processor_mode=true` (line 21), `window/handheld/orientation=6` (line 47). |
| `scripts/autoload/app_state.gd` | Tracks `LayoutMode` enum (line 177): `COMPACT` <500px, `MEDIUM` <768px, `FULL` >=768px. Breakpoints at lines 179-180. `update_layout_mode()` at line 250. Signals: `layout_mode_changed`, `sidebar_drawer_toggled`. |
| `scripts/autoload/updater.gd` | Auto-update system. `_parse_release()` (line 147) uses `OS.get_name().to_lower()` (line 168) for platform asset matching -- no `"android"` branch (lines 178-199, falls through to else at line 197). `apply_update_and_restart()` (line 450) replaces binary on disk -- impossible on Android. |
| `scripts/autoload/single_instance.gd` | Lock-file based single-instance guard. `_is_process_alive()` (line 31) uses `kill -0` on non-Windows (line 38) -- may fail on Android's restricted process model. |
| `scripts/long_press_detector.gd` | Touch long-press detector: 0.5s duration (line 4), 10px drag cancel threshold (line 5). Handles `InputEventScreenTouch` (line 24) and `InputEventScreenDrag` (line 31). Used by both message types for context menus. |
| `scenes/main/drawer_gestures.gd` | Edge-swipe gesture handler. 20px edge zone (line 3), 80px swipe threshold (line 4), 400px/s velocity threshold (line 6), 50% snap progress (line 7). Touch open handlers (lines 39-62), touch close handlers (lines 178-200). Mouse mirrors for desktop testing (lines 65-89, 203-225). Reduced motion support (lines 138, 155, 262). |
| `scenes/main/main_window.gd` | Root window. Creates `DrawerGestures` (line 73), routes touch input in COMPACT mode (lines 221-224), handles backdrop touch dismiss (lines 524-530), manages layout mode transitions (lines 369-385). UI scale: `_apply_ui_scale` (line 187), `_auto_ui_scale` (line 207). |
| `scenes/main/main_window_drawer.gd` | Drawer animation logic. Base width 308px (line 6), minimum backdrop tap target 60px (line 7), `get_drawer_width()` clamps to viewport minus 60px (line 46). Tween open/close with 0.2s cubic easing (lines 82-88, 98-105). |
| `scenes/messages/cozy_message.gd` | Full message layout. Creates `LongPressDetector` for touch context menu (line 35). Right-click for mouse context menu (line 169). Avatar/author click opens profile card (lines 173-182). |
| `scenes/messages/collapsed_message.gd` | Compact follow-up message. Creates `LongPressDetector` for touch context menu (line 27). Always shows timestamps in COMPACT mode (line 82) since hover is unavailable on touch. |
| `scenes/messages/message_view_hover.gd` | Action bar hover state machine. Suppresses hover action bar in COMPACT mode (line 33) -- touch devices use long-press context menu instead. |
| `scenes/messages/message_view_actions.gd` | Shared context menu with Reply/Edit/Delete/Add Reaction/Remove All Reactions/Start Thread items (lines 23-28). Used by both mouse right-click and touch long-press. |
| `scenes/messages/composer/composer.gd` | Message input. Enter sends, Shift+Enter newlines (lines 85-90). `FileDialog` for attachments (lines 156-157) -- uses `ACCESS_FILESYSTEM` with `use_native_dialog`. Max file size 25 MB (line 4). Emoji picker position clamping (lines 267-268). |
| `scenes/messages/image_lightbox.gd` | Image viewer overlay. Closes on mouse click (line 25) but not on `InputEventScreenTouch` -- touch dismiss is missing. Escape key closes (line 29). |
| `scenes/sidebar/sidebar.gd` | Orchestrates guild bar + channel panel. Auto-closes drawer on channel selection in COMPACT mode (line 95). DM selection also auto-closes (line 104). In MEDIUM mode, channel panel auto-hides after selection (lines 91-93) and auto-shows on space selection (lines 74-76). |
| `addons/godot-livekit/godot-livekit.gdextension` | LiveKit GDExtension. Has linux.x86_64, windows.x86_64, macos.arm64, macos.x86_64, and android.arm64 entries (lines 6-10). Android library and dependencies declared (lines 10, 17). |
| `scripts/autoload/config.gd` | Multi-profile config. `user://` paths resolve to Android's internal app storage directory. No Android-specific changes needed for file paths. |

## Implementation Details

### Android-Ready Foundations

**Renderer:** The project uses `gl_compatibility` for both desktop and mobile (project.godot lines 65-66). This is the correct renderer for Android -- Vulkan Mobile is an alternative but GL Compatibility has broader device support.

**Texture compression:** `import_etc2_astc=true` is already set (project.godot line 67). The Android preset sets `texture_format/etc2_astc=true` and `texture_format/s3tc_bptc=false` (export_presets.cfg lines 226-227).

**Low processor mode:** `run/low_processor_mode=true` (project.godot line 21) reduces CPU/GPU usage when the app is idle. This is important for battery life on Android devices.

**Handheld orientation:** `window/handheld/orientation=6` (project.godot line 47) sets the orientation mode for handheld devices (full sensor auto-rotate).

**Sentry SDK:** The Sentry Godot SDK (installed by CI from getsentry/sentry-godot) ships Android arm64/arm32/x86_64 `.so` binaries plus Android plugin AARs (`sentry_android_godot_plugin.debug.aar` and `.release.aar`). Error reporting should work out of the box on Android.

### CI Pipeline

The release workflow (`.github/workflows/release.yml`) includes a full Android build pipeline:

**Matrix entry** (lines 51-54): platform `android`, preset `Android`, artifact `daccord-android-arm64`, extension `apk`, runs on `ubuntu-latest`.

**Java setup** (lines 77-82): Uses `actions/setup-java@v4` with Temurin JDK 17.

**Android SDK** (lines 84-95): Uses `android-actions/setup-android@v3` with cmdline-tools 11076708. Installs `platform-tools`, `build-tools;34.0.0`, `platforms;android-34`, `ndk;23.2.8568313`. Sets `ANDROID_SDK_ROOT` and `ANDROID_NDK_ROOT` environment variables.

**Keystore handling** (lines 97-118): Decodes `ANDROID_KEYSTORE_BASE64` from GitHub secrets to `$RUNNER_TEMP/release.keystore`. If the secret is not available, generates a debug keystore as a fallback (lines 105-118) with default credentials.

**Godot configuration** (lines 331-343): Creates `$HOME/.config/godot/editor_settings-4.tres` with Android SDK and Java paths so Godot can find the toolchain.

**Keystore injection** (lines 345-356): Updates `export_presets.cfg` with the keystore path, user, and password. Falls back to debug values if release secrets are unavailable.

**Packaging** (lines 451-454): Copies `dist/build/android/daccord.apk` to `daccord-android-arm64.apk` for artifact upload.

**LiveKit safety removal** (lines 171-192): The case statement (lines 180-186) maps each platform to its expected LiveKit binary. For Android (line 185), it checks for `addons/godot-livekit/bin/libgodot-livekit.android.arm64.so`. If the binary is not found, lines 187-189 remove the `.gdextension` file to prevent crashes.

### Touch Interaction Model

The app has three layers of touch infrastructure that are already implemented and work on Android:

**Long-press context menus (`LongPressDetector`):** Both `cozy_message.gd` (line 35) and `collapsed_message.gd` (line 27) create a `LongPressDetector` instance that listens for `InputEventScreenTouch` events. A 0.5-second press triggers the shared context menu via the `context_menu_requested` signal. Dragging more than 10 pixels cancels the long-press (long_press_detector.gd line 31). The context menu offers Reply, Edit, Delete, Add Reaction, Remove All Reactions, and Start Thread -- the same actions as the desktop right-click and hover action bar.

**Hover action bar suppression:** The hover-based message action bar (message_view_hover.gd) is suppressed in COMPACT mode (line 33: `if AppState.current_layout_mode == AppState.LayoutMode.COMPACT: return`). This avoids showing a floating bar that requires mouse hover, which has no equivalent on touch screens. All message actions are instead accessible via long-press.

**Sidebar drawer gestures (`DrawerGestures`):** Edge-swipe open and backdrop-swipe close (drawer_gestures.gd):
- **Open:** Touch starts within 20px of the left edge (line 39). Drag past the 10px dead zone to begin tracking the sidebar position proportionally. On release, velocity-based snap: if |velocity| > 400px/s, snap in the direction of motion; otherwise snap open if progress >= 50% (line 7).
- **Close:** Touch starts on the backdrop area (x > drawer width, line 178). Drag left to track close progress. Velocity-based snap on release. Alternatively, a simple tap on the backdrop closes the drawer.
- Both open and close gestures respect `Config.get_reduced_motion()` and skip animations when enabled (lines 138, 155, 262).
- Mouse events mirror touch events for desktop testing (lines 65-89, 203-225).

**Backdrop touch dismiss:** `main_window._on_backdrop_input()` (line 524) handles `InputEventScreenTouch` to close the sidebar drawer. This guards against the close gesture tracker to avoid double-handling.

**Drawer width calculation:** `MainWindowDrawer.get_drawer_width()` (main_window_drawer.gd line 46) caps the drawer at `min(308px, viewport_width - 60px)`, ensuring at least a 60px tap target on the backdrop even on narrow screens.

### Responsive Layout on Android

**Layout mode breakpoints:** `AppState.update_layout_mode()` (app_state.gd line 250) sets the layout mode based on viewport width:
- `COMPACT` (<500px): Most Android phones in portrait mode. Sidebar becomes a drawer overlay, hamburger button visible, member list and search panel hidden, thread panel replaces message view.
- `MEDIUM` (500-768px): Large phones in landscape, small tablets. Sidebar is inline but channel panel auto-hides after channel selection (sidebar.gd lines 91-93) and auto-shows on space selection (lines 74-76).
- `FULL` (>=768px): Tablets in landscape. Full sidebar, member list, and search panel visible.

**Compact mode behavior** (main_window.gd lines 369-385):
- Sidebar moves to drawer container (`_drawer.move_sidebar_to_drawer()`)
- Channel panel always visible within the drawer (`sidebar.set_channel_panel_visible_immediate(true)`)
- Hamburger button visible, sidebar toggle hidden
- Member list toggle hidden, member list hidden
- Search toggle hidden, search panel hidden, search closed
- Thread panel replaces the message view

**Collapsed message timestamps:** In COMPACT mode, collapsed messages always show their timestamp (collapsed_message.gd line 82) since the hover-to-reveal interaction is unavailable on touch. On desktop, timestamps only appear on mouse hover.

**Minimum window size:** project.godot sets `min_width=320` and `min_height=480` (lines 48-49), accommodating small phone screens.

**UI scale:** `main_window._apply_ui_scale()` (line 187) reads `Config.get_ui_scale()`. If set to auto (<=0), `_auto_ui_scale()` (line 207) reads `DisplayServer.screen_get_scale()` and clamps to 1.0-2.0x. On Android, this adapts to high-DPI screens. The window's `content_scale_factor` is adjusted accordingly.

### Message Interaction on Android

**Sending messages:** The composer (composer.gd) uses a `TextEdit` for input. Enter sends the message (line 85), Shift+Enter inserts a newline (line 88). On Android, the virtual keyboard's Enter key maps to the same input event. The send button (44x44px touch target, composer.tscn) provides a tap alternative.

**File attachments:** The upload button opens a `FileDialog` with `ACCESS_FILESYSTEM` (composer.gd lines 156-157). On Android, Godot maps this to the system file picker via Storage Access Framework. The `use_native_dialog` flag ensures the native Android file picker is used. Files are limited to 25 MB (line 4).

**Emoji picker:** The emoji button (44x44px, composer.tscn) opens the emoji picker popup above the composer. Position is clamped to viewport bounds (composer.gd lines 267-268), which handles varying Android screen sizes.

**Reply bar:** After initiating a reply via long-press context menu, a reply bar appears above the composer with the author name and a cancel button. The text input auto-focuses for typing.

### Image Lightbox on Android

The image lightbox (image_lightbox.gd) opens as a full-screen overlay with the image centered. It closes on Escape key (line 29) or backdrop mouse click (line 25). However, the backdrop handler only checks `InputEventMouseButton` -- it does not handle `InputEventScreenTouch`, so tapping the backdrop on a touchscreen does not close the lightbox. The close button is the only way to dismiss it on Android.

### Voice & Video on Android

The `godot-livekit.gdextension` (lines 6-10) now includes an `android.arm64` entry (line 10) and a corresponding dependency entry (line 17). This means the LiveKit binary is declared for Android, and voice/video features will be available if the compiled `.so` is present at build time. The release workflow's safety removal step (lines 171-192) checks for `libgodot-livekit.android.arm64.so` (line 185) and removes the extension if the binary is missing, falling back to graceful degradation via `LiveKitAdapter` null guards.

The screen sharing button uses `ScreenPickerDialog` which relies on desktop screen enumeration APIs unavailable on Android.

### Android-Specific UX Considerations

**Mobile resolution and UI scaling:** On Android devices, the UI renders too small and the responsive layout breakpoints are not reached at typical mobile resolutions. The COMPACT mode breakpoint (<500px) and MEDIUM mode breakpoint (<768px) are measured in Godot viewport pixels, but Android phones report high logical resolutions (e.g. 1080x2400 or higher) even on small screens. This means a phone with a 6-inch display may report a viewport width well above 768px, causing the app to use FULL layout mode instead of COMPACT. As a result, menus do not collapse into hamburger button drawers, the sidebar remains inline, and the overall UI elements appear too small for comfortable touch interaction. The auto UI scale (`_auto_ui_scale()` in main_window.gd line 207) reads `DisplayServer.screen_get_scale()` and adjusts `content_scale_factor`, but this does not change the viewport dimensions that the layout breakpoints check against. The breakpoints need to account for screen density or the content scale factor so that a phone-sized screen triggers COMPACT mode regardless of its pixel resolution.

**Back button:** Android's system back button emits `ui_cancel` in Godot. Many dialogs already handle `ui_cancel` via `_input()` -- 25 dialog files use `event.is_action_pressed("ui_cancel")` to close on Escape (which maps to Android back). However, there is no global handler to close the sidebar drawer, dismiss the image lightbox, navigate back from thread view to message view, or handle a back-button stack for multi-level navigation. Each dialog handles `ui_cancel` independently rather than through a centralized navigation stack.

**On-screen keyboard:** Text input fields (`TextEdit`, `LineEdit`) in the composer and search bar will trigger the Android virtual keyboard. The viewport may need to resize or scroll to keep the input field visible above the keyboard. Godot has built-in virtual keyboard handling, but the composer is at the bottom of the screen, which is the most vulnerable position for keyboard occlusion.

**Notifications:** Android push notifications are not implemented. The client only receives messages while connected to the gateway WebSocket. Background notification delivery would require Firebase Cloud Messaging (FCM) integration on both client and server.

**App lifecycle:** Android may kill background apps. The WebSocket gateway connection will drop when the app is backgrounded. The existing reconnection logic (documented in [Server Disconnects & Timeouts](server_disconnects_timeouts.md)) should handle this, but reconnect timing may need tuning for mobile network conditions.

**Touch targets:** Header buttons (hamburger, sidebar toggle, search toggle, member toggle) use `custom_minimum_size = Vector2(44, 44)` (main_window.tscn), meeting the WCAG 44x44px minimum. Composer buttons (upload, emoji, send) also use 44x44px (composer.tscn). Guild bar space icons, channel items, and DM items may need verification for adequate touch targets.

**FileDialog on Android:** The composer (composer.gd lines 156-157) and multiple admin dialogs use `FileDialog` with `ACCESS_FILESYSTEM`. On Android, Godot uses the Storage Access Framework for file picking, which limits access to user-selected files. The `use_native_dialog` flag ensures the native Android picker is used. Profile export/import and avatar upload also use `FileDialog` -- these should work but may behave differently than desktop.

**Image lightbox touch dismiss:** The image lightbox (image_lightbox.gd line 25) only handles `InputEventMouseButton` for backdrop dismiss. It does not check `InputEventScreenTouch`, so the lightbox cannot be dismissed by tapping the backdrop on Android -- only the close button works.

**Clipboard paste:** The composer supports pasting images and large text from clipboard. On Android, clipboard access works differently -- `DisplayServer.clipboard_get()` returns text but image paste from clipboard requires Android-specific clipboard content provider access, which may not be supported by Godot's clipboard API.

### Distribution

**GitHub Releases (sideload):** The `.apk` artifact is attached to GitHub Releases alongside desktop artifacts. Users enable "Install unknown apps" and install directly. The updater would need to open the release page or trigger an APK install intent for updates.

**Google Play Store:** Requires a Google Play Developer account ($25 one-time fee), app listing metadata (screenshots, description, privacy policy), and an AAB (Android App Bundle) instead of APK. The CI pipeline would need to upload to Play Store via Fastlane or similar.

**F-Droid:** Open-source alternative app store. Requires reproducible builds and no proprietary dependencies. The Sentry SDK may need to be optional for F-Droid compliance.

## Implementation Status

### Build & Release
- [x] GL Compatibility renderer configured for mobile (project.godot lines 65-66)
- [x] ETC2/ASTC texture compression enabled (project.godot line 67)
- [x] Minimum window size 320x480 suitable for phones (project.godot lines 48-49)
- [x] Low processor mode for battery efficiency (project.godot line 21)
- [x] Handheld orientation set to full sensor auto-rotate (project.godot line 47)
- [x] Sentry SDK ships Android binaries (installed by CI)
- [x] LiveKit GDExtension declares android.arm64 entry (godot-livekit.gdextension lines 10, 17)
- [x] LiveKit gracefully disabled when platform binary missing (release.yml lines 171-192)
- [x] Android export preset in `export_presets.cfg` (preset.4, line 159)
- [x] Android matrix entry in `release.yml` (lines 51-54)
- [x] Java JDK 17 + Android SDK/NDK setup in CI (lines 77-95)
- [x] Keystore management with debug fallback (lines 97-118)
- [x] Godot editor settings configured for Android SDK path (lines 331-343)
- [x] Keystore injection into export preset (lines 345-356)
- [x] Android manifest permissions: internet, microphone, camera (export_presets.cfg lines 246-248)
- [ ] Explicit min/target SDK versions (export_presets.cfg lines 220-221 are empty, using Godot defaults)
- [ ] Adaptive icon for Android (foreground/background layers)
- [ ] Google Play Store listing and AAB upload

### Touch & Gesture UX
- [x] Touch long-press for context menus (long_press_detector.gd, cozy_message.gd line 35, collapsed_message.gd line 27)
- [x] Edge-swipe drawer open/close gestures (drawer_gestures.gd lines 39-62, 178-200)
- [x] Backdrop touch dismiss for sidebar drawer (main_window.gd lines 524-530)
- [x] Velocity-based snap decision for drawer gestures (drawer_gestures.gd line 7)
- [x] Reduced motion support in drawer gestures (drawer_gestures.gd lines 138, 155, 262)
- [x] Drawer width capped to leave 60px backdrop tap target (main_window_drawer.gd line 46)
- [x] Hover action bar suppressed in COMPACT mode (message_view_hover.gd line 33)
- [x] 44x44px touch targets on header buttons (main_window.tscn) and composer buttons (composer.tscn)
- [ ] Image lightbox missing `InputEventScreenTouch` backdrop dismiss (image_lightbox.gd line 25)

### Responsive Layout
- [x] Compact layout mode for narrow viewports (app_state.gd lines 177-180)
- [x] Sidebar drawer mode in COMPACT (main_window.gd lines 369-385)
- [x] Channel panel auto-hide/show in MEDIUM mode (sidebar.gd lines 74-76, 91-93)
- [x] Thread panel replaces message view in COMPACT (main_window.gd)
- [x] Collapsed message timestamps always shown in COMPACT (collapsed_message.gd line 82)
- [x] Member list and search panel hidden in COMPACT (main_window.gd)
- [x] Auto UI scale for high-DPI Android screens (main_window.gd lines 187-219)
- [ ] Layout breakpoints not density-aware -- phones stay in FULL mode with tiny UI (ANDROID-15)

### Navigation & Platform
- [x] All dialogs handle `ui_cancel` for Escape/back button dismiss (25 dialog files)
- [ ] No global back button handler for drawer/lightbox/thread navigation
- [ ] Updater `_parse_release()` Android asset matching (updater.gd line 168)
- [ ] Updater Android update mechanism (Play Store redirect or APK install intent)
- [ ] Single-instance guard Android platform check (single_instance.gd line 38)
- [ ] On-screen keyboard viewport handling for composer
- [ ] Push notifications via FCM

## Tasks

### ANDROID-1: No Android export preset
- **Status:** done
- **Impact:** 4
- **Effort:** 3
- **Tags:** ci, mobile, permissions
- **Notes:** Android preset exists as preset.4 in `export_presets.cfg` (line 159) with arm64 architecture, ETC2/ASTC textures, internet/microphone/camera permissions.

### ANDROID-2: No Android CI pipeline entry
- **Status:** done
- **Impact:** 4
- **Effort:** 2
- **Tags:** ci, mobile
- **Notes:** `release.yml` matrix (lines 51-54) includes android entry. Full pipeline with Java JDK 17, Android SDK/NDK, keystore management, and packaging.

### ANDROID-3: Updater ignores Android
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** api, ci, mobile
- **Notes:** `_parse_release()` (updater.gd line 147) has no `"android"` branch in asset matching (lines 178-199, falls through to else at line 197). `apply_update_and_restart()` (line 450) replaces the binary on disk, which is impossible on Android. Needs Play Store redirect or APK install intent.

### ANDROID-4: Single-instance guard may break
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** api, mobile
- **Notes:** `single_instance.gd` `_is_process_alive()` (line 31) uses `kill -0` (line 38) to check PIDs, which may fail on Android's restricted process model. Should skip or use manifest `singleTask` launch mode.

### ANDROID-5: No Android back button handling
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** mobile, ui
- **Notes:** Android back button emits `ui_cancel`. Individual dialogs (25 files) handle it for closing, but no global handler maps it to close the sidebar drawer, dismiss the image lightbox, navigate back from thread view, or implement a back stack.

### ANDROID-6: LiveKit Android binary availability
- **Status:** partial
- **Impact:** 3
- **Effort:** 2
- **Tags:** ci, mobile, video, voice
- **Notes:** `godot-livekit.gdextension` now declares `android.arm64` entries (lines 10, 17). The release workflow checks for the binary (line 185) and removes the extension if missing. Voice/video will work once the compiled `libgodot-livekit.android.arm64.so` is included in the godot-livekit release zip. Currently the binary may not be present in the release download.

### ANDROID-7: No keystore setup
- **Status:** done
- **Impact:** 3
- **Effort:** 3
- **Tags:** ci, mobile
- **Notes:** Release workflow decodes `ANDROID_KEYSTORE_BASE64` from secrets (lines 97-103) with debug keystore fallback (lines 105-118). Keystore injected into export preset (lines 345-356).

### ANDROID-8: No push notifications
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** gateway
- **Notes:** Messages only arrive while the gateway WebSocket is connected. Background delivery requires FCM on both client and server.

### ANDROID-9: No adaptive icon
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** mobile, ui
- **Notes:** Android requires adaptive icons (foreground + background layers). Current icons in `dist/icons/` are standard PNGs. Need `res/mipmap-*` directories or Godot's icon override.

### ANDROID-10: No Play Store distribution
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** ci
- **Notes:** Sideload via APK is sufficient initially. Play Store requires developer account, AAB format, and listing metadata.

### ANDROID-11: No F-Droid compliance
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** ci
- **Notes:** F-Droid requires reproducible builds and no proprietary SDKs. Sentry may need to be optional.

### ANDROID-12: On-screen keyboard viewport handling
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** a11y
- **Notes:** Virtual keyboard may obscure the composer `TextEdit`. May need viewport resize or scroll-into-view logic. The composer sits at the bottom of the screen, the most vulnerable position for occlusion.

### ANDROID-13: Image lightbox missing touch dismiss
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** mobile, ui
- **Notes:** `image_lightbox.gd` `_on_backdrop_input()` (line 24) only checks `InputEventMouseButton`. Needs an `InputEventScreenTouch` check so tapping the backdrop closes the lightbox on touch devices. One-line fix.

### ANDROID-15: Mobile resolution does not trigger responsive breakpoints
- **Status:** open
- **Impact:** 4
- **Effort:** 2
- **Tags:** mobile, ui
- **Notes:** Android phones report high logical viewport widths (e.g. 1080px+) despite having small physical screens. The layout breakpoints in `AppState.update_layout_mode()` (app_state.gd line 250) compare raw viewport pixels, so COMPACT (<500px) and MEDIUM (<768px) modes are never reached on most phones. The UI stays in FULL mode with tiny elements and no drawer navigation. The breakpoints should incorporate screen density or the content scale factor so that a 6-inch phone screen triggers COMPACT mode. Alternatively, `_auto_ui_scale()` could adjust the viewport size (via `content_scale_size` or `window/size/viewport_width`) rather than just `content_scale_factor`, so the effective viewport width shrinks to match the physical screen class.

### ANDROID-14: Empty min/target SDK versions
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** ci, mobile
- **Notes:** `export_presets.cfg` lines 220-221 leave min SDK and target SDK empty, relying on Godot defaults. Should explicitly set min SDK 24 (Android 7.0, Godot 4.5 minimum) and target SDK 34 (current Play Store requirement).
