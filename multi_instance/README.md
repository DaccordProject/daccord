# Multi-instance tests

Layer 3 of #217: **two real app processes**, one server. Each client is driven through the Developer Mode MCP server (`lib/features/developer/services/mcp_tools.dart`) — no synthetic input.

```bash
flutter build linux --release          # required, see below
flutter test multi_instance/
```

Plain `flutter test` does not pick these up.

## How an instance is made

`AppInstance.launch` (`support/app_instance.dart`), per instance:

1. Creates a throwaway `HOME` with an XDG layout (isolates Hive boxes between instances and from your real profile).
2. Seeds `accord-settings`: Developer Mode + MCP on, unique `mcpPort`, unique nonempty bearer token, all tool groups enabled (default is only `read`/`navigate`; others 404).
3. Seeds `accord-session` with a token from a layer-1 harness account, so the app starts signed in.
4. Launches the app and waits for MCP to answer.

## Things that cost real time

- **Release, not debug.** A debug bundle launched directly never runs `main()` — no Hive, no MCP server, no error; the window just does nothing. (`flutter test -d linux` works only because the tool injects the entrypoint.) `resolveBinary()` prefers release.
- **`XDG_DOCUMENTS_DIR` doesn't decide the data path.** `getApplicationDocumentsDirectory()` on Linux runs the `xdg-user-dir` executable, ignoring the env var; under a fresh `HOME` without `user-dirs.dirs` it returns `$HOME`, not `$HOME/Documents`. `prepareHome` writes `user-dirs.dirs` and `documentsDirFor` asks `xdg-user-dir` the same way the app does.
- **`select_channel` needs the space selected first**, or it answers "Channel not found". `openChannel` does both.
- **Don't reuse HTTP connections.** A pooled socket the app dropped fails with "Connection closed before full header was received". Each call uses a fresh connection and retries once.

## Adding a scenario

`AppInstance.call(tool, args)` unwraps JSON-RPC `result.content[0].text` and throws on tool errors. After any gateway-crossing action use `callUntil` (polls, times out with the last result).

Tool payloads don't always match REST: `list_members` flattens the member onto the user (`id`, `username`, …) where REST nests `user`.

## Voice

- `two_clients_test.dart` is the cheap voice-state seam: Alice joins over REST, Bob's app must see it via `list_voice_states` (reads the local `voiceStatesController` cache the UI renders; `get_current_state` only reports the caller's own state). No SFU, audio, or UDP needed.
- The server refuses voice endpoints (`voice_not_configured`) unless LiveKit is configured, even in test mode; the fixture sets placeholder `LIVEKIT_*` values it never dials.
- `livekit_voice_test.dart` is the opt-in real-media seam. `ACCORD_TEST_LIVEKIT=1` starts a digest-pinned LiveKit container, drops `ACCORD_TEST_MODE`, and drives both apps through `join_voice_channel`, asserting room/participants, mute, deafen subscriptions, SFU outage + reconnection, and teardown. Needs Linux Docker host networking, UDP, and usable PulseAudio default sink/source (CI uses a null sink and its monitor).

```bash
flutter build linux --release
ACCORD_TEST_LIVEKIT=1 \
  xvfb-run -a flutter test multi_instance/livekit_voice_test.dart --reporter expanded
```

## CI

`multi-instance` is an advisory Linux job under xvfb (with a gnome-keyring secret service). `livekit-sfu` is advisory and manual: **Run workflow → Real LiveKit SFU** (`livekit_sfu` input).
