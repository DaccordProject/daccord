# Client Test API

Priority: 79
Depends on: Test Coverage
Status: Complete

Local HTTP/JSON server embedded in the running client for programmatic state reading, UI navigation, action execution, and screenshot capture. Activated via `--test-api` CLI flag or Developer Mode settings. The MCP server wraps this as a protocol adapter.

## Key Files

| File | Role |
|------|------|
| `scripts/client/client_test_api.gd` | Core subsystem — TCP listener, HTTP parsing, request routing, auth, rate limiting (39+ endpoints) |
| `scripts/client/client_test_api_state.gd` | State, screenshot, and theme endpoint handlers (read-only queries + viewport capture) |
| `scripts/client/client_test_api_actions.gd` | Mutation, moderation, voice, and lifecycle endpoint handlers |
| `scripts/client/client_test_api_navigate.gd` | Navigation helpers — surface catalog (10 sections), dialog map (29 dialogs), viewport presets |
| `scripts/config/config_developer.gd` | Developer Mode config helper — CLI flag parsing, test API/MCP enable checks |
| `scenes/user/app_settings_developer_page.gd` | Developer settings UI — test API toggle/port/token, MCP toggle/port/token/groups |
| `scenes/user/app_settings_about_page.gd` | About page — Developer Mode toggle in ADVANCED section (line 88) |
| `scripts/autoload/client.gd` | Parent — initializes test_api (line 247), polls in `_process()` (line 287), stops on shutdown (line 313) |
| `scripts/autoload/error_reporting.gd` | PII scrubbing — covers `dk_` tokens (line 44) and Bearer tokens (line 37) |
| `tests/unit/test_client_test_api.gd` | GUT unit tests: request parsing, auth, rate limiting, routing (25 tests) |
| `tests/client_api/` | Bash integration tests: state, navigation, lifecycle (3 scripts) |
| `test.sh` | Test runner — `client` suite starts Daccord with `--test-api` and runs bash tests |
| `.github/workflows/ci.yml` | CI — client API bash tests in integration-test job (line 354) |
