#!/bin/bash
# =============================================================================
# App Test: Send Message
# =============================================================================
# User A sends a message, User B should receive it.
# User B sends a reply, User A should see it.
# =============================================================================

source "$(dirname "$0")/lib.sh"
app_test_setup || exit 1

# --- Test 1: User A sends a message, User B sees it ---
test_start "User A sends message → User B receives it"

# Select channel on both instances
api_a "select_channel" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\"}" > /dev/null
api_b "select_channel" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\"}" > /dev/null
sleep 0.5

# User A sends a message
MSG_CONTENT="Hello from User A $(date +%s)"
SEND_RESULT=$(api_a "send_message" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\",\"content\":\"$MSG_CONTENT\"}")
assert_ok "User A send_message" "$SEND_RESULT"

# User B should see the message (via gateway push)
MESSAGES_B=$(wait_for_message api_b "$GENERAL_CHANNEL_ID" ".content == \"$MSG_CONTENT\"" 10)
assert_jq "User B received message" "$MESSAGES_B" ".messages[]? | select(.content == \"$MSG_CONTENT\")"

# --- Test 2: User B sends a reply, User A sees it ---
test_start "User B sends reply → User A receives it"

REPLY_CONTENT="Reply from User B $(date +%s)"
SEND_REPLY=$(api_b "send_message" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\",\"content\":\"$REPLY_CONTENT\"}")
assert_ok "User B send_message" "$SEND_REPLY"

MESSAGES_A=$(wait_for_message api_a "$GENERAL_CHANNEL_ID" ".content == \"$REPLY_CONTENT\"" 10)
assert_jq "User A received reply" "$MESSAGES_A" ".messages[]? | select(.content == \"$REPLY_CONTENT\")"

# --- Test 3: Edit message ---
test_start "User A edits a message"

# Find User A's message ID
MSG_ID=$(echo "$MESSAGES_A" | jq -r ".messages[] | select(.content == \"$MSG_CONTENT\") | .id")
if [ -n "$MSG_ID" ] && [ "$MSG_ID" != "null" ]; then
    EDITED_CONTENT="Edited by User A $(date +%s)"
    EDIT_RESULT=$(api_a "edit_message" "{\"message_id\":\"$MSG_ID\",\"content\":\"$EDITED_CONTENT\"}")
    assert_ok "User A edit_message" "$EDIT_RESULT"

    # User B should see the edited message
    sleep 2
    MESSAGES_B2=$(api_b "list_messages" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\",\"limit\":20}")
    assert_jq "User B sees edited message" "$MESSAGES_B2" \
        ".messages[]? | select(.id == \"$MSG_ID\") | select(.content == \"$EDITED_CONTENT\")"
else
    err "Could not find message ID for edit test — skipping"
fi

# --- Test 4: Delete message ---
test_start "User A deletes a message"

if [ -n "$MSG_ID" ] && [ "$MSG_ID" != "null" ]; then
    DEL_RESULT=$(api_a "delete_message" "{\"message_id\":\"$MSG_ID\"}")
    assert_ok "User A delete_message" "$DEL_RESULT"

    sleep 2
    MESSAGES_B3=$(api_b "list_messages" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\",\"limit\":20}")
    # Message should no longer be present
    if echo "$MESSAGES_B3" | jq -e ".messages[]? | select(.id == \"$MSG_ID\")" > /dev/null 2>&1; then
        _FAIL_COUNT=$((_FAIL_COUNT + 1))
        err "FAIL: Deleted message still visible to User B"
    else
        _PASS_COUNT=$((_PASS_COUNT + 1))
    fi
else
    err "Could not find message ID for delete test — skipping"
fi

test_summary
