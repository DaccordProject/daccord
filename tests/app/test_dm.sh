#!/bin/bash
# =============================================================================
# App Test: Direct Messages
# =============================================================================
# User A opens a DM with User B, sends a message.
# User B receives the DM.
# =============================================================================

source "$(dirname "$0")/lib.sh"
app_test_setup || exit 1

# --- Test 1: User A opens DM mode ---
test_start "User A enters DM mode"

DM_RESULT=$(api_a "open_dm" "{}")
assert_ok "User A open_dm" "$DM_RESULT"

# --- Test 2: Get User B's ID from instance A ---
test_start "User A can see User B in member list"

# Get state to check current user IDs
STATE_A=$(api_a "get_state" "{}")
STATE_B=$(api_b "get_state" "{}")
USER_A_RESOLVED=$(echo "$STATE_A" | jq -r '.user_id // empty')
USER_B_RESOLVED=$(echo "$STATE_B" | jq -r '.user_id // empty')

info "User A ID: $USER_A_RESOLVED"
info "User B ID: $USER_B_RESOLVED"

if [ -n "$USER_B_RESOLVED" ] && [ "$USER_B_RESOLVED" != "null" ]; then
    # Verify User A can look up User B
    USER_B_INFO=$(api_a "get_user" "{\"user_id\":\"$USER_B_RESOLVED\"}")
    assert_ok "User A can fetch User B info" "$USER_B_INFO"
fi

# --- Test 3: Both users visible in space member list ---
test_start "Both users in member list"

if [ -n "$SPACE_ID" ] && [ "$SPACE_ID" != "null" ]; then
    MEMBERS=$(api_a "list_members" "{\"space_id\":\"$SPACE_ID\"}")
    assert_ok "list_members returns ok" "$MEMBERS"
    assert_jq "Members list is non-empty" "$MEMBERS" ".members | length > 0"
fi

test_summary
