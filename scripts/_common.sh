#!/usr/bin/env bash
# Shared helpers for the Daccord build/run scripts.
# Sourced by the other scripts in this folder — not meant to be run directly.

set -euo pipefail

# Resolve the repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Prefer fvm (the repo pins a Flutter channel in .fvmrc) when it's installed,
# otherwise fall back to a plain `flutter` on PATH.
if command -v fvm >/dev/null 2>&1 && [ -f "$REPO_ROOT/.fvmrc" ]; then
  FLUTTER="fvm flutter"
  DART="fvm dart"
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER="flutter"
  DART="dart"
else
  echo "error: neither 'fvm' nor 'flutter' found on PATH." >&2
  echo "       install Flutter (https://docs.flutter.dev/get-started/install)" >&2
  echo "       or fvm (https://fvm.app) and re-run." >&2
  exit 127
fi

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

# Linux desktop builds shell out to CMake, which honours the CXX/CC env vars.
# Some environments (e.g. the VSCodium / Freedesktop Flatpak runtime) export
# CXX=clang++ / CC=clang even when clang isn't actually usable, which makes
# CMake abort before it can fall back to the system compiler.
#
# Treat a compiler as usable only if it's on PATH *and* actually runs. If the
# configured CXX/CC isn't usable, pin gcc/g++ explicitly (exported, so the CMake
# subprocess inherits it) rather than just unsetting — that way a stray clang in
# a downstream toolchain can't sneak back in.
_compiler_works() { command -v "$1" >/dev/null 2>&1 && "$1" --version >/dev/null 2>&1; }

if [ -n "${CXX:-}" ] && ! _compiler_works "$CXX"; then
  warn "\$CXX='$CXX' isn't a working compiler here."
  if _compiler_works g++; then
    warn "Pinning CXX=g++ for this build."
    export CXX=g++
  else
    warn "g++ not found either — unsetting CXX and letting CMake choose."
    unset CXX
  fi
fi

if [ -n "${CC:-}" ] && ! _compiler_works "$CC"; then
  if _compiler_works gcc; then
    export CC=gcc
  else
    unset CC
  fi
fi

# Native system libraries the Linux desktop build links against, expressed as
# `pkg-config module:apt dev package`. media_kit needs mpv; audioplayers needs
# gstreamer, whose *private* deps (libunwind, libdw) must also ship their .pc
# files or CMake's pkg_check_modules aborts with a misleading "gstreamer-1.0 not
# found". gtk+-3.0 is the base Flutter Linux requirement.
LINUX_PKGCONFIG_DEPS=(
  "gtk+-3.0:libgtk-3-dev"
  "gstreamer-1.0:libgstreamer1.0-dev"
  "gstreamer-base-1.0:libgstreamer-plugins-base1.0-dev"
  "libunwind:libunwind-dev"
  "libdw:libdw-dev"
  "mpv:libmpv-dev"
)

# Echo (one per line) the apt dev packages whose pkg-config module is absent.
# Empty output means the Linux build deps are satisfied.
linux_missing_dev_pkgs() {
  if ! command -v pkg-config >/dev/null 2>&1; then echo pkg-config; return; fi
  local pair mod pkg
  for pair in "${LINUX_PKGCONFIG_DEPS[@]}"; do
    mod="${pair%%:*}"; pkg="${pair#*:}"
    pkg-config --exists "$mod" 2>/dev/null || echo "$pkg"
  done
}

# Install any missing Linux build deps via apt (used by setup.sh). No-op off
# Linux or on non-apt distros (the build will surface its own error there).
install_linux_dev_deps() {
  [ "$(uname -s)" = "Linux" ] || return 0
  command -v apt-get >/dev/null 2>&1 || return 0
  local missing
  missing="$(linux_missing_dev_pkgs | sort -u)"
  if [ -z "$missing" ]; then
    log "Linux build dependencies already satisfied."
    return 0
  fi
  log "Installing missing Linux build dependencies: $(echo $missing)"
  local sudo=""
  [ "$(id -u)" -eq 0 ] || sudo="sudo"
  $sudo apt-get update
  $sudo apt-get install -y $missing
}

# Non-fatal nudge for the run/build scripts: warn and point at setup.sh rather
# than silently letting CMake fail three layers deep.
warn_if_linux_deps_missing() {
  [ "$(uname -s)" = "Linux" ] || return 0
  command -v apt-get >/dev/null 2>&1 || return 0
  local missing
  missing="$(linux_missing_dev_pkgs | sort -u)"
  [ -n "$missing" ] || return 0
  warn "Missing Linux build deps: $(echo $missing)"
  warn "Run scripts/setup.sh, or: sudo apt-get install -y $(echo $missing)"
}
