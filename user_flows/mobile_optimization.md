# Mobile Optimization

Priority: 30
Depends on: None
Status: Complete

Mobile performance optimizations for Android: gl_compatibility renderer, ETC2/ASTC textures, ARM64-only, 60fps cap, DPI-aware scaling, edge-to-edge display with safe-area insets, disabled hover tracking on touch devices, memory budget monitoring, immersive mode, and touch gesture navigation. All `_process()` loops are guarded or disabled on mobile.

## Key Files

| File | Role |
|------|------|
| `scenes/main/main_window.gd` | FPS cap, safe-area insets, memory watchdog, DPI scaling |
| `scenes/main/drawer_gestures.gd` | Touch edge-swipe gesture system with DPI-aware edge zones |
| `scenes/messages/message_view.gd` | `_is_mobile` flag disables hover `_process()` on mobile |
| `scenes/messages/message_view_hover.gd` | Action bar hover state machine (skipped on mobile) |
| `project.godot` | Renderer, low processor mode, physics ticks, texture compression |
| `export_presets.cfg` | Android preset: ARM64, immersive mode, edge-to-edge |
| `scenes/members/member_list.gd` | Virtual scroll with self-disabling `_process()` |
| `scripts/autoload/sound_manager.gd` | Short WAV SFX via preload constants |
| `assets/theme/*.gdshader` | Lightweight canvas_item SDF shaders |
