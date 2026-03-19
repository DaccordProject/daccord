#!/bin/bash
# Test lifecycle and error handling endpoints
set -euo pipefail

API="${CLIENT_API_URL:-http://localhost:39100/api}"

# wait_frames
RESULT=$(curl -sf "$API/wait_frames" -X POST -d '{"count": 2}')
echo "$RESULT" | jq -e '.ok == true' > /dev/null || { echo "FAIL: wait_frames not ok"; exit 1; }
echo "$RESULT" | jq -e '.frames_waited == 2' > /dev/null || { echo "FAIL: wrong frame count"; exit 1; }

# Unknown endpoint should return error
RESULT=$(curl -s "$API/nonexistent_endpoint" -X POST -d '{}')
echo "$RESULT" | jq -e 'has("error")' > /dev/null || { echo "FAIL: expected error for unknown endpoint"; exit 1; }

# Missing required params
RESULT=$(curl -s "$API/select_channel" -X POST -d '{}')
echo "$RESULT" | jq -e 'has("error")' > /dev/null || { echo "FAIL: expected error for missing channel_id"; exit 1; }

# list_surfaces
RESULT=$(curl -sf "$API/list_surfaces" -X POST -d '{}')
echo "$RESULT" | jq -e '.ok == true' > /dev/null || { echo "FAIL: list_surfaces not ok"; exit 1; }

# set_viewport_size with preset
RESULT=$(curl -sf "$API/set_viewport_size" -X POST -d '{"preset": "full"}')
echo "$RESULT" | jq -e '.ok == true' > /dev/null || { echo "FAIL: set_viewport_size not ok"; exit 1; }

echo "PASS: lifecycle and error handling"
