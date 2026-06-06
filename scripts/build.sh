#!/usr/bin/env bash
# Build a release bundle for the given platform.
#
#   scripts/build.sh [platform] [-- extra flutter args]
#
# platform: web (default) | apk | appbundle | linux | windows | ios | macos
#
# Examples:
#   scripts/build.sh                 # web release (WASM)
#   scripts/build.sh apk             # Android APK
#   scripts/build.sh linux
#   scripts/build.sh ios -- --no-codesign
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

PLATFORM="${1:-web}"
shift || true
# Drop a leading `--` separator if present so callers can append raw flags.
[ "${1:-}" = "--" ] && shift || true
EXTRA=("$@")

[ "$PLATFORM" = "linux" ] && warn_if_linux_deps_missing

log "Fetching package dependencies"
$FLUTTER pub get

log "Running code generation (build_runner)"
$DART run build_runner build --delete-conflicting-outputs

case "$PLATFORM" in
  web)
    log "Building Web (release, WASM)"
    $FLUTTER build web --no-tree-shake-icons --release "${EXTRA[@]}"
    log "Output: build/web/"
    ;;
  apk)
    log "Building Android APK (release)"
    $FLUTTER build apk --no-tree-shake-icons -v "${EXTRA[@]}"
    log "Output: build/app/outputs/flutter-apk/"
    ;;
  appbundle|aab)
    log "Building Android App Bundle (release)"
    $FLUTTER build appbundle --no-tree-shake-icons -v "${EXTRA[@]}"
    log "Output: build/app/outputs/bundle/"
    ;;
  linux)
    log "Building Linux desktop (release)"
    $FLUTTER build linux -v "${EXTRA[@]}"
    log "Output: build/linux/"
    ;;
  windows)
    log "Building Windows desktop (release)"
    $FLUTTER build windows -v "${EXTRA[@]}"
    log "Output: build/windows/"
    ;;
  ios)
    log "Building iOS (release, no codesign by default)"
    $FLUTTER build ios --release --no-tree-shake-icons --no-codesign -v "${EXTRA[@]}"
    log "Output: build/ios/"
    ;;
  macos)
    log "Building macOS desktop (release)"
    $FLUTTER build macos -v "${EXTRA[@]}"
    log "Output: build/macos/"
    ;;
  *)
    echo "error: unknown platform '$PLATFORM'." >&2
    echo "       valid: web | apk | appbundle | linux | windows | ios | macos" >&2
    exit 2
    ;;
esac

log "Build complete."
