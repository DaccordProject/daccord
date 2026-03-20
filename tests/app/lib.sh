#!/bin/bash
# =============================================================================
# App Test Library — shared helpers for multi-instance Daccord tests
# =============================================================================
# Source this file from test scripts:
#   source "$(dirname "$0")/lib.sh"
#
# Provides:
#   - Two Daccord instances (INSTANCE_A on port 39100, INSTANCE_B on port 39101)
#   - Helper functions: api_a, api_b, seed, login_a, login_b
#   - Assertion helpers: assert_ok, assert_eq, assert_contains
#   - Automatic setup/teardown via app_test_setup / app_test_teardown
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVER_DIR="${ACCORD_SERVER_DIR:-$(cd "$PROJECT_DIR/../accordserver" 2>/dev/null && pwd || echo "")}"
SERVER_LOG="$PROJECT_DIR/test_server.log"

PORT_A="${APP_TEST_PORT_A:-39100}"
PORT_B="${APP_TEST_PORT_B:-39101}"
API_A="http://127.0.0.1:$PORT_A/api"
API_B="http://127.0.0.1:$PORT_B/api"
SERVER_URL="${ACCORD_TEST_URL:-http://127.0.0.1:39099}"

PID_A=""
PID_B=""
SERVER_PID=""
TEST_USERDATA_A="$PROJECT_DIR/.test_userdata_a"
TEST_USERDATA_B="$PROJECT_DIR/.test_userdata_b"

# Seed data (populated by seed/login)
USER_A_ID=""
USER_A_TOKEN=""
USER_B_ID=""
USER_B_TOKEN=""
SPACE_ID=""
GENERAL_CHANNEL_ID=""
TESTING_CHANNEL_ID=""

# Test counters
_PASS_COUNT=0
_FAIL_COUNT=0
_TEST_NAME=""

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

info()   { echo -e "${CYAN}[info]${NC}  $*"; }
ok()     { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()   { echo -e "${YELLOW}[warn]${NC}  $*"; }
err()    { echo -e "${RED}[err]${NC}   $*"; }
header() { echo -e "\n${BOLD}$*${NC}"; }

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

## Call an endpoint on instance A.  Usage: api_a <endpoint> [json_body]
api_a() {
    local endpoint="$1"
    local body="${2:-{}}"
    curl -sf "$API_A/$endpoint" -X POST \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null || echo '{"error":"curl failed"}'
}

## Call an endpoint on instance B.  Usage: api_b <endpoint> [json_body]
api_b() {
    local endpoint="$1"
    local body="${2:-{}}"
    curl -sf "$API_B/$endpoint" -X POST \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null || echo '{"error":"curl failed"}'
}

## Call the AccordServer seed endpoint.  Returns JSON with test data.
seed() {
    curl -sf "$SERVER_URL/test/seed" -X POST \
        -H "Content-Type: application/json" \
        -d '{}' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

## Assert a JSON result has .ok == true
assert_ok() {
    local label="$1"
    local json="$2"
    if echo "$json" | jq -e '.ok == true' > /dev/null 2>&1; then
        _PASS_COUNT=$((_PASS_COUNT + 1))
    else
        _FAIL_COUNT=$((_FAIL_COUNT + 1))
        err "FAIL: $label"
        err "  Got: $json"
    fi
}

## Assert a jq expression evaluates to true
assert_jq() {
    local label="$1"
    local json="$2"
    local expr="$3"
    if echo "$json" | jq -e "$expr" > /dev/null 2>&1; then
        _PASS_COUNT=$((_PASS_COUNT + 1))
    else
        _FAIL_COUNT=$((_FAIL_COUNT + 1))
        err "FAIL: $label — expression: $expr"
        err "  Got: $json"
    fi
}

## Assert two values are equal
assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        _PASS_COUNT=$((_PASS_COUNT + 1))
    else
        _FAIL_COUNT=$((_FAIL_COUNT + 1))
        err "FAIL: $label"
        err "  Expected: $expected"
        err "  Actual:   $actual"
    fi
}

## Assert a string contains a substring
assert_contains() {
    local label="$1"
    local haystack="$2"
    local needle="$3"
    if echo "$haystack" | grep -q "$needle"; then
        _PASS_COUNT=$((_PASS_COUNT + 1))
    else
        _FAIL_COUNT=$((_FAIL_COUNT + 1))
        err "FAIL: $label — '$needle' not found in output"
    fi
}

## Start a named test
test_start() {
    _TEST_NAME="$1"
    info "Test: $_TEST_NAME"
}

## Print test summary and return appropriate exit code
test_summary() {
    echo ""
    if [ $_FAIL_COUNT -gt 0 ]; then
        err "$_FAIL_COUNT failed, $_PASS_COUNT passed"
        return 1
    else
        ok "All $_PASS_COUNT assertions passed"
        return 0
    fi
}

# ---------------------------------------------------------------------------
# Wait/poll helpers
# ---------------------------------------------------------------------------

## Wait for an endpoint to return ok.  Usage: wait_for <api_fn> <endpoint> [body] [timeout_s]
wait_for() {
    local api_fn="$1"
    local endpoint="$2"
    local body="${3:-{}}"
    local timeout="${4:-10}"
    local deadline=$((SECONDS + timeout))
    while [ $SECONDS -lt "$deadline" ]; do
        local result
        result=$($api_fn "$endpoint" "$body")
        if echo "$result" | jq -e '.ok == true' > /dev/null 2>&1; then
            echo "$result"
            return 0
        fi
        sleep 0.5
    done
    echo '{"error":"timeout waiting for '"$endpoint"'"}'
    return 1
}

## Wait until list_messages on an instance contains a message matching a jq filter.
## Usage: wait_for_message <api_fn> <channel_id> <jq_filter> [timeout_s]
wait_for_message() {
    local api_fn="$1"
    local channel_id="$2"
    local filter="$3"
    local timeout="${4:-15}"
    local deadline=$((SECONDS + timeout))
    while [ $SECONDS -lt "$deadline" ]; do
        local result
        result=$($api_fn "list_messages" "{\"channel_id\":\"$channel_id\",\"limit\":20}")
        if echo "$result" | jq -e ".messages[]? | select($filter)" > /dev/null 2>&1; then
            echo "$result"
            return 0
        fi
        sleep 0.5
    done
    echo '{"error":"timeout waiting for message matching: '"$filter"'"}'
    return 1
}

# ---------------------------------------------------------------------------
# Server management
# ---------------------------------------------------------------------------

start_server() {
    if curl -sf "$SERVER_URL/api/v1/gateway" > /dev/null 2>&1; then
        warn "Server already running on $SERVER_URL — using existing instance"
        return 0
    fi

    if [ -z "$SERVER_DIR" ] || [ ! -d "$SERVER_DIR" ]; then
        err "AccordServer not found. Set ACCORD_SERVER_DIR or clone to ../accordserver"
        return 1
    fi

    header "Starting AccordServer in test mode..."
    info "Building AccordServer..."
    (cd "$SERVER_DIR" && cargo build --bin accordserver --features test-seed --quiet 2>&1) || {
        err "Failed to build AccordServer"
        return 1
    }

    # Clean stale test database
    rm -f "$SERVER_DIR/accord_test.db" \
          "$SERVER_DIR/accord_test.db-shm" \
          "$SERVER_DIR/accord_test.db-wal"

    ACCORD_TEST_MODE=true \
    DATABASE_URL="sqlite:accord_test.db?mode=rwc" \
    RUST_LOG="accordserver=debug,tower_http=info" \
        cargo run --quiet --bin accordserver --features test-seed \
        --manifest-path "$SERVER_DIR/Cargo.toml" \
        > "$SERVER_LOG" 2>&1 &
    SERVER_PID=$!

    info "Waiting for server on $SERVER_URL..."
    local retries=0
    while ! curl -sf "$SERVER_URL/api/v1/gateway" > /dev/null 2>&1; do
        retries=$((retries + 1))
        if [ $retries -ge 30 ]; then
            err "Server failed to start within 30s"
            tail -20 "$SERVER_LOG" | sed 's/^/  /'
            return 1
        fi
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            err "Server process exited early"
            tail -20 "$SERVER_LOG" | sed 's/^/  /'
            return 1
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
    fi
}

# ---------------------------------------------------------------------------
# Instance management
# ---------------------------------------------------------------------------

_setup_userdata() {
    local dir="$1"
    rm -rf "$dir"
    case "$(uname)" in
        Darwin)
            mkdir -p "$dir/Library/Application Support/Godot/app_userdata/daccord/logs"
            ;;
        *)
            mkdir -p "$dir/godot/app_userdata/daccord/logs"
            ;;
    esac
}

start_instance() {
    local port="$1"
    local userdata_dir="$2"
    local profile="${3:-default}"

    _setup_userdata "$userdata_dir"

    local env_prefix=""
    case "$(uname)" in
        Darwin) env_prefix="HOME=$userdata_dir" ;;
        *)      env_prefix="XDG_DATA_HOME=$userdata_dir" ;;
    esac

    local headless_flag="--headless"
    if [ "${APP_TEST_VISIBLE:-}" = "true" ]; then
        headless_flag=""
    fi

    env $env_prefix godot $headless_flag \
        --test-api --test-api-port "$port" --test-api-no-auth \
        --profile "$profile" \
        --path "$PROJECT_DIR" &
    local pid=$!

    # Wait for test API to be ready
    local api_url="http://127.0.0.1:$port/api"
    local retries=0
    while ! curl -sf "$api_url/get_state" -X POST -d '{}' > /dev/null 2>&1; do
        retries=$((retries + 1))
        if [ $retries -ge 30 ]; then
            err "Instance on port $port failed to start within 30s"
            return 1
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            err "Instance on port $port exited early"
            return 1
        fi
        sleep 1
    done
    echo "$pid"
}

stop_instance() {
    local pid="$1"
    local port="$2"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        # Try graceful quit
        curl -sf "http://127.0.0.1:$port/api/quit" -X POST -d '{}' > /dev/null 2>&1 || true
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        wait "$pid" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Full setup / teardown for two-instance tests
# ---------------------------------------------------------------------------

app_test_setup() {
    header "App Test Setup"

    # Start server if needed
    start_server || return 1

    # Seed test data (two separate seeds = two users, same space)
    info "Seeding test data..."
    local seed_a
    seed_a=$(seed)
    if [ -z "$seed_a" ] || ! echo "$seed_a" | jq -e '.data' > /dev/null 2>&1; then
        err "Failed to seed test data (user A)"
        return 1
    fi

    local seed_b
    seed_b=$(seed)
    if [ -z "$seed_b" ] || ! echo "$seed_b" | jq -e '.data' > /dev/null 2>&1; then
        err "Failed to seed test data (user B)"
        return 1
    fi

    # Extract seed data
    USER_A_ID=$(echo "$seed_a" | jq -r '.data.user.id')
    USER_A_TOKEN=$(echo "$seed_a" | jq -r '.data.user.token')
    USER_B_ID=$(echo "$seed_b" | jq -r '.data.user.id')
    USER_B_TOKEN=$(echo "$seed_b" | jq -r '.data.user.token')

    # Both seeds create the same space structure
    SPACE_ID=$(echo "$seed_a" | jq -r '.data.space.id')
    GENERAL_CHANNEL_ID=$(echo "$seed_a" | jq -r '.data.channels[] | select(.name=="general") | .id')
    TESTING_CHANNEL_ID=$(echo "$seed_a" | jq -r '.data.channels[] | select(.name=="testing") | .id')

    ok "Seed complete: User A=$USER_A_ID, User B=$USER_B_ID, Space=$SPACE_ID"

    # Start two Daccord instances
    info "Starting instance A on port $PORT_A..."
    PID_A=$(start_instance "$PORT_A" "$TEST_USERDATA_A" "test_a") || return 1
    ok "Instance A ready (PID $PID_A)"

    info "Starting instance B on port $PORT_B..."
    PID_B=$(start_instance "$PORT_B" "$TEST_USERDATA_B" "test_b") || return 1
    ok "Instance B ready (PID $PID_B)"

    # Log in user A on instance A using seed token
    info "Logging in User A on instance A..."
    local login_a_result
    login_a_result=$(api_a "login" "{
        \"base_url\": \"$SERVER_URL\",
        \"token\": \"$USER_A_TOKEN\"
    }")
    if ! echo "$login_a_result" | jq -e '.ok == true' > /dev/null 2>&1; then
        err "Login failed for User A: $login_a_result"
        return 1
    fi
    SPACE_ID=$(echo "$login_a_result" | jq -r '.space_id // empty')
    ok "User A logged in (space: $SPACE_ID)"

    # Log in user B on instance B using seed token
    info "Logging in User B on instance B..."
    local login_b_result
    login_b_result=$(api_b "login" "{
        \"base_url\": \"$SERVER_URL\",
        \"token\": \"$USER_B_TOKEN\"
    }")
    if ! echo "$login_b_result" | jq -e '.ok == true' > /dev/null 2>&1; then
        err "Login failed for User B: $login_b_result"
        return 1
    fi
    ok "User B logged in (space: $(echo "$login_b_result" | jq -r '.space_id // empty'))"

    # Fetch channel IDs from instance A (now connected)
    if [ -n "$SPACE_ID" ]; then
        info "Fetching channels..."
        sleep 1  # Allow gateway to sync
        local channels_result
        channels_result=$(api_a "list_channels" "{\"space_id\":\"$SPACE_ID\"}")
        if echo "$channels_result" | jq -e '.ok == true' > /dev/null 2>&1; then
            GENERAL_CHANNEL_ID=$(echo "$channels_result" | jq -r '.channels[] | select(.name=="general") | .id // empty')
            TESTING_CHANNEL_ID=$(echo "$channels_result" | jq -r '.channels[] | select(.name=="testing") | .id // empty')
            # If no named channels, use the first one
            if [ -z "$GENERAL_CHANNEL_ID" ]; then
                GENERAL_CHANNEL_ID=$(echo "$channels_result" | jq -r '.channels[0].id // empty')
            fi
            ok "Channels: general=$GENERAL_CHANNEL_ID testing=$TESTING_CHANNEL_ID"
        fi
    fi

    ok "Setup complete — both instances running"
}

app_test_teardown() {
    header "App Test Teardown"
    stop_instance "$PID_A" "$PORT_A" 2>/dev/null || true
    stop_instance "$PID_B" "$PORT_B" 2>/dev/null || true
    stop_server 2>/dev/null || true
    rm -rf "$TEST_USERDATA_A" "$TEST_USERDATA_B"
    ok "Teardown complete"
}

# Auto-teardown on exit
trap app_test_teardown EXIT INT TERM
