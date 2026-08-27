#!/usr/bin/env bash
# Run the app in debug mode (hot reload). Defaults to the Linux desktop
# target; pass -d/--device-id to target something else.
#
#   scripts/start.sh                 # run on Linux desktop
#   scripts/start.sh --flavor github # run on an Android device/emulator
#   scripts/start.sh -d chrome       # run in Chrome
#   scripts/start.sh --release       # any extra args pass straight to `flutter run`
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Only default to the Linux desktop device when the caller hasn't already
# said where to run, so `-d chrome` (etc.) isn't clobbered by a second
# `-d linux`.
DEVICE_ARGS=()
has_target=false
for arg in "$@"; do
  case "$arg" in
    # `-d chrome`, `-dchrome`, `--device-id chrome`, `--device-id=chrome`.
    -d | -d?* | --device-id | --device-id=*) has_target=true ;;
    # Only Android declares product flavors (android/app/build.gradle), and a
    # flavor is mandatory there — so `--flavor` means "an Android device", and
    # forcing `-d linux` alongside it would fail on a target that has no
    # flavors. Leave the device to `flutter run` to pick or prompt for.
    --flavor | --flavor=*) has_target=true ;;
  esac
done

if [ "$has_target" = false ]; then
  warn_if_linux_deps_missing
  DEVICE_ARGS=(-d linux)
fi

log "Fetching package dependencies"
$FLUTTER pub get

log "Launching app ($FLUTTER run ${DEVICE_ARGS[*]+"${DEVICE_ARGS[*]}"} $*)"
exec $FLUTTER run ${DEVICE_ARGS[@]+"${DEVICE_ARGS[@]}"} "$@"
