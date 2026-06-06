#!/usr/bin/env bash
# Run the app on the Linux desktop target (debug mode with hot reload).
#
#   scripts/start.sh                 # run on Linux desktop
#   scripts/start.sh --release       # any extra args pass straight to `flutter run`
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

warn_if_linux_deps_missing

log "Fetching package dependencies"
$FLUTTER pub get

log "Launching app ($FLUTTER run -d linux $*)"
exec $FLUTTER run -d linux "$@"
