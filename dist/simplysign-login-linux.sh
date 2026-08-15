#!/usr/bin/env bash
# Opens a Certum SimplySign cloud-signing session on a Linux CI runner and
# leaves the PKCS#11 module ready for osslsigncode.
#
# WHY LINUX AT ALL, when the artifacts are Windows binaries:
#
#   SimplySign's cloud key is reachable only through SimplySign Desktop, which
#   has no CLI - the session is opened by typing into its GUI. On a
#   GitHub-hosted Windows runner that is impossible: the runner has no
#   interactive desktop, so the app starts but never gets a window
#   (v0.2.10-rc.2 proved this - "No SimplySign window could be activated in
#   60s"). On Linux the same GUI drives fine under Xvfb, because Xvfb IS a real
#   X server, and osslsigncode can Authenticode-sign PE files through the
#   module. So the signing moves to Linux even though the binaries are not.
#
# The PKCS#11 modules Certum ship only ever talk to localhost - they are a thin
# front end onto the running SimplySign Desktop, which holds the OAuth session
# against cloudsign.webnotarius.pl. That is why the app must be running and why
# there is no way to skip it with an API call.
#
# Environment:
#   SIMPLYSIGN_USER          SimplySign account ID / e-mail            (required)
#   SIMPLYSIGN_TOTP_SECRET   enrolment otpauth:// URI (or base32)      (required)
#   SIMPLYSIGN_TIMEOUT_SEC   seconds to wait for the card              (default 180)
#
# Never fails the caller: every failure path warns and exits 0 without setting
# SIMPLYSIGN_PKCS11_MODULE, so the signing step finds no credential and ships
# unsigned binaries - the same outcome as owning no certificate.
set -uo pipefail

warn() { echo "::warning::$*"; }

if [ -z "${SIMPLYSIGN_USER:-}" ] || [ -z "${SIMPLYSIGN_TOTP_SECRET:-}" ]; then
  warn "SIMPLYSIGN_USER / SIMPLYSIGN_TOTP_SECRET are not both set - skipping SimplySign login."
  exit 0
fi

TIMEOUT_SEC="${SIMPLYSIGN_TIMEOUT_SEC:-180}"

# Pinned, like the Windows MSI: the URL is version-stamped so there is no
# floating one, and pinning lets the download be hash-checked. Bump both
# together from https://files.certum.eu/software/SimplySignDesktop/Linux-Ubuntu/
SSD_URL='https://files.certum.eu/software/SimplySignDesktop/Linux-Ubuntu/2.9.14-9.4.3.0/SimplySignDesktop-2.9.14-9.4.3.0-x86_64-prod-ubuntu.bin'
SSD_SHA256='e462dc83679f9987d4e8419c9b4db30e11884bffd875e85e142ac77aad7233e8'

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

PKCS11_MODULE=/usr/lib/SimplySignPKCS/SimplySignPKCS_64-MS-1.0.20.so

install_simplysign() {
  [ -x /opt/SimplySignDesktop/SimplySignDesktop ] && return 0

  local bin=/tmp/simplysign.bin
  echo "Downloading $SSD_URL"
  curl -fsSL -o "$bin" "$SSD_URL" || return 1

  local actual
  actual="$(sha256sum "$bin" | cut -d' ' -f1)"
  if [ "$actual" != "$SSD_SHA256" ]; then
    warn "SimplySign installer hash mismatch: expected $SSD_SHA256, got $actual"
    return 1
  fi
  echo "Installer hash verified."

  # Certum's own installer (zz_install_en) is interactive - it `read -p`s for
  # confirmation twice - so it cannot run unattended. It is also only a handful
  # of copies, so do them directly rather than trying to feed it stdin.
  rm -rf /tmp/ssd-extract && mkdir -p /tmp/ssd-extract
  sh "$bin" --noexec --keep --target /tmp/ssd-extract >/dev/null || return 1

  $SUDO rm -rf /opt/SimplySignDesktop
  $SUDO mkdir -p /opt/SimplySignDesktop /usr/lib/SimplySignPKCS
  $SUDO cp -a /tmp/ssd-extract/SSD-2.9.14-dist/. /opt/SimplySignDesktop/
  $SUDO cp -a "/opt/SimplySignDesktop/SimplySignPKCS_64-MS-1.0.20.so" "$PKCS11_MODULE"
  $SUDO ln -sf "$PKCS11_MODULE" /usr/lib/libSimplySignPKCS.so
  # The app reads its endpoint/OAuth config from $HOME, not from /opt.
  cp -f /opt/SimplySignDesktop/SimplySignDesktop.xml "$HOME/" || return 1
  echo "SimplySign Desktop installed."
}

# RFC 6238. Certum's code-signing enrolment uses HMAC-SHA256, not the SHA1
# default, so the parameters come from the otpauth:// URI - see the same note
# in dist/simplysign-login.ps1.
current_totp() {
  python3 - "$SIMPLYSIGN_TOTP_SECRET" <<'PY'
import base64, hmac, hashlib, struct, sys, time, urllib.parse
raw = sys.argv[1].strip()
secret, alg, digits, period = raw, 'SHA1', 6, 30
if raw.startswith('otpauth://'):
    q = urllib.parse.parse_qs(urllib.parse.urlparse(raw).query)
    secret = q['secret'][0]
    alg = q.get('algorithm', ['SHA1'])[0].upper()
    digits = int(q.get('digits', [6])[0])
    period = int(q.get('period', [30])[0])
key = base64.b32decode(secret + '=' * (-len(secret) % 8), casefold=True)
h = hmac.new(key, struct.pack('>Q', int(time.time()) // period), getattr(hashlib, alg.lower())).digest()
o = h[-1] & 0x0F
print(str((struct.unpack('>I', h[o:o+4])[0] & 0x7fffffff) % 10 ** digits).zfill(digits))
print(f"{alg} {digits} {period}", file=sys.stderr)
PY
}

if ! install_simplysign; then
  warn "SimplySign Desktop could not be installed - shipping UNSIGNED Windows binaries."
  exit 0
fi

# Xvfb is the whole reason this works where Windows did not: a real X server
# with no monitor attached, so the Qt app gets a genuine window to receive
# synthetic key events.
export DISPLAY=:99
Xvfb :99 -screen 0 1280x1024x24 >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
sleep 3
if ! kill -0 "$XVFB_PID" 2>/dev/null; then
  warn "Xvfb failed to start - shipping UNSIGNED Windows binaries. Log:"
  cat /tmp/xvfb.log
  exit 0
fi

export LD_LIBRARY_PATH=/opt/SimplySignDesktop
export QT_QPA_PLATFORM_PLUGIN_PATH=/opt/SimplySignDesktop/plugins

# A missing transitive library is the likeliest way this fails on a fresh
# runner, and the symptom (no window ever appears) points nowhere near the
# cause, so name the missing libraries up front instead of making the next
# person read a 60-second timeout and guess.
LDD_OUT="$(ldd /opt/SimplySignDesktop/SimplySignDesktop 2>&1)"
# Two distinct failures both say "not found": an absent file ("libfoo.so.1 =>
# not found") is fatal, whereas a symbol-version complaint ("version `X' not
# found") often is not - the app may still run. Only the former aborts; both
# get printed, because either one explains a window that never appears.
MISSING="$(awk '/=> not found/{print $1}' <<<"$LDD_OUT" | sort -u)"
VERSIONS="$(grep -F 'version `' <<<"$LDD_OUT" | sort -u)"
if [ -n "$VERSIONS" ]; then
  echo "Symbol-version mismatches (not necessarily fatal):"
  echo "$VERSIONS"
fi
if [ -n "$MISSING" ]; then
  warn "SimplySign Desktop is missing shared libraries - shipping UNSIGNED Windows binaries:"
  echo "$MISSING"
  exit 0
fi

# SimplySign Desktop is a TRAY application: it starts with no window at all and
# its login dialog is opened from a QSystemTrayIcon. A bare Xvfb has neither a
# window manager nor a system tray, so the icon has nowhere to dock and the
# window never exists - which is exactly what the first hosted-Ubuntu probe saw.
# openbox provides the WM, stalonetray provides the tray the icon docks into,
# and the icon is then clickable at a known position.
openbox >/tmp/openbox.log 2>&1 &
sleep 2
stalonetray --geometry 1x1+0+0 --icon-size 24 --window-strut none >/tmp/stalonetray.log 2>&1 &
sleep 2

# Under a session bus, because Qt's tray/notification paths expect one and
# there is no desktop session here to have started it.
dbus-run-session -- /opt/SimplySignDesktop/SimplySignDesktop >/tmp/simplysign.log 2>&1 &
SSD_PID=$!

# Give the app time to start and its icon time to dock. The previous probe
# waited 15s, clicked into an empty tray and learned nothing, so wait longer
# and say what is actually there before clicking anything.
sleep 45
if ! kill -0 "$SSD_PID" 2>/dev/null; then
  warn "SimplySign Desktop exited immediately - shipping UNSIGNED Windows binaries. Log:"
  tail -30 /tmp/simplysign.log
  exit 0
fi
echo "SimplySign is running (pid $SSD_PID). X11 tree under the tray:"
xwininfo -root -tree 2>/dev/null | grep -iE "stalonetray|simplysign|icon" | head -10

# Window titles and the X11 tree have both come back empty-handed, so capture
# the screen itself. /tmp/ssd-shot-*.png is uploaded as a CI artifact.
snap() { import -window root "/tmp/ssd-shot-$1.png" 2>/dev/null || true; }
snap 01-before-click
# The window is NOT called "SimplySign": Certum shipped it with Qt Designer's
# default title, "MainWindow". Every earlier probe searched for a window that
# was sitting right there, fullscreen, and reported "no window appeared".
find_window() {
  { xdotool search --name 'SimplySign'   2>/dev/null
    xdotool search --name '^MainWindow$' 2>/dev/null
    xdotool search --class -i simplysign 2>/dev/null
  } | head -1
}

WIN="$(find_window)"
if [ -z "$WIN" ]; then
  for attempt in double single; do
    case "$attempt" in
      double) xdotool mousemove 12 12 click --repeat 2 --delay 120 1 ;;
      single) xdotool mousemove 12 12 click 1 ;;
    esac
    snap "02-after-$attempt-click"
    for _ in $(seq 1 15); do
      WIN="$(find_window)"
      [ -n "$WIN" ] && break
      sleep 2
    done
    [ -n "$WIN" ] && { echo "Tray $attempt click opened the window."; break; }
    echo "Tray $attempt click produced no window; retrying."
  done
fi

# The tray menu is the way in. Its first item is "Connect with cloud" (then
# Options / About / Quit) - confirmed from a screen capture, since the menu is
# an override-redirect window whose items cannot be read with xdotool.
xdotool mousemove 12 12 click 3
sleep 3
snap 06-tray-menu

# Do not try to find the menu window first: it is override-redirect, so
# xdotool search does not reliably match it even while it is plainly on screen
# (a guard on that check failed a probe where the capture showed the menu open).
# Click the first item rather than sending Down/Return: Qt menus opened from a
# tray icon do not always take keyboard focus under a bare WM.
xdotool mousemove 100 24 click 1
sleep 8
snap 07-after-connect

# The login dialog is a new window; the empty "MainWindow" is not it.
LOGIN=""
for _ in $(seq 1 20); do
  LOGIN="$(xdotool search --onlyvisible --name '.' 2>/dev/null | while read -r w; do
      geo="$(xdotool getwindowgeometry "$w" 2>/dev/null | grep Geometry | tr -d ' ')"
      case "$geo" in
        *1280x1024|*24x24|*1x1) ;;                # root, tray, openbox helper
        Geometry:*) echo "$w" ;;
      esac
    done | head -1)"
  [ -n "$LOGIN" ] && break
  sleep 3
done

if [ -n "$LOGIN" ]; then
  echo "Login dialog found (id $LOGIN): $(xdotool getwindowname "$LOGIN" 2>/dev/null)"
  WIN="$LOGIN"
  xdotool windowactivate --sync "$WIN" 2>/dev/null || true
  sleep 5
  snap 08-login-dialog
else
  warn "No login dialog appeared after Connect with cloud - shipping UNSIGNED Windows binaries."
  echo "--- windows ---"
  xdotool search --onlyvisible --name '.' 2>/dev/null | while read -r w; do
    echo "  $w: $(xdotool getwindowname "$w" 2>/dev/null) $(xdotool getwindowgeometry "$w" 2>/dev/null | grep Geometry)"
  done
  snap 03-final
  exit 0
fi

# Derive the code only now, and only from a window with enough validity left to
# survive the typing below - see the matching note in the PowerShell script.
PERIOD=30
ELAPSED=$(( $(date +%s) % PERIOD ))
if [ $(( PERIOD - ELAPSED )) -lt 10 ]; then
  echo "TOTP window has $(( PERIOD - ELAPSED ))s left; waiting for the next one."
  sleep $(( PERIOD - ELAPSED + 1 ))
fi
OTP="$(current_totp 2>/tmp/totp-params)"
echo "Generated a ${#OTP}-digit TOTP ($(cat /tmp/totp-params))."   # never the value

# The form is a web view inside the window, and it does not behave like a Qt
# dialog: sending events with `xdotool --window` delivered only some of them,
# and Tab did not move focus between the fields. The previous probe ended up
# with the OTP sitting in the e-mail box and no e-mail at all.
#
# So drive it the way a person would: click each field, then type with XTEST
# (no --window) so the events go through the normal focus path. Coordinates are
# from the 1280x1024 Xvfb screen and the captures in this repo's history —
# e-mail box, token box, Login button, all horizontally centred.
click_type() {   # x y text
  xdotool mousemove "$1" "$2" click 1
  sleep 1
  xdotool key --clearmodifiers ctrl+a
  xdotool key --clearmodifiers Delete
  xdotool type --clearmodifiers --delay 80 "$3"
  sleep 1
}

click_type 639 457 "$SIMPLYSIGN_USER"
snap 09-email-typed
click_type 639 565 "$OTP"
snap 10-otp-typed
xdotool mousemove 639 645 click 1     # Login
sleep 20
snap 05-after-submit

# The login succeeds and then parks on a "Logon succesfull" panel with a Close
# button (Certum's spelling). Dismiss it — leaving the dialog up is what kept
# the earlier probes at "Get Softcards List -> none" for the full three
# minutes despite the logon having worked.
xdotool mousemove 634 738 click 1     # Close
sleep 5
snap 12-after-close

echo "Credentials submitted; waiting up to ${TIMEOUT_SEC}s for the virtual card..."

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
FOUND=0
SHOT=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep 5
  # A mounted card shows up as a PKCS#11 slot with a token present.
  if pkcs11-tool --module "$PKCS11_MODULE" --list-token-slots 2>/dev/null | grep -qi 'token label'; then
    FOUND=1
    break
  fi
  # Once, ~30s in: show what the login actually did and what the module sees.
  # A rejected OTP and a slow mount look identical from out here otherwise.
  if [ "$SHOT" -eq 0 ] && [ "$(date +%s)" -gt $(( DEADLINE - TIMEOUT_SEC + 30 )) ]; then
    SHOT=1
    snap 11-30s-after-login
    echo "--- pkcs11-tool --list-slots (30s after login) ---"
    pkcs11-tool --module "$PKCS11_MODULE" --list-slots 2>&1 | head -15
  fi
done

if [ "$FOUND" -ne 1 ]; then
  warn "SimplySign session did not expose a token within ${TIMEOUT_SEC}s - shipping UNSIGNED Windows binaries."
  echo "--- SimplySign log ---"
  tail -40 /tmp/simplysign.log
  exit 0
fi

echo "Virtual card mounted. Certificates on the token:"
pkcs11-tool --module "$PKCS11_MODULE" --list-objects --type cert 2>/dev/null | head -20

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "SIMPLYSIGN_PKCS11_MODULE=$PKCS11_MODULE"
    echo "SIMPLYSIGN_PID=$SSD_PID"
  } >> "$GITHUB_ENV"
fi
echo "Session is open; SIMPLYSIGN_PKCS11_MODULE exported."
