#!/bin/bash
# Test state endpoints: get_state, list_spaces, list_channels
set -euo pipefail

API="${CLIENT_API_URL:-http://localhost:39100/api}"

# get_state should return ok
STATE=$(curl -sf "$API/get_state" -X POST -d '{}')
echo "$STATE" | jq -e '.ok == true' > /dev/null || { echo "FAIL: get_state not ok"; exit 1; }
echo "$STATE" | jq -e 'has("space_id")' > /dev/null || { echo "FAIL: missing space_id"; exit 1; }
echo "$STATE" | jq -e 'has("layout_mode")' > /dev/null || { echo "FAIL: missing layout_mode"; exit 1; }
echo "$STATE" | jq -e 'has("user_id")' > /dev/null || { echo "FAIL: missing user_id"; exit 1; }

# list_spaces
SPACES=$(curl -sf "$API/list_spaces" -X POST -d '{}')
echo "$SPACES" | jq -e '.ok == true' > /dev/null || { echo "FAIL: list_spaces not ok"; exit 1; }
echo "$SPACES" | jq -e '.spaces | type == "array"' > /dev/null || { echo "FAIL: spaces not array"; exit 1; }

# If we have spaces, test list_channels
SPACE_COUNT=$(echo "$SPACES" | jq '.spaces | length')
if [ "$SPACE_COUNT" -gt 0 ]; then
    SPACE_ID=$(echo "$SPACES" | jq -r '.spaces[0].id')

    CHANNELS=$(curl -sf "$API/list_channels" -X POST -d "{\"space_id\": \"$SPACE_ID\"}")
    echo "$CHANNELS" | jq -e '.ok == true' > /dev/null || { echo "FAIL: list_channels not ok"; exit 1; }
    echo "$CHANNELS" | jq -e '.channels | type == "array"' > /dev/null || { echo "FAIL: channels not array"; exit 1; }

    # list_members
    MEMBERS=$(curl -sf "$API/list_members" -X POST -d "{\"space_id\": \"$SPACE_ID\"}")
    echo "$MEMBERS" | jq -e '.ok == true' > /dev/null || { echo "FAIL: list_members not ok"; exit 1; }
fi

echo "PASS: state endpoints"
