# Mobile Optimization

## Overview
Review of mobile performance optimizations for Daccord's Android build, benchmarked against common Godot mobile best practices. Daccord is a 2D chat client using the Compatibility renderer — most 3D-specific advice (LOD, lightmaps, MultiMesh) does not apply. This document catalogues what is already in good shape and what remains actionable.

## User Steps
1. User launches Daccord on an Android device
2. App renders UI at the correct DPI scale, with responsive layout (COMPACT/MEDIUM/FULL)
3. User interacts via touch gestures (edge-swipe drawer, tap, scroll)
4. App maintains smooth frame rate and reasonable battery/thermal profile
5. Scene transitions (space/channel switching) load without visible hitches

## Signal Flow
```
viewport size_changed ─→ _on_viewport_resized() ─→ AppState.update_layout_mode()
                                                   ├─→ layout_mode_changed signal
                                                   └─→ listeners reconfigure UI

touch event ─→ _input() ─→ DrawerGestures.handle_input()
                           ├─→ _handle_open_swipe()  ─→ toggle_sidebar_drawer()
                           └─→ _handle_close_swipe() ─→ close_sidebar_drawer()
```

## Key Files
| File | Role |
|------|------|
| `project.godot` | Renderer, physics ticks, VRAM compression, viewport settings |
| `export_presets.cfg:421` | Android export preset (preset.4): architecture, permissions, screen |
| `scripts/autoload/app_state.gd:319` | `update_layout_mode()` — responsive breakpoint logic |
| `scenes/main/main_window.gd:215` | `_auto_ui_scale()` — DPI-based scaling on mobile |
| `scenes/main/main_window.gd:324` | `_on_viewport_resized()` — calls `update_layout_mode` on every resize |
| `scenes/main/drawer_gestures.gd` | Touch edge-swipe gesture system |
| `scenes/messages/message_view.gd:161` | `_process()` — hover tracker, runs every frame |
| `scenes/messages/typing_indicator.gd:29` | `_process()` — dot animation, runs every frame when visible |
| `scenes/sidebar/channels/channel_skeleton.gd:34` | `_process()` — shimmer animation, every frame |
| `scenes/messages/loading_skeleton.gd:58` | `_process()` — shimmer animation, every frame |
| `scenes/video/video_tile.gd:91` | `_process()` — video texture polling, every frame |
| `scenes/members/member_list.gd:89` | `_process()` — virtual scroll, self-disabling |
| `scripts/autoload/client.gd:286` | `_process()` — test API / MCP poll |
| `scripts/autoload/updater.gd:253` | `_process()` — download progress, guarded |
| `scripts/voice/livekit_adapter.gd:312` | `_process()` — screen capture frame pump |
| `scripts/voice/web_voice_session.gd:191` | `_process()` — connection state poll (web only) |
| `scripts/autoload/sound_manager.gd` | SFX playback — all WAV preloads |
| `assets/theme/avatar_circle.gdshader` | Lightweight canvas_item SDF shader |
| `assets/theme/skeleton_shimmer.gdshader` | Loading placeholder shimmer |
| `assets/theme/status_circle.gdshader` | Status indicator shader |
| `assets/theme/welcome_bg.gdshader` | Welcome screen background |

## Implementation Details

### Already Optimised
These settings already follow mobile best practices:

- **Renderer**: `gl_compatibility` for both desktop and mobile (`project.godot` lines 76-77) — correct choice for a 2D chat app; avoids Vulkan overhead on tile-based mobile GPUs.
- **Texture compression**: `import_etc2_astc=true` (`project.godot` line 78) — hardware-native VRAM compression for Android.
- **Architecture**: ARM64-only (`export_presets.cfg` line 454, `armeabi-v7a=false`) — drops legacy 32-bit, reducing APK size.
- **Low processor mode**: Enabled (`project.godot` line 21) — reduces idle CPU/GPU usage by only rendering on input events and signals.
- **Physics ticks**: Set to 1/sec (`project.godot` line 72) — minimal overhead since Daccord has no physics simulation.
- **DPI scaling**: Mobile-specific path in `_auto_ui_scale()` (line 226) uses `screen_get_dpi()` with 160 DPI baseline, clamped 1x–3x.
- **Shaders**: All 4 shaders are lightweight `canvas_item` SDF shaders — no `discard`, no dynamic branching, no `highp` abuse, anti-aliased with `fwidth()`.
- **Node caching**: `DrawerGestures` caches the main window reference in `_init()` (line 24). All `@onready` vars in `main_window.gd` cache node refs at scene ready.
- **Virtual scrolling**: `member_list.gd` uses object pooling with self-disabling `_process()` (line 90: `set_process(false)` immediately) — only runs when scroll changes.
- **SFX format**: All 9 sound effects are short WAV files (uncompressed, low-latency) loaded via `preload()` constants — correct for short SFX per mobile audio best practices.
- **Reduced motion**: Config preference disables drawer/transition tweens, saving GPU fill and CPU tween overhead.

### `_process()` Audit
Files with active per-frame loops on mobile:

| File | Guard | Mobile concern |
|------|-------|----------------|
| `message_view.gd:161` | None (always runs) | Hover tracker runs every frame even on touch devices where hover is irrelevant |
| `typing_indicator.gd:29` | Only when `visible` | Low concern — 3 dots, simple sin() |
| `channel_skeleton.gd:34` | While skeleton shown | Low concern — temporary loading state |
| `loading_skeleton.gd:58` | While skeleton shown | Low concern — temporary loading state |
| `video_tile.gd:91` | `_stream == null` guard | Only runs during active video — acceptable |
| `client.gd:286` | `test_api`/`mcp` null guards | Only runs if developer mode active — no mobile impact |
| `updater.gd:253` | `_downloading` guard | Only during active download — acceptable |
| `livekit_adapter.gd:312` | `_screen_capture` guard | Only during screen share — acceptable |
| `scripted_runtime.gd:165` | `_running` and `_canvas` guard | Only during plugin activity — acceptable |

### Missing Optimisations

#### 1. FPS Cap on Mobile
`Engine.max_fps` is never set anywhere in the codebase. On 120Hz+ phones, Godot will render at the display refresh rate even though `low_processor_mode` is enabled (it still re-renders on every signal/input). A chat app should cap at 60 fps (or 30 when idle).

**Where**: `main_window.gd:_ready()` or a new mobile init path.

#### 2. Hover Tracker in `_process()` on Touch Devices
`message_view.gd:161` runs `_hover.process()` every frame. On mobile, hover is not meaningful — this wastes CPU scanning message positions for mouse-over state that will never trigger via touch.

**Where**: Guard with `if not OS.has_feature("mobile"):` or disable `set_process(false)` on mobile.

#### 3. Layout Recalculation Debouncing
`_on_viewport_resized()` (`main_window.gd:324`) calls `update_layout_mode()` on every `size_changed` signal. During continuous resize (e.g., split-screen or orientation change animations), this fires many times per second. The function itself is cheap (two comparisons), but downstream listeners rebuilding UI on `layout_mode_changed` are not.

**Where**: Already partially mitigated — `update_layout_mode()` (line 332) only emits when the mode actually changes. Low priority.

#### 4. Threaded Resource Loading for Scene Transitions
`ResourceLoader.load_threaded_request()` is not used anywhere. Channel/space switches load scenes synchronously, which can cause frame drops on low-end Android devices.

**Where**: Scene instantiation paths in `main_window.gd` and message view.

#### 5. Android Immersive Mode
`screen/immersive_mode=false` in the export preset (`export_presets.cfg` line 476). Enabling it would use the full screen on devices with gesture navigation bars.

#### 6. Edge-to-Edge Display
`screen/edge_to_edge=false` (`export_presets.cfg` line 477). Modern Android apps should handle display cutouts and edge-to-edge rendering, but this requires safe-area inset handling.

#### 7. Debug Symbol Stripping
No `strip_debug` or debug symbol configuration found in export presets. Release builds may include debug symbols, increasing APK size.

#### 8. Memory Budget Monitoring
No memory tracking or budget enforcement exists. The article recommends targeting < 300 MB RAM on mid-range Android. With emoji SVG assets (160+ files), message caches, and avatar textures, memory could grow unbounded on long sessions.

#### 9. `print()` Audit in Hot Paths
Not yet audited — stray `print()` or `push_warning()` calls in signal handlers or `_process()` loops can cause measurable frame drops on Android due to logcat overhead.

#### 10. Emoji SVG Atlas
160+ individual SVG emoji files under `assets/theme/emoji/` are loaded individually. Packing into a sprite atlas would reduce draw calls when many emoji are visible (e.g., emoji picker, message reactions).

## Implementation Status
- [x] Compatibility renderer (gl_compatibility)
- [x] ETC2/ASTC texture compression
- [x] ARM64-only architecture
- [x] Low processor mode
- [x] Physics ticks minimised (1/sec)
- [x] DPI-aware scaling on mobile
- [x] Lightweight canvas_item shaders (no discard, no highp abuse)
- [x] Node reference caching in `_ready()` / `@onready`
- [x] Virtual scrolling with object pooling (member list)
- [x] Short SFX as WAV, preloaded
- [x] Reduced motion preference
- [x] Touch gesture system (edge-swipe drawer)
- [ ] FPS cap on mobile (`Engine.max_fps`)
- [ ] Disable hover tracker on mobile
- [ ] Threaded resource loading for scene transitions
- [ ] Android immersive mode
- [ ] Edge-to-edge display with safe-area insets
- [ ] Debug symbol stripping in release exports
- [ ] Memory budget monitoring
- [ ] `print()` audit in hot paths
- [ ] Emoji SVG sprite atlas
- [ ] Thermal throttle test protocol
- [ ] Low-end device test matrix

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| No `Engine.max_fps` cap on mobile | High | 120Hz+ phones burn battery rendering a chat app at full rate. Set 60 in `main_window.gd:_ready()` when `OS.has_feature("mobile")`. Consider 30 fps when idle (no active typing/scrolling). |
| `message_view.gd` hover tracker runs on mobile | Medium | `_process()` at line 161 calls `_hover.process()` every frame. Pointless on touch devices — guard with platform check or `set_process(false)`. |
| No threaded resource loading | Medium | `ResourceLoader.load_threaded_request()` unused. Channel/space switches may hitch on low-end devices. Most impactful for initial load and space transitions. |
| Immersive mode disabled | Medium | `export_presets.cfg` line 476: `screen/immersive_mode=false`. Wastes screen real estate on gesture-nav devices. Requires no code changes — just toggle the preset. |
| Edge-to-edge disabled | Medium | `export_presets.cfg` line 477: `screen/edge_to_edge=false`. Modern Android standard, but requires safe-area margin handling in UI to avoid content behind cutouts. |
| No debug symbol stripping | Low | Export presets don't explicitly strip debug symbols. Check if custom templates already handle this. Affects APK size. |
| No memory budget or monitoring | Low | No tracking of RAM usage. Long sessions with many spaces/channels/messages could exceed 300 MB on mid-range devices. Add `OS.get_static_memory_usage()` logging or Sentry breadcrumbs. |
| Stray `print()` in hot paths | Low | Not yet audited. Each `print()` on Android goes through logcat, which has measurable overhead in tight loops. Run `grep -rn 'print(' scripts/ scenes/` and review hits in `_process()` methods and high-frequency signal handlers. |
| 160+ individual emoji SVGs | Low | Each emoji is a separate `.svg` file. When many are visible (emoji picker grid), each is a separate draw call. Packing into an atlas would improve batching. |
| No thermal throttle test protocol | Low | Article recommends a 30-minute sustained-use test on a mid-range device monitoring for thermal throttling. No test procedure exists. |
| No low-end device test matrix | Low | Testing only on personal phones misses real-world low-end performance. Define target devices (e.g., Samsung A series, Pixel 4a) and minimum acceptable frame times. |
