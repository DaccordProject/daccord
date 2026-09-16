# scripts

Build/run helpers. They use `fvm flutter` when fvm is installed (channel pinned in `.fvmrc`), else `flutter`/`dart` on `PATH`.

| Script | What it does |
|--------|--------------|
| `setup.sh` | Install missing Linux desktop build deps (apt), `flutter pub get`, one-shot codegen. |
| `start.sh` | `flutter run` in debug. Defaults to `-d linux` unless you pass `-d` or `--flavor`; extra args pass through. |
| `codegen.sh` | `build_runner`. `--watch` keeps it running; `--check` fails when generated files differ from the commit. |
| `build.sh` | `pub get` + codegen + release build: Web (JavaScript, default), `apk`, `appbundle`, `linux`, `windows`, `ios`, `macos`. Args after `--` pass to `flutter build`. |
| `bootstrap-signing.sh` | One-off: create Apple signing certs/profiles and upload them as GitHub secrets (Mac with fastlane + gh). See the script header. |

```bash
scripts/setup.sh
scripts/codegen.sh --watch
scripts/codegen.sh --check
scripts/start.sh --flavor github # Android device/emulator (flavor required)
scripts/start.sh -d chrome

scripts/build.sh                 # Web (JavaScript) -> build/web/
scripts/build.sh apk             # Android GitHub/sideload APK
scripts/build.sh appbundle       # Android Play Store AAB
scripts/build.sh linux
scripts/build.sh ios -- --no-codesign
```
