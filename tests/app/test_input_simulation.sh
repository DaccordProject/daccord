#!/bin/bash
# =============================================================================
# App Test: Input Simulation
# =============================================================================
# Tests the simulate_click, simulate_key, simulate_text, and
# simulate_mouse_move endpoints.
# =============================================================================

source "$(dirname "$0")/lib.sh"
app_test_setup || exit 1

# --- Test 1: Simulate mouse move ---
test_start "Simulate mouse move"

MOVE_RESULT=$(api_a "simulate_mouse_move" '{"x": 100, "y": 200}')
assert_ok "simulate_mouse_move" "$MOVE_RESULT"
assert_jq "returns coordinates" "$MOVE_RESULT" '.x == 100 and .y == 200'

# --- Test 2: Simulate click ---
test_start "Simulate mouse click"

CLICK_RESULT=$(api_a "simulate_click" '{"x": 100, "y": 200}')
assert_ok "simulate_click" "$CLICK_RESULT"
assert_jq "returns click info" "$CLICK_RESULT" '.x == 100 and .y == 200'

# --- Test 3: Simulate double click ---
test_start "Simulate double click"

DBLCLICK_RESULT=$(api_a "simulate_click" '{"x": 150, "y": 250, "double_click": true}')
assert_ok "simulate_click double" "$DBLCLICK_RESULT"

# --- Test 4: Simulate key press ---
test_start "Simulate key press (escape)"

KEY_RESULT=$(api_a "simulate_key" '{"key": "escape"}')
assert_ok "simulate_key escape" "$KEY_RESULT"
assert_jq "returns key name" "$KEY_RESULT" '.key == "escape"'

# --- Test 5: Simulate key with modifiers ---
test_start "Simulate key with Ctrl modifier"

CTRL_KEY=$(api_a "simulate_key" '{"key": "a", "ctrl": true}')
assert_ok "simulate_key ctrl+a" "$CTRL_KEY"

# --- Test 6: Simulate text input ---
test_start "Simulate text input"

TEXT_RESULT=$(api_a "simulate_text" '{"text": "Hello World"}')
assert_ok "simulate_text" "$TEXT_RESULT"
assert_jq "returns text length" "$TEXT_RESULT" '.length == 11'

# --- Test 7: Invalid key returns error ---
test_start "Invalid key returns error"

BAD_KEY=$(api_a "simulate_key" '{"key": "nonexistent_key_name"}')
assert_jq "error returned for bad key" "$BAD_KEY" 'has("error")'

# --- Test 8: Missing coordinates returns error ---
test_start "Missing coordinates returns error"

BAD_CLICK=$(api_a "simulate_click" '{}')
assert_jq "error returned for missing coords" "$BAD_CLICK" 'has("error")'

test_summary
