#!/usr/bin/env bash
# Launches a built Linux bundle under a private Xvfb display and fails unless
# the whole window gets painted, on both of the embedder's compositor paths.
#
# Framework-level tests (widget, integration_test) inspect Flutter's layer
# tree, so they cannot see an embedder/compositor fault. Flutter 3.49.0-0.1.pre
# shipped one in v0.2.22: on NVIDIA the window stayed mostly black while every
# test passed. This check screenshots the real X window instead and requires
# each quadrant to be mostly non-black.
#
# The GTK embedder composites with glBlitFramebuffer, except on drivers whose
# GL_VENDOR it distrusts (NVIDIA, ARM, Vivante), which take a textured-quad
# fallback — the path that broke. Mesa's `force_gl_vendor` driconf override
# (read from the environment) routes the second pass through that fallback on
# a software renderer, so CI covers the path NVIDIA users get.
#
# Usage: dist/verify-linux-render.sh <bundle-dir> [screenshot-dir]
# Needs: Xvfb and Mesa, xdotool, ImageMagick (import/convert), dbus
# (dbus-run-session) and gnome-keyring — the app aborts at startup without a
# session bus or a Secret Service. GStreamer's playbin
# (gstreamer1.0-plugins-base) is deliberately not required: without it the app
# must still start, just silently (packages/audioplayers_linux/FORK.md).
set -euo pipefail

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  exec dbus-run-session -- "$0" "$@"
fi

bundle=${1:?usage: $0 <bundle-dir> [screenshot-dir]}
shots=${2:-${RUNNER_TEMP:-/tmp}}
exe="$bundle/daccord"
[ -x "$exe" ] || { echo "error: $exe is not an executable bundle" >&2; exit 2; }
mkdir -p "$shots"

timeout_s=${RENDER_TIMEOUT:-60}
# A quadrant passes when at least this fraction of its pixels is brighter than
# near-black. The app's darkest surface is well above the cutoff; the broken
# engine left whole quadrants at 0.
min_painted=0.9
near_black=3%

work=$(mktemp -d)
app_pid=
xvfb_pid=
cleanup() {
  [ -n "$app_pid" ] && kill "$app_pid" 2>/dev/null || true
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# -displayfd picks a free display number and reports it once the server is up.
Xvfb -displayfd 3 -screen 0 1920x1080x24 -nolisten tcp 3>"$work/display" \
  2>"$work/xvfb.log" &
xvfb_pid=$!
xvfb_deadline=$((SECONDS + timeout_s))
while [ ! -s "$work/display" ] && [ $SECONDS -lt "$xvfb_deadline" ]; do
  kill -0 "$xvfb_pid" 2>/dev/null || break
  sleep 0.1
done
[ -s "$work/display" ] || {
  echo "error: Xvfb did not provide a display within ${timeout_s}s" >&2
  cat "$work/xvfb.log" >&2
  exit 1
}
export DISPLAY=":$(cat "$work/display")"

# A throwaway home (and keyring inside it) keeps the check away from any real
# profile, and the fresh profile always opens on the same first-run screen.
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" \
  XDG_DATA_HOME="$work/home/.local/share"
mkdir -p "$HOME"
eval "$(printf 'render-smoke' |
  gnome-keyring-daemon --unlock --components=secrets)"

quadrant_painted() { # <png> <x> <y> <w> <h> → fraction of non-black pixels
  convert "$1" -crop "$4x$5+$2+$3" +repage -colorspace Gray \
    -threshold "$near_black" -format '%[fx:mean]' info:
}

# render_pass <label> [VAR=value...] — launches the app with the given
# environment and waits for a fully painted window.
render_pass() {
  local label=$1 shot="$shots/daccord-render-$1.png" verdict= win w h hw hh
  shift
  env "$@" "$exe" >"$work/app-$label.log" 2>&1 &
  app_pid=$!

  local deadline=$((SECONDS + timeout_s)) status=1
  while [ $SECONDS -lt $deadline ]; do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      echo "error [$label]: the app exited before painting a frame" >&2
      break
    fi
    sleep 2
    win=$(xdotool search --onlyvisible --name '^Daccord$' 2>/dev/null |
      head -1) || true
    [ -n "$win" ] || continue
    import -window "$win" "$shot" 2>/dev/null || continue
    read -r w h < <(identify -format '%w %h\n' "$shot")
    hw=$((w / 2)) hh=$((h / 2))
    verdict=$(printf '%s ' \
      "$(quadrant_painted "$shot" 0 0 "$hw" "$hh")" \
      "$(quadrant_painted "$shot" "$hw" 0 "$((w - hw))" "$hh")" \
      "$(quadrant_painted "$shot" 0 "$hh" "$hw" "$((h - hh))")" \
      "$(quadrant_painted "$shot" "$hw" "$hh" "$((w - hw))" "$((h - hh))")")
    if awk -v min="$min_painted" \
      '{ for (i = 1; i <= NF; i++) if ($i < min) exit 1 }' <<<"$verdict"; then
      status=0
      break
    fi
  done

  kill "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  app_pid=

  if [ $status -eq 0 ]; then
    echo "[$label] rendered ${w}x${h}; painted per quadrant (TL TR BL BR): $verdict"
  else
    echo "error [$label]: the window never painted fully within ${timeout_s}s." >&2
    echo "Painted per quadrant (TL TR BL BR): ${verdict:-no window}" >&2
    echo "Last screenshot: $shot" >&2
    tail -40 "$work/app-$label.log" >&2
  fi
  return $status
}

failed=0
render_pass blit || failed=1
render_pass fallback 'force_gl_vendor=NVIDIA Corporation' || failed=1
exit $failed
