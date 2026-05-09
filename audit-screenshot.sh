#!/usr/bin/env bash
# audit-screenshot.sh — Launch daccord with Xvfb for headless screenshot capture.
# Usage: ./audit-screenshot.sh [--port 39100] [--resolution 1280x720x24]
#
# Starts daccord under a virtual framebuffer so the test API's screenshot
# endpoint works in CI or headless environments.
#
# Prerequisites: xvfb (apt install xvfb)

set -euo pipefail

PORT="${PORT:-39100}"
RESOLUTION="1280x720x24"
GODOT="${GODOT:-godot}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --resolution) RESOLUTION="$2"; shift 2 ;;
        --godot) GODOT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if ! command -v xvfb-run &>/dev/null; then
    echo "Error: xvfb-run not found. Install with: apt install xvfb"
    exit 1
fi

echo "Starting daccord under Xvfb (${RESOLUTION}) with test API on port ${PORT}..."
exec xvfb-run -a -s "-screen 0 ${RESOLUTION}" \
    "$GODOT" --test-api --test-api-port "$PORT" "$@"
