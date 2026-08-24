#!/usr/bin/env bash
# Run code generation. Pass --watch to keep it running during development.
#
#   scripts/codegen.sh           # one-shot build
#   scripts/codegen.sh --watch   # watch mode (keep open while developing)
#   scripts/codegen.sh --check   # one-shot build + committed-output check
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

if [ "${1:-}" = "--watch" ] || [ "${1:-}" = "-w" ]; then
  log "Running build_runner in watch mode (Ctrl-C to stop)"
  exec $DART run build_runner watch --delete-conflicting-outputs
elif [ "${1:-}" = "--check" ]; then
  log "Running deterministic build_runner check"
  $DART run build_runner build --delete-conflicting-outputs

  tracked="$(git diff --name-only HEAD -- '*.g.dart')"
  untracked="$(git ls-files --others --exclude-standard -- '*.g.dart')"
  if [ -n "$tracked" ] || [ -n "$untracked" ]; then
    echo "error: generated Dart files are not up to date." >&2
    if [ -n "$tracked" ]; then
      echo "Tracked generated files changed:" >&2
      printf '%s\n' "$tracked" | sed 's/^/  /' >&2
    fi
    if [ -n "$untracked" ]; then
      echo "Untracked generated files were created:" >&2
      printf '%s\n' "$untracked" | sed 's/^/  /' >&2
    fi
    echo "Run 'scripts/codegen.sh', review the generated changes, and commit them." >&2
    exit 1
  fi

  log "Generated Dart files match the committed output."
else
  log "Running build_runner (one-shot)"
  exec $DART run build_runner build --delete-conflicting-outputs
fi
