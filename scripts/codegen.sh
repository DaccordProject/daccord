#!/usr/bin/env bash
# Run code generation. Pass --watch to keep it running during development.
#
#   scripts/codegen.sh           # one-shot build
#   scripts/codegen.sh --watch   # watch mode (keep open while developing)
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

if [ "${1:-}" = "--watch" ] || [ "${1:-}" = "-w" ]; then
  log "Running build_runner in watch mode (Ctrl-C to stop)"
  exec $DART run build_runner watch --delete-conflicting-outputs
else
  log "Running build_runner (one-shot)"
  exec $DART run build_runner build --delete-conflicting-outputs
fi
