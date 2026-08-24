# scripts

Helper scripts for building and running the Daccord Flutter client.

They use `fvm flutter` when [fvm](https://fvm.app) is installed (the repo pins a
channel in `.fvmrc`), and fall back to a plain `flutter`/`dart` on `PATH`.

| Script | What it does |
|--------|--------------|
| `setup.sh` | Install Linux desktop build deps (via apt, if missing) + `flutter pub get` + one-shot code generation. Run after cloning or pulling. |
| `start.sh` | Run the app in debug mode (hot reload). Extra args pass to `flutter run`, e.g. `scripts/start.sh -d chrome`. |
| `codegen.sh` | Run `build_runner`. Pass `--watch` to keep it running during development. |
| `build.sh` | Release build for a platform: Web (JavaScript, the default), `apk`, `appbundle`, `linux`, `windows`, `ios`, `macos`. |

## Examples

```bash
scripts/setup.sh                 # first-time setup
scripts/codegen.sh --watch       # keep this open while developing
scripts/start.sh --flavor github # run on an Android device/emulator
scripts/start.sh -d chrome       # run in Chrome

scripts/build.sh                 # Web (JavaScript) release -> build/web/
scripts/build.sh apk             # Android GitHub/sideload APK
scripts/build.sh appbundle       # Android Play Store AAB
scripts/build.sh linux           # Linux desktop (setup.sh installs the native deps)
scripts/build.sh ios -- --no-codesign
```
