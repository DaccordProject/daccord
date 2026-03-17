#!/bin/bash
# Test navigation endpoints: select_space, select_channel, toggle_member_list
set -euo pipefail

API="${CLIENT_API_URL:-http://localhost:39100/api}"

# Get initial state
SPACES=$(curl -sf "$API/list_spaces" -X POST -d '{}')
SPACE_COUNT=$(echo "$SPACES" | jq '.spaces | length')

if [ "$SPACE_COUNT" -eq 0 ]; then
    echo "SKIP: no spaces available for navigation test"
    exit 0
fi

SPACE_ID=$(echo "$SPACES" | jq -r '.spaces[0].id')

# Select space
RESULT=$(curl -sf "$API/select_space" -X POST -d "{\"space_id\": \"$SPACE_ID\"}")
echo "$RESULT" | jq -e '.ok == true' > /dev/null || { echo "FAIL: select_space not ok"; exit 1; }

# Verify state updated
STATE=$(curl -sf "$API/get_state" -X POST -d '{}')
echo "$STATE" | jq -e ".space_id == \"$SPACE_ID\"" > /dev/null || { echo "FAIL: space_id not updated"; exit 1; }

# Get channels and select one
CHANNELS=$(curl -sf "$API/list_channels" -X POST -d "{\"space_id\": \"$SPACE_ID\"}")
CH_COUNT=$(echo "$CHANNELS" | jq '.channels | length')

if [ "$CH_COUNT" -gt 0 ]; then
    CHANNEL_ID=$(echo "$CHANNELS" | jq -r '.channels[0].id')
    RESULT=$(curl -sf "$API/select_channel" -X POST -d "{\"channel_id\": \"$CHANNEL_ID\"}")
    echo "$RESULT" | jq -e '.ok == true' > /dev/null || { echo "FAIL: select_channel not ok"; exit 1; }

    STATE=$(curl -sf "$API/get_state" -X POST -d '{}')
    echo "$STATE" | jq -e ".channel_id == \"$CHANNEL_ID\"" > /dev/null || { echo "FAIL: channel_id not updated"; exit 1; }
fi

# Toggle member list
RESULT=$(curl -sf "$API/toggle_member_list" -X POST -d '{}')
echo "$RESULT" | jq -e '.ok == true' > /dev/null || { echo "FAIL: toggle_member_list not ok"; exit 1; }

# Toggle search
RESULT=$(curl -sf "$API/toggle_search" -X POST -d '{}')
echo "$RESULT" | jq -e '.ok == true' > /dev/null || { echo "FAIL: toggle_search not ok"; exit 1; }

# Error case: select nonexistent space
RESULT=$(curl -sf "$API/select_space" -X POST -d '{"space_id": "nonexistent_999"}')
echo "$RESULT" | jq -e 'has("error")' > /dev/null || { echo "FAIL: expected error for bad space_id"; exit 1; }

echo "PASS: navigation endpoints"
