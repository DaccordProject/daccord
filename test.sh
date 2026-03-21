#!/bin/bash

# =============================================================================
# daccord Test Runner
# =============================================================================
# Starts AccordServer in test mode, runs GUT tests, and tears down the server.
# Server logs are written to a file and can be tailed in a separate terminal.
#
# Usage:
#   ./test.sh              Run all tests (excludes gateway -- needs non-headless)
#   ./test.sh unit         Run only unit tests (no server needed)
#   ./test.sh integration  Run AccordKit unit + REST integration tests
#   ./test.sh accordkit    Run only AccordKit unit + REST tests
#   ./test.sh gateway      Run gateway/e2e tests (requires non-headless Godot)
#   ./test.sh livekit      Run only LiveKit adapter tests (no server needed)
#   ./test.sh sync         Run daccord-sync integration tests (requires Docker on port 3001)
#   ./test.sh client       Run Client API integration tests (starts Daccord with --test-api)
#
# Extra arguments after the suite name are passed to GUT as -gselect filters:
#   ./test.sh unit test_emoji_picker       Run only test_emoji_picker.gd
#   ./test.sh unit test_emoji,test_config  Run tests matching either prefix
#
# Environment variables:
#   ACCORD_TEST_URL        Run against a remote server instead of starting one
#                          locally. The server must have ACCORD_TEST_MODE=true.
#                          Example: ACCORD_TEST_URL=http://192.168.1.144:39099 ./test.sh accordkit
#
# Server logs are written to: test_server.log
# Tail them with: tail -f test_server.log
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/../accordserver"
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

setup_godot_user_dir() {
    local test_data="$SCRIPT_DIR/.test_userdata"
    case "$(uname)" in
        Darwin)
            # macOS: Godot uses ~/Library/Application Support/Godot/app_userdata/
            # Override HOME so it writes to an isolated directory instead
            export HOME="$test_data"
            mkdir -p "$HOME/Library/Application Support/Godot/app_userdata/daccord/logs"
            ;;
        *)
            # Linux: Godot respects XDG_DATA_HOME
            export XDG_DATA_HOME="$test_data"
            mkdir -p "$XDG_DATA_HOME/godot/app_userdata/daccord/logs"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Determine which test dirs to run
# ---------------------------------------------------------------------------
GUT_SELECT=""

resolve_dirs() {
    # Extra positional args after suite name become -gselect filter
    if [ -n "${2:-}" ]; then
        GUT_SELECT="$2"
    fi
    case "${1:-all}" in
        unit)
            NEEDS_SERVER=false
            GUT_DIRS="res://tests/unit"
            ;;
        integration)
            NEEDS_SERVER=true
            GUT_DIRS="res://tests/accordkit/unit,res://tests/accordkit/integration"
            ;;
        accordkit)
            NEEDS_SERVER=true
            GUT_DIRS="res://tests/accordkit/unit,res://tests/accordkit/integration"
            ;;
        gateway)
            NEEDS_SERVER=true
            GUT_DIRS="res://tests/accordkit/gateway,res://tests/accordkit/e2e"
            ;;
        livekit)
            NEEDS_SERVER=false
            GUT_DIRS="res://tests/livekit"
            ;;
        sync)
            NEEDS_SERVER=false
            GUT_DIRS="res://tests/integration"
            ;;
        client)
            NEEDS_SERVER=true
            CLIENT_API_SUITE=true
            GUT_DIRS=""
            ;;
        all)
            NEEDS_SERVER=true
            GUT_DIRS="res://tests/unit,res://tests/accordkit/unit,res://tests/accordkit/integration,res://tests/livekit"
            ;;
        *)
            err "Unknown suite: $1"
            echo "Usage: $0 [unit|integration|accordkit|gateway|livekit|sync|client|all]"
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
    (cd "$SERVER_DIR" && cargo build --bin accordserver --features test-seed --quiet 2>&1) || {
        err "Failed to build AccordServer"
        exit 1
    }
    ok "Build complete"

    # Remove stale test database so each run starts fresh
    # cargo run uses CWD for relative DATABASE_URL, so clean both locations
    rm -f "$SERVER_DIR/accord_test.db" \
          "$SERVER_DIR/accord_test.db-shm" \
          "$SERVER_DIR/accord_test.db-wal"
    rm -f "accord_test.db" \
          "accord_test.db-shm" \
          "accord_test.db-wal"

    # Start server in background, logging to file
    info "Server log: $SERVER_LOG"
    info "Tail it with: ${DIM}tail -f $SERVER_LOG${NC}"

    ACCORD_TEST_MODE=true \
    DATABASE_URL="sqlite:accord_test.db?mode=rwc" \
    RUST_LOG="accordserver=debug,tower_http=info" \
        cargo run --quiet --bin accordserver --features test-seed --manifest-path "$SERVER_DIR/Cargo.toml" \
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
    stop_daccord 2>/dev/null || true
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
    local select_flag=""
    if [ -n "$GUT_SELECT" ]; then
        select_flag="-gselect=$GUT_SELECT"
    fi
    local godot_cmd="godot --headless -s addons/gut/gut_cmdln.gd \
        -gexit \
        -ginclude_subdirs=true \
        -gprefix=test_ \
        -gsuffix=.gd \
        -glog=1 \
        -gdir=$dir \
        $select_flag"

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
# Client API test runner
# ---------------------------------------------------------------------------
DACCORD_PID=""
CLIENT_API_SUITE="${CLIENT_API_SUITE:-false}"
CLIENT_API_PORT="${DACCORD_TEST_API_PORT:-39100}"
CLIENT_API_URL="http://127.0.0.1:$CLIENT_API_PORT/api"

start_daccord() {
    header "Starting Daccord with --test-api..."
    local headless_flag="--headless"
    if [ "${DACCORD_SCREENSHOTS:-}" = "true" ]; then
        headless_flag=""
    fi

    godot $headless_flag --test-api --test-api-port "$CLIENT_API_PORT" --test-api-no-auth &
    DACCORD_PID=$!
    info "Daccord PID: $DACCORD_PID"

    # Wait for test API to become ready
    info "Waiting for test API on :$CLIENT_API_PORT..."
    local retries=0
    local max_retries=30
    while ! curl -sf "$CLIENT_API_URL/get_state" > /dev/null 2>&1; do
        retries=$((retries + 1))
        if [ $retries -ge $max_retries ]; then
            err "Test API failed to start within ${max_retries}s"
            stop_daccord
            return 1
        fi
        if ! kill -0 "$DACCORD_PID" 2>/dev/null; then
            err "Daccord process exited early"
            return 1
        fi
        sleep 1
    done
    ok "Test API is ready"
}

stop_daccord() {
    if [ -n "$DACCORD_PID" ] && kill -0 "$DACCORD_PID" 2>/dev/null; then
        info "Stopping Daccord (PID $DACCORD_PID)..."
        # Try graceful quit via API first
        curl -sf "$CLIENT_API_URL/quit" -X POST -d '{}' > /dev/null 2>&1 || true
        sleep 1
        if kill -0 "$DACCORD_PID" 2>/dev/null; then
            kill "$DACCORD_PID" 2>/dev/null || true
        fi
        wait "$DACCORD_PID" 2>/dev/null || true
        ok "Daccord stopped"
    fi
}

run_client_api_tests() {
    header "Running Client API tests..."

    start_daccord || return 1

    local test_dir="$SCRIPT_DIR/tests/client_api"
    if [ ! -d "$test_dir" ]; then
        err "Test directory not found: $test_dir"
        stop_daccord
        return 1
    fi

    local failed=0
    for test_script in "$test_dir"/test_*.sh; do
        if [ ! -f "$test_script" ]; then
            continue
        fi
        local test_name
        test_name="$(basename "$test_script")"
        info "Running: $test_name"
        if bash "$test_script"; then
            ok "PASS: $test_name"
        else
            err "FAIL: $test_name"
            failed=$((failed + 1))
        fi
    done

    stop_daccord

    if [ $failed -gt 0 ]; then
        err "$failed test(s) failed"
        return 1
    fi
    ok "All client API tests passed"
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

    resolve_dirs "${1:-all}" "${2:-}"
    setup_godot_user_dir

    if [ "$NEEDS_SERVER" = true ]; then
        if [ -n "${ACCORD_TEST_URL:-}" ]; then
            info "Using remote server: $ACCORD_TEST_URL"
            export ACCORD_TEST_URL
            if curl -sf "${ACCORD_TEST_URL}/api/v1/gateway" > /dev/null 2>&1; then
                ok "Remote server is reachable"
            else
                err "Remote server at $ACCORD_TEST_URL is not reachable"
                exit 1
            fi
        # Check if server is already running
        elif curl -sf http://127.0.0.1:39099/api/v1/gateway > /dev/null 2>&1; then
            warn "Server already running on :39099 -- using existing instance"
            info "Server logs will be wherever that instance logs to"
        else
            start_server
        fi
    else
        info "Skipping server (not needed for this suite)"
    fi

    if [ "$CLIENT_API_SUITE" = true ]; then
        run_client_api_tests || EXIT_CODE=$?
    else
        run_tests
    fi

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
