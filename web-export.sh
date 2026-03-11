#!/usr/bin/env bash
# web-export.sh — Run the Godot web export, then download livekit-client JS SDK
# and copy the godot-livekit web wrapper into the output directory so voice/video
# works at runtime.
#
# Usage:  ./web-export.sh [livekit-client-version]
#   livekit-client-version  livekit-client major version (default: 2)

set -euo pipefail

VERSION="${1:-2}"
SDK_URL="https://cdn.jsdelivr.net/npm/livekit-client@${VERSION}/dist/livekit-client.umd.min.js"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist/build/web"
TEMPLATE_DIR="${SCRIPT_DIR}/export/web"

# Path to the godot-livekit web wrapper (custom JS bridge in export/web/).
GODOT_LIVEKIT_WEB="${GODOT_LIVEKIT_WEB:-${TEMPLATE_DIR}/godot-livekit-web.js}"

# --- 1. Run Godot web export ---------------------------------------------------
echo "Running Godot web export..."
mkdir -p "$DIST_DIR"
godot --headless --export-release "Web" 2>&1 | tee /tmp/web_export.log

if [ ! -f "${DIST_DIR}/Daccord.html" ]; then
  echo "ERROR: Web export failed — Daccord.html not produced"
  exit 1
fi
echo "Godot web export complete."

# --- 2. Download livekit-client UMD bundle ------------------------------------
echo "Downloading livekit-client@${VERSION} UMD bundle..."
curl -fSL --retry 3 -o "${DIST_DIR}/livekit-client.umd.min.js" "$SDK_URL"
echo "  -> $(wc -c < "${DIST_DIR}/livekit-client.umd.min.js" | tr -d ' ') bytes"

# Also keep a copy in the template dir for reference.
cp "${DIST_DIR}/livekit-client.umd.min.js" "${TEMPLATE_DIR}/"

# --- 3. Copy godot-livekit web wrapper ----------------------------------------
if [ -f "$GODOT_LIVEKIT_WEB" ]; then
  cp "$GODOT_LIVEKIT_WEB" "${DIST_DIR}/godot-livekit-web.js"
  echo "Copied godot-livekit-web.js"
else
  echo "WARNING: godot-livekit-web.js not found at ${GODOT_LIVEKIT_WEB}"
  echo "  Voice/video will not work in the web export."
fi

echo "Done. Output in ${DIST_DIR}/"
ls -lh "$DIST_DIR"
