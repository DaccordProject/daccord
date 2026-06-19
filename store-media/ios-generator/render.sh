#!/usr/bin/env bash
# Render Apple App Store screenshots from template.html.
# iPhone 6.9" = 1290x2796, iPad 13" = 2048x2732 (exact pixel sizes Apple requires).
# Needs a Chromium/Chrome with headless support. Inner app captures live in ./inner.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CHROME="${CHROME:-$(command -v chromium || command -v google-chrome || command -v chromium-browser)}"
OUT="$DIR/out"; mkdir -p "$OUT"
shot(){ "$CHROME" --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size="$3" --virtual-time-budget=9000 \
  --screenshot="$OUT/$4" "file://$DIR/template.html?scene=$1&device=$2" 2>/dev/null; }
for s in 1 2 3 4 5 6; do
  shot "$s" iphone 1290,2796 "iphone-0$s.png"
  shot "$s" ipad   2048,2732 "ipad-0$s.png"
done
echo "Rendered 12 screenshots to $OUT"
