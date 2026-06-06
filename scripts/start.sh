#!/usr/bin/env bash
# Run the app on a connected device/emulator (debug mode with hot reload).
#
#   scripts/start.sh                 # let Flutter pick a device
#   scripts/start.sh -d chrome       # run on a specific device
#   scripts/start.sh --release       # any extra args pass straight to `flutter run`
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

warn_if_linux_deps_missing

log "Fetching package dependencies"
$FLUTTER pub get

log "Launching app ($FLUTTER run $*)"
exec $FLUTTER run "$@"
