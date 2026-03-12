#!/usr/bin/env bash
# web-export.sh — Run the Godot web export, then download livekit-client JS SDK
# and copy the godot-livekit web wrapper into the output directory so voice/video
# works at runtime.
#
# Usage:
#   ./web-export.sh [livekit-client-version]   Export the web build
#   ./web-export.sh serve [port]               Serve dist/build/web with COOP/COEP headers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist/build/web"
TEMPLATE_DIR="${SCRIPT_DIR}/dist/web"

# --- serve subcommand ---------------------------------------------------------
if [ "${1:-}" = "serve" ]; then
  PORT="${2:-8060}"
  if [ ! -f "${DIST_DIR}/Daccord.html" ]; then
    echo "ERROR: No web build found. Run ./web-export.sh first."
    exit 1
  fi
  echo "Serving ${DIST_DIR} on http://localhost:${PORT}"
  exec python3 -c "
import http.server, sys
PORT = int(sys.argv[1])
DIR = sys.argv[2]
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=DIR, **kw)
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()
http.server.HTTPServer(('0.0.0.0', PORT), H).serve_forever()
" "$PORT" "$DIST_DIR"
fi

# --- export -------------------------------------------------------------------
VERSION="${1:-2}"
SDK_URL="https://cdn.jsdelivr.net/npm/livekit-client@${VERSION}/dist/livekit-client.umd.min.js"

# Path to the godot-livekit web wrapper (custom JS bridge in dist/web/).
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

# --- 4. Copy COOP/COEP service worker -----------------------------------------
if [ -f "${TEMPLATE_DIR}/coop_coep.js" ]; then
  cp "${TEMPLATE_DIR}/coop_coep.js" "${DIST_DIR}/coop_coep.js"
  echo "Copied coop_coep.js"
fi

echo "Done. Output in ${DIST_DIR}/"
ls -lh "$DIST_DIR"
