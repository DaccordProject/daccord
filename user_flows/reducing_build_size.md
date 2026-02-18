# Reducing Build Size

*Last touched: 2026-02-18 20:21*

## Overview

This flow documents how to reduce daccord's exported build size by compiling custom Godot export templates with unused features stripped out. The stock Godot export templates include the full engine (3D, VR, advanced text shaping, Vulkan, etc.), most of which daccord doesn't use. By building minimal custom templates and applying post-processing tools, the final binary size can be cut by 70-80%.

Reference: [How to Minify Godot's Build Size](https://popcar.bearblog.dev/how-to-minify-godots-build-size/) by Popcar.

None of this is implemented yet. daccord currently exports with stock Godot templates. This document serves as a build optimization specification.

## Current State

daccord exports to three platforms via the release CI pipeline (`.github/workflows/release.yml`):

| Platform | Preset | Output |
|----------|--------|--------|
| Linux | `Linux` | `daccord-linux-x86_64.tar.gz` |
| Windows | `Windows` | `daccord-windows-x86_64.zip` |
| macOS | `macOS` | `daccord-macos.zip` |

All three use stock Godot 4.6 export templates (`custom_template/release=""` in `export_presets.cfg`). The project uses the GL Compatibility renderer (`project.godot` line 20), meaning Vulkan is unused.

## User Steps

### 1. Set Up the Build Environment

1. Clone the Godot source for the version matching the project (4.6).
2. Install SCons and a C++ compiler (see [Godot docs: Compiling](https://docs.godotengine.org/en/stable/contributing/development/compiling/)).
3. Create a `custom.py` file in the Godot source root with the build flags below.

### 2. Create the Custom Build Profile (`custom.py`)

```python
# custom.py — daccord minimal export template build flags

# Size optimization
optimize = "size"          # -Os compiler flag (smaller binary)
lto = "full"               # Link-time optimization (slower build, smaller output)
deprecated = "no"          # Strip deprecated API wrappers

# Strip 3D engine (daccord is 2D-only)
disable_3d = "yes"

# Renderer — daccord uses GL Compatibility, not Vulkan
vulkan = "no"
use_volk = "no"

# Disable unused features
openxr = "no"              # No VR/AR support needed
minizip = "no"             # No ZIP archive support needed

# Text server — use fallback (no RTL/complex script support)
# NOTE: If daccord ever needs RTL language support, keep the advanced text server.
module_text_server_adv_enabled = "no"
module_text_server_fb_enabled = "yes"
```

### 3. Selective Module Compilation (Optional, Aggressive)

For maximum size reduction, disable all modules by default and enable only what daccord uses:

```python
# Append to custom.py for aggressive stripping
modules_enabled_by_default = "no"

# Modules daccord actually needs
module_gdscript_enabled = "yes"          # Scripting language
module_text_server_fb_enabled = "yes"    # Text rendering
module_freetype_enabled = "yes"          # Font rendering
module_svg_enabled = "yes"              # SVG icon support (theme/icons/)
module_webp_enabled = "yes"             # WebP image support
module_godot_physics_2d_enabled = "yes" # 2D physics (if used)
module_websocket_enabled = "yes"        # WebSocket gateway
module_mbedtls_enabled = "yes"          # TLS for HTTPS/WSS
module_regex_enabled = "yes"            # Regex (used in markdown parsing)
```

**Do NOT disable `disable_advanced_gui`** — daccord relies heavily on `RichTextLabel` (message rendering, markdown-to-BBCode), `TextEdit` (composer), and other advanced GUI nodes.

### 4. Generate a Build Profile File (Optional)

Use Godot's Engine Compilation Configuration Editor to strip unused node types:

1. Open the project in Godot Editor.
2. Go to `Project > Tools > Engine Compilation Configuration Editor`.
3. Uncheck node types daccord doesn't use (e.g., 3D nodes, physics nodes, navigation nodes).
4. Save as `custom.build` in the project root.
5. Add `build_profile = "custom.build"` to the SCons command.

### 5. Compile Custom Export Templates

```bash
# Linux template
scons platform=linuxbsd target=template_release profile=custom.py arch=x86_64

# Windows template (cross-compile from Linux)
scons platform=windows target=template_release profile=custom.py arch=x86_64

# macOS template
scons platform=macos target=template_release profile=custom.py arch=universal
```

Each build takes 15-30 minutes with `lto="full"`. The output binaries go into `bin/`.

### 6. Configure Export Presets to Use Custom Templates

Update `export_presets.cfg` to point to the custom templates:

```ini
# Linux preset
custom_template/release="res://dist/templates/godot.linuxbsd.template_release.x86_64"

# Windows preset
custom_template/release="res://dist/templates/godot.windows.template_release.x86_64.exe"

# macOS preset
custom_template/release="res://dist/templates/godot.macos.template_release.universal"
```

Store the compiled templates in `dist/templates/` (gitignored) or as CI artifacts.

### 7. Post-Processing: UPX (Windows/Linux)

Apply [UPX](https://upx.github.io/) compression to the final executable:

```bash
upx --best daccord.exe       # Windows
upx --best daccord.x86_64    # Linux
```

**Trade-offs:** UPX reduces on-disk size by ~60% but increases RAM usage by ~20MB (the compressed binary is decompressed into memory at launch). Some antivirus software flags UPX-packed executables as suspicious — consider skipping UPX for release builds distributed to end users, or signing the executable.

### 8. Post-Processing: wasm-opt (Web, Future)

If daccord adds a web export in the future:

```bash
wasm-opt original.wasm -o optimized.wasm -all --post-emscripten -Oz
```

Provides 1-2MB savings on the uncompressed WASM binary.

## Signal Flow

```
CI Release Pipeline (release.yml):
  push tag v*
    -> build job (per platform)
      -> checkout Godot source
      -> scons platform=<platform> target=template_release profile=custom.py
      -> godot --headless --export-release "<Preset>"
         (uses custom_template/release from export_presets.cfg)
      -> Post-process (UPX for Windows/Linux, optional)
      -> Package artifact
    -> release job
      -> Create GitHub Release with artifacts
```

## Key Files

| File | Role |
|------|------|
| `export_presets.cfg` | Export presets for Linux, Windows, macOS. `custom_template/release` fields point to custom templates (currently empty = stock templates). |
| `.github/workflows/release.yml` | CI release pipeline. Would need a "compile custom template" step before the export step. |
| `project.godot` | Declares GL Compatibility renderer and enabled features. Input for the build profile. |
| `custom.py` | SCons build flags for custom export templates. Does not exist yet. |
| `custom.build` | Godot build profile listing enabled/disabled node types. Does not exist yet. |
| `dist/templates/` | Directory for compiled custom export templates. Does not exist yet. |

## Implementation Details

### What to Strip

daccord is a 2D chat client using GL Compatibility. The following engine features are confirmed unused:

| Feature | Flag | Savings (approx.) | Safe to Remove? |
|---------|------|-------------------|-----------------|
| 3D engine | `disable_3d="yes"` | ~9MB (Windows) | Yes — no 3D nodes or resources |
| Vulkan renderer | `vulkan="no"`, `use_volk="no"` | ~2-3MB | Yes — project uses GL Compatibility |
| Advanced text server | `module_text_server_adv_enabled="no"` | ~2MB | Yes, unless RTL/complex script support is needed |
| OpenXR | `openxr="no"` | ~1MB | Yes — no VR/AR |
| Deprecated APIs | `deprecated="no"` | ~0.5MB | Yes — new project, no legacy API usage |
| Minizip | `minizip="no"` | small | Yes — no ZIP handling in client code |

### What NOT to Strip

| Feature | Why It's Needed |
|---------|----------------|
| Advanced GUI (`disable_advanced_gui`) | `RichTextLabel` (message content), `TextEdit` (composer), `SpinBox` (admin dialogs) |
| WebSocket module | Gateway connection to accordserver |
| mbedTLS module | HTTPS for REST API, WSS for gateway |
| Regex module | Markdown-to-BBCode parsing in `client.gd` |
| SVG module | Theme icons (`theme/icons/*.svg`) |
| FreeType module | Font rendering |

### CI Integration

The release workflow currently uses `chickensoft-games/setup-godot` to install Godot with stock templates. To use custom templates:

**Option A: Build templates in CI** — Add a job that clones Godot source, compiles custom templates with `custom.py`, and passes them as artifacts to the export job. Adds ~30 minutes per platform to CI.

**Option B: Pre-built template cache** — Compile templates locally or in a separate CI workflow, upload to a GitHub Release (e.g., `daccord-templates-v4.6`), and download them in the release workflow. Faster CI runs but requires manual template updates when Godot version changes.

**Option C: GitHub Actions cache** — Build templates once and cache them keyed by Godot version + `custom.py` hash. Subsequent runs use the cache. Best balance of automation and speed.

### Expected Results

Based on the reference article's measurements for a 2D Godot 4.5 project:

| Platform | Stock Template | Custom Template | With UPX |
|----------|---------------|-----------------|----------|
| Windows | ~93MB | ~17MB | ~5-6MB |
| Linux | ~85MB | ~16MB | ~5-6MB |
| macOS | ~90MB | ~18MB | N/A (UPX unreliable on macOS) |

Actual results will vary based on which modules are kept.

## Implementation Status

- [ ] `custom.py` build flags file created
- [ ] `custom.build` profile generated via Godot's Engine Compilation Configuration Editor
- [ ] Custom export templates compiled for Linux
- [ ] Custom export templates compiled for Windows
- [ ] Custom export templates compiled for macOS
- [ ] `export_presets.cfg` updated to reference custom templates
- [ ] `dist/templates/` directory created and gitignored
- [ ] CI release workflow updated to use custom templates
- [ ] UPX post-processing added to CI for Windows/Linux
- [ ] Build size measured before and after optimizations
- [ ] `disable_advanced_gui` confirmed as unsafe (RichTextLabel dependency)
- [ ] Selective module list validated against actual imports

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No custom export templates | High | All exports use stock Godot templates with full engine. This is the single biggest size win (~70% reduction). |
| No `custom.py` or build profile | High | Build flags need to be defined and tested. Start with the safe flags (`disable_3d`, `vulkan="no"`, `openxr="no"`) before aggressive module stripping. |
| CI doesn't compile templates | Medium | The release workflow downloads pre-built stock templates. Needs a template compilation step or a pre-built template cache. |
| No post-export compression | Low | UPX could further reduce Windows/Linux binaries but has trade-offs (RAM, antivirus). Consider for optional/advanced builds. |
| Module list not validated | Medium | The selective module list above is a best guess. Need to export with `modules_enabled_by_default="no"` and test that the app runs correctly, adding back any missing modules. |
| No web export | Low | Web-specific optimizations (wasm-opt, Brotli) are documented for future reference but not actionable today. |
| AccordStream native binary | Medium | `addons/accordstream/` includes a GDExtension native binary (`.so`/`.dll`/`.dylib`) that ships alongside the Godot export. Its size is separate from the export template and may need its own optimization (strip symbols, LTO in Rust/C++ build). |
