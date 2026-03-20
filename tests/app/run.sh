#!/bin/bash
# =============================================================================
# App Test Runner — runs multi-instance Daccord integration tests
# =============================================================================
# Usage:
#   ./tests/app/run.sh                   Run all app tests
#   ./tests/app/run.sh test_messages     Run a specific test
#   APP_TEST_VISIBLE=true ./tests/app/run.sh   Run non-headless (see the UI)
#
# Environment variables:
#   ACCORD_TEST_URL       Use a remote server (default: http://127.0.0.1:39099)
#   ACCORD_SERVER_DIR     Path to accordserver checkout (default: ../accordserver)
#   APP_TEST_PORT_A       Port for instance A (default: 39100)
#   APP_TEST_PORT_B       Port for instance B (default: 39101)
#   APP_TEST_VISIBLE      Set to "true" to run without --headless
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()   { echo -e "${CYAN}[info]${NC}  $*"; }
ok()     { echo -e "${GREEN}[ok]${NC}    $*"; }
err()    { echo -e "${RED}[err]${NC}   $*"; }
header() { echo -e "\n${BOLD}$*${NC}"; }

header "Daccord App Test Runner"
echo ""

# Find test scripts
FILTER="${1:-}"
TEST_SCRIPTS=()
for f in "$SCRIPT_DIR"/test_*.sh; do
    [ -f "$f" ] || continue
    if [ -n "$FILTER" ]; then
        basename_f="$(basename "$f" .sh)"
        if [[ "$basename_f" != *"$FILTER"* ]]; then
            continue
        fi
    fi
    TEST_SCRIPTS+=("$f")
done

if [ ${#TEST_SCRIPTS[@]} -eq 0 ]; then
    err "No test scripts found${FILTER:+ matching '$FILTER'}"
    exit 1
fi

info "Found ${#TEST_SCRIPTS[@]} test script(s)"
for f in "${TEST_SCRIPTS[@]}"; do
    info "  $(basename "$f")"
done

TOTAL_PASS=0
TOTAL_FAIL=0

for test_script in "${TEST_SCRIPTS[@]}"; do
    test_name="$(basename "$test_script" .sh)"
    header "Running: $test_name"
    echo ""

    if bash "$test_script"; then
        ok "PASS: $test_name"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        err "FAIL: $test_name"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    echo ""
done

header "Results"
echo ""
if [ $TOTAL_FAIL -gt 0 ]; then
    err "$TOTAL_FAIL failed, $TOTAL_PASS passed out of $((TOTAL_PASS + TOTAL_FAIL)) test(s)"
    exit 1
else
    ok "All $TOTAL_PASS test(s) passed"
fi
