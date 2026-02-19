#!/bin/bash

# =============================================================================
# daccord Test Runner
# =============================================================================
# Starts AccordServer in test mode, runs GUT tests, and tears down the server.
# Server logs are written to a file and can be tailed in a separate terminal.
#
# Usage:
#   ./test.sh              Run all tests
#   ./test.sh unit         Run only unit tests (no server needed)
#   ./test.sh integration  Run AccordKit + AccordStream integration/e2e tests
#   ./test.sh accordkit    Run only AccordKit tests
#   ./test.sh accordstream Run only AccordStream tests
#
# Server logs are written to: test_server.log
# Tail them with: tail -f test_server.log
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../accordserver" && pwd)"
SERVER_LOG="$SCRIPT_DIR/test_server.log"
SERVER_PID=""
EXIT_CODE=0

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[info]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
err()     { echo -e "${RED}[err]${NC}   $*"; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

# ---------------------------------------------------------------------------
# Determine which test dirs to run
# ---------------------------------------------------------------------------
resolve_dirs() {
    case "${1:-all}" in
        unit)
            NEEDS_SERVER=false
            GUT_DIRS="res://tests/unit"
            ;;
        integration)
            NEEDS_SERVER=true
            GUT_DIRS="res://tests/accordkit,res://tests/accordstream"
            ;;
        accordkit)
            NEEDS_SERVER=true
            GUT_DIRS="res://tests/accordkit"
            ;;
        accordstream)
            NEEDS_SERVER=false
            GUT_DIRS="res://tests/accordstream"
            ;;
        all)
            NEEDS_SERVER=true
            GUT_DIRS="res://tests/unit,res://tests/accordkit,res://tests/accordstream"
            ;;
        *)
            err "Unknown suite: $1"
            echo "Usage: $0 [unit|integration|accordkit|accordstream|all]"
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Server management
# ---------------------------------------------------------------------------
start_server() {
    header "Starting AccordServer in test mode..."

    if ! [ -d "$SERVER_DIR" ]; then
        err "AccordServer not found at $SERVER_DIR"
        exit 1
    fi

    # Build first so startup is fast
    info "Building AccordServer..."
    (cd "$SERVER_DIR" && cargo build --quiet 2>&1) || {
        err "Failed to build AccordServer"
        exit 1
    }
    ok "Build complete"

    # Remove stale test database so each run starts fresh
    rm -f "$SERVER_DIR/accord_test.db" \
          "$SERVER_DIR/accord_test.db-shm" \
          "$SERVER_DIR/accord_test.db-wal"

    # Start server in background, logging to file
    info "Server log: $SERVER_LOG"
    info "Tail it with: ${DIM}tail -f $SERVER_LOG${NC}"

    ACCORD_TEST_MODE=true \
    DATABASE_URL="sqlite:accord_test.db?mode=rwc" \
    RUST_LOG="accordserver=debug,tower_http=info" \
        cargo run --quiet --manifest-path "$SERVER_DIR/Cargo.toml" \
        > "$SERVER_LOG" 2>&1 &
    SERVER_PID=$!

    # Wait for the server to become ready
    info "Waiting for server on :39099..."
    local retries=0
    local max_retries=30
    while ! curl -sf http://127.0.0.1:39099/api/v1/gateway > /dev/null 2>&1; do
        retries=$((retries + 1))
        if [ $retries -ge $max_retries ]; then
            err "Server failed to start within ${max_retries}s"
            err "Last 20 lines of server log:"
            tail -20 "$SERVER_LOG" | sed 's/^/  /'
            stop_server
            exit 1
        fi
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            err "Server process exited early"
            err "Last 20 lines of server log:"
            tail -20 "$SERVER_LOG" | sed 's/^/  /'
            exit 1
        fi
        sleep 1
    done
    ok "Server is ready (PID $SERVER_PID)"
}

stop_server() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        info "Stopping AccordServer (PID $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        ok "Server stopped"
    fi
}

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------
cleanup() {
    stop_server
    # Clean up test database
    rm -f "$SERVER_DIR/accord_test.db" \
          "$SERVER_DIR/accord_test.db-shm" \
          "$SERVER_DIR/accord_test.db-wal"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------
run_suite() {
    local dir="$1"
    local godot_cmd="godot --headless -s addons/gut/gut_cmdln.gd \
        -gexit \
        -ginclude_subdirs=true \
        -gprefix=test_ \
        -gsuffix=.gd \
        -glog=1 \
        -gdir=$dir"

    info "Command: ${DIM}$godot_cmd${NC}"
    echo ""

    if eval "$godot_cmd"; then
        ok "Suite passed: $dir"
    else
        EXIT_CODE=$?
        err "Suite failed: $dir (exit code $EXIT_CODE)"
        return 1
    fi
}

run_tests() {
    header "Running GUT tests..."
    info "Dirs: $GUT_DIRS"
    echo ""

    cd "$SCRIPT_DIR"

    IFS=',' read -ra DIRS <<< "$GUT_DIRS"
    for d in "${DIRS[@]}"; do
        header "Suite: $d"
        if ! run_suite "$d"; then
            err "Aborting -- suite $d failed"
            return 1
        fi
        echo ""
    done

    ok "All suites passed"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    header "daccord Test Runner"
    echo ""

    if [ ! -f "$SCRIPT_DIR/project.godot" ]; then
        err "Not in the daccord project root"
        exit 1
    fi

    resolve_dirs "${1:-all}"

    if [ "$NEEDS_SERVER" = true ]; then
        # Check if server is already running
        if curl -sf http://127.0.0.1:39099/api/v1/gateway > /dev/null 2>&1; then
            warn "Server already running on :39099 -- using existing instance"
            info "Server logs will be wherever that instance logs to"
        else
            start_server
        fi
    else
        info "Skipping server (not needed for this suite)"
    fi

    run_tests

    if [ "$NEEDS_SERVER" = true ] && [ -f "$SERVER_LOG" ]; then
        echo ""
        header "Server log summary (last 10 lines):"
        tail -10 "$SERVER_LOG" | sed 's/^/  /'
    fi

    echo ""
    if [ $EXIT_CODE -eq 0 ]; then
        ok "Done"
    else
        err "Done (with failures)"
    fi

    exit $EXIT_CODE
}

main "$@"
