#!/usr/bin/env bash
# Robust apt-get install for CI runners.
#
# The bare `sudo apt-get update && sudo apt-get install` pattern fails
# regularly in CI because:
#   1. Ubuntu mirrors occasionally return slow or partial responses, and
#      apt's default of zero retries surfaces those as hard failures.
#   2. With `-qq`, apt produces no output, so a hang looks identical to
#      a slow download until the step's timeout fires.
#   3. Wine + i386 pulls a few hundred MB of packages on a cold runner,
#      which is enough to outrun a 10-minute step timeout if a single
#      mirror is degraded.
#
# This wrapper:
#   - Configures apt to retry transport errors (Acquire::Retries) and
#     to time out hung connections quickly so retries actually trigger.
#   - Retries the whole `update + install` cycle up to 3 times with
#     exponential backoff between attempts.
#   - Drops `-qq` so failures leave a useful tail in the log.
#
# Usage:  apt-install.sh <pkg> [pkg ...]
# Env:    APT_INSTALL_EXTRA_FLAGS (e.g. "--no-install-recommends")

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "::error::apt-install.sh requires at least one package name"
  exit 2
fi

EXTRA_FLAGS="${APT_INSTALL_EXTRA_FLAGS:-}"

# Apt config: retry network ops, fail fast on stuck mirrors so retries kick in.
sudo tee /etc/apt/apt.conf.d/99-ci-robust >/dev/null <<'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::http::No-Cache "true";
APT::Get::Assume-Yes "true";
EOF

export DEBIAN_FRONTEND=noninteractive

attempt=1
max_attempts=3
delay=15
while :; do
  echo "::group::apt install (attempt ${attempt}/${max_attempts}): $*"
  if sudo -E apt-get update && \
     sudo -E apt-get install -y ${EXTRA_FLAGS} "$@"; then
    echo "::endgroup::"
    echo "apt install succeeded on attempt ${attempt}"
    exit 0
  fi
  echo "::endgroup::"

  if [ "${attempt}" -ge "${max_attempts}" ]; then
    echo "::error::apt install failed after ${max_attempts} attempts"
    exit 1
  fi

  echo "apt install attempt ${attempt} failed; recovering and retrying in ${delay}s"
  # Recover potentially-broken dpkg/apt state between attempts.
  sudo dpkg --configure -a || true
  sudo apt-get -f install -y || true
  sleep "${delay}"
  attempt=$((attempt + 1))
  delay=$((delay * 2))
done
