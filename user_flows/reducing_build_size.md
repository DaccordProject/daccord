# Reducing Build Size


## Overview

This flow documents how to reduce daccord's exported build size using custom Godot export templates with unused features stripped out. The stock Godot export templates include the full engine (3D, VR, advanced text shaping, Vulkan, etc.), most of which daccord doesn't use. By using minimal custom templates and applying post-processing tools, the final binary size can be cut by 70-80%.

Reference: [How to Minify Godot's Build Size](https://popcar.bearblog.dev/how-to-minify-godots-build-size/) by Popcar.

Custom export templates are provided by [GodotLite](https://github.com/NodotProject/GodotLite), a cross-platform project that ships pre-built minimal Godot export templates for Linux, Windows, and macOS. Pre-built templates can be downloaded directly from [GodotLite Releases](https://github.com/NodotProject/GodotLite/releases) — no compilation required. For custom builds, GodotLite also provides its `custom.py` and `build.sh` source. Downloaded templates are stored in `dist/templates/` and tracked with git-lfs.

## Current State

daccord exports to three platforms via the release CI pipeline (`.github/workflows/release.yml`):

| Platform | Preset | Output |
|----------|--------|--------|
| Linux | `Linux` | `daccord-linux-x86_64.tar.gz` |
| Windows | `Windows` | `daccord-windows-x86_64.zip` |
| macOS | `macOS` | `daccord-macos.zip` |

`export_presets.cfg` points to custom templates in `dist/templates/` (tracked with git-lfs). The project uses the GL Compatibility renderer (`project.godot` line 20), meaning Vulkan is unused.

## Architecture

### GodotLite

[GodotLite](https://github.com/NodotProject/GodotLite) is a minimal Godot builder for apps and simple games. It provides:

- **Pre-built export templates** for Linux, Windows, and macOS, available as release downloads
- **`custom.py`** — SCons build flags that disable 3D, Vulkan, XR, and all unused modules
- **`build.sh`** — Build script to compile templates from Godot source (for custom builds)

```
NodotProject/GodotLite
├── custom.py        # SCons build flags for minimal export templates
├── build.sh         # Clones Godot source and compiles templates
├── .gitignore       # Ignores godot/ source clone and build artifacts
├── .gitattributes   # git-lfs tracking for compiled template binaries
└── godot/           # (gitignored) Godot source, cloned by build.sh
    └── bin/         # Compiled template output
```

### daccord Template Directory

Downloaded or compiled templates are stored in the daccord repo:

```
daccord/
└── dist/
    └── templates/                                          # git-lfs tracked
        ├── godot.linuxbsd.template_release.x86_64          # Linux template
        ├── godot.windows.template_release.x86_64.exe       # Windows template
        └── godot.macos.template_release.universal           # macOS template
```

### Build Flags (`custom.py`)

GodotLite's `custom.py` ships with the same flags daccord needs out of the box:

```python
# custom.py — minimal export template build flags
# Godot 4.5

# Size optimization
optimize = "size"          # -Os compiler flag (smaller binary)
lto = "full"               # Link-time optimization (slower build, smaller output)
deprecated = "no"          # Strip deprecated API wrappers

# Strip 3D engine
disable_3d = "yes"

# Renderer — GL Compatibility only, no Vulkan
vulkan = "no"
use_volk = "no"

# Disable unused features
openxr = "no"              # No VR/AR support needed
minizip = "no"             # No ZIP archive support needed

# Text server — use fallback (no RTL/complex script support)
module_text_server_adv_enabled = "no"
module_text_server_fb_enabled = "yes"

# Aggressive stripping: disable all modules by default, enable only what's needed
modules_enabled_by_default = "no"

# Enabled modules
module_gdscript_enabled = "yes"          # Scripting language
module_text_server_fb_enabled = "yes"    # Text rendering
module_freetype_enabled = "yes"          # Font rendering
module_svg_enabled = "yes"               # SVG icon support (theme/icons/)
module_webp_enabled = "yes"              # WebP image support
module_godot_physics_2d_enabled = "yes"  # 2D physics (if used)
module_websocket_enabled = "yes"         # WebSocket gateway
module_mbedtls_enabled = "yes"           # TLS for HTTPS/WSS
module_regex_enabled = "yes"             # Regex (used in markdown parsing)
```

**Do NOT disable `disable_advanced_gui`** — daccord relies heavily on `RichTextLabel` (message rendering, markdown-to-BBCode), `TextEdit` (composer), and other advanced GUI nodes.

If daccord ever needs additional modules beyond what GodotLite ships, fork the repo or override `custom.py` before building from source.

## User Steps

### Downloading Pre-Built Templates (Recommended)

Download the export templates for all three platforms from [GodotLite Releases](https://github.com/NodotProject/GodotLite/releases):

1. Go to the release matching your Godot version (e.g., `v4.5`)
2. Download the template ZIPs:
   - `templates-v4.5-linux.zip`
   - `templates-v4.5-windows.zip`
   - `templates-v4.5-macos.zip`
3. Extract each ZIP and copy the template binaries into `dist/templates/`:

```bash
# Extract and copy templates
unzip templates-v4.5-linux.zip -d /tmp/templates
unzip templates-v4.5-windows.zip -d /tmp/templates
unzip templates-v4.5-macos.zip -d /tmp/templates

cp /tmp/templates/godot.linuxbsd.template_release.x86_64 dist/templates/
cp /tmp/templates/godot.windows.template_release.x86_64.exe dist/templates/
cp /tmp/templates/godot.macos.template_release.universal dist/templates/
```

These are tracked with git-lfs, so commit and push as usual.

### Building Templates From Source (Optional)

Only needed if you want to customize `custom.py` beyond the GodotLite defaults.

```bash
# Clone GodotLite
git clone https://github.com/NodotProject/GodotLite.git
cd GodotLite

# Build all platforms
./build.sh

# Or build a single platform
./build.sh linux
./build.sh windows
./build.sh macos
```

`build.sh` handles cloning the Godot 4.5 source, copying `custom.py` in, and compiling. Output goes to `godot/bin/`.

### Updating daccord Templates

After downloading or building, copy the template binaries into the daccord repo:

```bash
cp godot/bin/godot.linuxbsd.template_release.x86_64 ../daccord/dist/templates/
cp godot/bin/godot.windows.template_release.x86_64.exe ../daccord/dist/templates/
cp godot/bin/godot.macos.template_release.universal ../daccord/dist/templates/
```

These are tracked with git-lfs, so commit and push as usual.

### Generate a Build Profile File (Optional)

Use Godot's Engine Compilation Configuration Editor to strip unused node types:

1. Open the project in Godot Editor.
2. Go to `Project > Tools > Engine Compilation Configuration Editor`.
3. Uncheck node types daccord doesn't use (e.g., 3D nodes, physics nodes, navigation nodes).
4. Save as `custom.build` in the project root.
5. Add `build_profile = "custom.build"` to the SCons command.

### Post-Processing: UPX (Windows/Linux)

Apply [UPX](https://upx.github.io/) compression to the final executable:

```bash
upx --best daccord.exe       # Windows
upx --best daccord.x86_64    # Linux
```

**Trade-offs:** UPX reduces on-disk size by ~60% but increases RAM usage by ~20MB (the compressed binary is decompressed into memory at launch). Some antivirus software flags UPX-packed executables as suspicious — consider skipping UPX for release builds distributed to end users, or signing the executable.

### Post-Processing: wasm-opt (Web, Future)

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
      -> checkout daccord (with lfs: true to pull dist/templates/*)
      -> godot --headless --export-release "<Preset>"
         (uses custom_template/release from export_presets.cfg,
          pointing to res://dist/templates/<template binary>)
      -> Post-process (UPX for Windows/Linux, optional)
      -> Package artifact
    -> release job
      -> Create GitHub Release with artifacts

Template Update (when Godot version changes):
  developer workstation
    -> download pre-built templates from GodotLite Releases
       (https://github.com/NodotProject/GodotLite/releases)
    -> extract and copy to daccord/dist/templates/
    -> git add, commit, push (git-lfs handles the large binaries)
```

## Key Files

| File | Role |
|------|------|
| `export_presets.cfg` | Export presets for Linux, Windows, macOS. `custom_template/release` fields point to custom templates in `dist/templates/`. |
| `.github/workflows/release.yml` | CI release pipeline. Uses custom templates pulled via git-lfs during checkout. |
| `.gitattributes` | git-lfs tracking for `dist/templates/*` (and fonts, images). |
| `project.godot` | Declares GL Compatibility renderer and enabled features. |
| `dist/templates/` | Custom export templates (from GodotLite releases), tracked with git-lfs. |
| [GodotLite](https://github.com/NodotProject/GodotLite) `custom.py` | SCons build flags for minimal export templates. |
| [GodotLite](https://github.com/NodotProject/GodotLite) `build.sh` | Build script that clones Godot source and compiles templates. |
| [GodotLite Releases](https://github.com/NodotProject/GodotLite/releases) | Pre-built template downloads for Linux, Windows, and macOS. |

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

The release workflow uses `chickensoft-games/setup-godot` to install the Godot editor binary. Custom templates are stored in `dist/templates/` (git-lfs) and pulled during the `actions/checkout` step with `lfs: true`. The Godot export picks them up via the `custom_template/release` paths in `export_presets.cfg`.

Template binaries only need to be updated when:
- The Godot version changes (download new templates from GodotLite releases)
- daccord needs modules not included in GodotLite's defaults (build from source with a modified `custom.py`)

Updated templates are committed to daccord's `dist/templates/` via git-lfs.

### Measured Results

Linux export with custom template (Godot 4.5.1-stable):

| File | Size |
|------|------|
| `daccord.x86_64` (custom template) | 30MB |
| `daccord.pck` (game data) | 13MB |
| `liblivekit.so` (GDExtension) | 28MB |
| `libsentry.linux.release.x86_64.so` | 3.9MB |
| `crashpad_handler` | 903KB |
| **Total** | **~75MB** |

Stock template comparison (~85MB for Linux), so the custom template provides a ~65% reduction on the engine binary.

## Implementation Status

- [x] Pre-built templates available via [GodotLite](https://github.com/NodotProject/GodotLite) for all three platforms
- [x] `custom.py` build flags maintained in GodotLite repo
- [x] `build.sh` build script maintained in GodotLite repo
- [ ] `custom.build` profile generated via Godot's Engine Compilation Configuration Editor
- [x] Custom export templates for Linux (via GodotLite release)
- [x] Custom export templates for Windows (via GodotLite release)
- [x] Custom export templates for macOS (via GodotLite release)
- [x] `export_presets.cfg` updated to reference custom templates
- [x] `dist/templates/` directory created and git-lfs tracked
- [x] CI release workflow updated (Godot version `4.6` -> `4.5`)
- [ ] UPX post-processing added to CI for Windows/Linux
- [x] Build size measured (Linux: 30MB template, 75MB total export)
- [ ] `disable_advanced_gui` confirmed as unsafe (RichTextLabel dependency)
- [ ] Selective module list validated against actual imports

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| ~~Windows/macOS templates not yet compiled~~ | ~~High~~ | **Resolved** — GodotLite provides pre-built templates for all three platforms. |
| ~~CI Godot version mismatch~~ | ~~Medium~~ | **Resolved** — `release.yml` updated to `GODOT_VERSION: "4.5.0"`. |
| Module list not validated | Medium | The selective module list is a best guess. Need to export with `modules_enabled_by_default="no"` and test that the app runs correctly, adding back any missing modules. |
| No post-export compression | Low | UPX could further reduce Windows/Linux binaries but has trade-offs (RAM, antivirus). Consider for optional/advanced builds. |
| No web export | Low | Web-specific optimizations (wasm-opt, Brotli) are documented for future reference but not actionable today. |
| LiveKit native binary | Medium | `addons/livekit/` includes a GDExtension native binary (`.so`/`.dll`/`.dylib`) at 28MB that ships alongside the Godot export. Its size is separate from the export template and may need its own optimization (strip symbols, LTO in Rust/C++ build). |
