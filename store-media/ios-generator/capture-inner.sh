#!/usr/bin/env bash
# Regenerate the tablet capture set in ./inner from the app's own widgets.
#
# Serves tool/store_capture/capture_app.dart — the real app, wired to an
# in-memory fixture instead of a server — and photographs its six scenes with a
# headless Chromium at a 13" iPad landscape canvas (2732x2048). No Accord
# server is contacted; see docs/app-store-deploy.md, "Guideline 2.3.10".
#
# Needs a Flutter SDK and a Chromium/Chrome. Then feed the result to render.sh.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
PORT="${PORT:-8099}"
WAIT_MS="${WAIT_MS:-18000}"
CHROME="${CHROME:-$(command -v chromium || command -v google-chrome || command -v chromium-browser)}"
LOG="$(mktemp)"

cd "$ROOT"
# Release, not debug: a debug web build loads two thousand modules and is still
# on the splash screen when the shot would be taken.
flutter run --release -d web-server --web-port "$PORT" \
  -t tool/store_capture/capture_app.dart >"$LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

echo "Building the capture app (this takes a few minutes)…"
for _ in $(seq 1 120); do
  grep -q 'is being served at' "$LOG" && break
  kill -0 "$SERVER_PID" 2>/dev/null || { cat "$LOG"; exit 1; }
  sleep 5
done
grep -q 'is being served at' "$LOG" || { cat "$LOG"; exit 1; }

dart run tool/store_capture/shoot_scenes.dart \
  --chrome "$CHROME" --url "http://localhost:$PORT" \
  --out "$DIR/inner" --wait "$WAIT_MS"

dart run tool/store_capture/verify_store_shots.dart
echo "Tablet captures written to $DIR/inner — now run render.sh."
