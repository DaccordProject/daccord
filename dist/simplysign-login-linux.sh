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
MISSING="$(ldd /opt/SimplySignDesktop/SimplySignDesktop 2>/dev/null | awk '/not found/{print $1}' | sort -u)"
if [ -n "$MISSING" ]; then
  warn "SimplySign Desktop is missing shared libraries - shipping UNSIGNED Windows binaries:"
  echo "$MISSING"
  exit 0
fi

/opt/SimplySignDesktop/SimplySignDesktop >/tmp/simplysign.log 2>&1 &
SSD_PID=$!

# Poll for the window rather than sleeping a fixed interval.
WIN=""
for _ in $(seq 1 30); do
  WIN="$(xdotool search --name 'SimplySign' 2>/dev/null | head -1)"
  [ -n "$WIN" ] && break
  sleep 2
done
if [ -z "$WIN" ]; then
  warn "No SimplySign window appeared in 60s - shipping UNSIGNED Windows binaries. Log:"
  tail -30 /tmp/simplysign.log
  exit 0
fi
echo "SimplySign window found (id $WIN)."
xdotool windowactivate --sync "$WIN" 2>/dev/null || true
sleep 2

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

xdotool type --window "$WIN" --delay 60 "$SIMPLYSIGN_USER"
xdotool key --window "$WIN" Tab
sleep 1
xdotool type --window "$WIN" --delay 60 "$OTP"
xdotool key --window "$WIN" Return

echo "Credentials submitted; waiting up to ${TIMEOUT_SEC}s for the virtual card..."

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
FOUND=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep 5
  # A mounted card shows up as a PKCS#11 slot with a token present.
  if pkcs11-tool --module "$PKCS11_MODULE" --list-token-slots 2>/dev/null | grep -qi 'token label'; then
    FOUND=1
    break
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
