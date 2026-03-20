#!/bin/bash
# =============================================================================
# App Test: Emoji Reactions
# =============================================================================
# User A sends a message, User B reacts to it.
# Verify the reaction is visible on User A's instance.
# =============================================================================

source "$(dirname "$0")/lib.sh"
app_test_setup || exit 1

# Select channel on both instances
api_a "select_channel" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\"}" > /dev/null
api_b "select_channel" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\"}" > /dev/null
sleep 0.5

# --- Test 1: User A sends a message ---
test_start "User A sends a message for reactions"

MSG_CONTENT="React to this $(date +%s)"
SEND_RESULT=$(api_a "send_message" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\",\"content\":\"$MSG_CONTENT\"}")
assert_ok "User A send_message" "$SEND_RESULT"

# Wait for User B to receive it
MESSAGES_B=$(wait_for_message api_b "$GENERAL_CHANNEL_ID" ".content == \"$MSG_CONTENT\"" 10)
MSG_ID=$(echo "$MESSAGES_B" | jq -r ".messages[] | select(.content == \"$MSG_CONTENT\") | .id")
assert_jq "Message has ID" "$MESSAGES_B" ".messages[] | select(.content == \"$MSG_CONTENT\") | .id"

# --- Test 2: User B adds a reaction ---
test_start "User B adds thumbsup reaction"

if [ -n "$MSG_ID" ] && [ "$MSG_ID" != "null" ]; then
    REACT_RESULT=$(api_b "add_reaction" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\",\"message_id\":\"$MSG_ID\",\"emoji\":\"thumbsup\"}")
    assert_ok "User B add_reaction" "$REACT_RESULT"

    # Verify reaction appears on User A's side
    sleep 2
    MESSAGES_A=$(api_a "list_messages" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\",\"limit\":20}")
    # Check the message has reactions
    assert_jq "User A sees reaction on message" "$MESSAGES_A" \
        ".messages[] | select(.id == \"$MSG_ID\") | .reactions | length > 0"
else
    err "No message ID — skipping reaction tests"
fi

# --- Test 3: User A also reacts ---
test_start "User A adds heart reaction"

if [ -n "$MSG_ID" ] && [ "$MSG_ID" != "null" ]; then
    REACT_A=$(api_a "add_reaction" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\",\"message_id\":\"$MSG_ID\",\"emoji\":\"heart\"}")
    assert_ok "User A add_reaction heart" "$REACT_A"

    sleep 2
    MESSAGES_B2=$(api_b "list_messages" "{\"channel_id\":\"$GENERAL_CHANNEL_ID\",\"limit\":20}")
    assert_jq "User B sees multiple reactions" "$MESSAGES_B2" \
        ".messages[] | select(.id == \"$MSG_ID\") | .reactions | length >= 2"
fi

test_summary
