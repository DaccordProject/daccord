# Multi-instance tests

Layer 3 of #217: **two real app processes**, one server, both sides of every
interaction asserted.

Layers 1 (`integration/`) and 2 (`integration_test/`) both run inside a single
process, so they can only check what one client believes. These launch two
actual clients and drive them through the MCP server the app already exposes in
Developer Mode — the same JSON-RPC tool surface a developer or an agent would
use (`lib/features/developer/services/mcp_tools.dart`). No synthetic input: no
xdotool, no fake clicks.

```bash
flutter build linux --release          # required — see "Release, not debug"
flutter test multi_instance/
```

`flutter test` on its own doesn't pick these up; it only walks `test/`.

## How an instance is made

Per instance, `AppInstance.launch`:

1. Creates a throwaway `HOME` and gives it the XDG layout (see below).
2. Seeds `accord-settings` with Developer Mode + MCP on, a unique `mcpPort`,
   and every tool group enabled — the default is `read`/`navigate` only, so
   anything else 404s.
3. Seeds `accord-session` with a token from an account the layer-1 harness
   registered, which is what makes the app come up already signed in: the login
   screen restores it on its first frame.
4. Launches the app and waits for its MCP server to answer.

Storage isolation is what keeps two instances from fighting over the same Hive
boxes, and it's also what stops a test run touching your real profile.

## Four things that cost real time

**Release, not debug.** A *debug* bundle launched directly never runs its Dart
entrypoint. The engine starts, native plugins register, the GTK loop idles — and
`main()` never executes, so no Hive box is opened and no MCP server starts. It
presents as a window that simply does nothing, with no error anywhere.
`flutter test -d linux` drives debug bundles fine because the tool attaches and
injects the entrypoint; nothing does that here. `resolveBinary()` prefers
release for this reason.

**`XDG_DOCUMENTS_DIR` is not what decides where data goes.** Flutter's
`getApplicationDocumentsDirectory()` on Linux calls `xdg.getUserDirectory`,
which shells out to the **`xdg-user-dir` executable** and ignores the
environment variable entirely. Under a fresh `HOME` with no
`.config/user-dirs.dirs`, that returns `$HOME` itself — not `$HOME/Documents` —
so seeding the obvious path writes somewhere the app never reads, and the app
comes up with default settings and no MCP server. `prepareHome` writes a
`user-dirs.dirs`, and `documentsDirFor` asks `xdg-user-dir` the same question
the app will, rather than assuming.

**`select_channel` needs the space selected first.** It resolves the id against
the selected space's channel list, so calling it cold answers "Channel not
found" for a channel that plainly exists. `openChannel` in the test does both.

**Don't reuse HTTP connections.** A pooled socket the app has since dropped
fails the next call with "Connection closed before full header was received" —
it flaked roughly one run in two. Each call now opens its own connection, and
retries once on a transport error.

## Adding a scenario

`AppInstance.call(tool, args)` unwraps both layers of the response (JSON-RPC
`result.content[0].text` holds the tool's JSON as a string) and throws on a
tool-level error. Never assert straight after an action that crosses the
gateway — use `callUntil`, which polls and fails with a timeout carrying the
last result it saw.

Note that tool payloads don't always match the REST shapes: `list_members`
flattens the member onto the user (`id`, `username`, …) where REST nests a
`user` object under `user_id`.

## Voice, without an SFU

Voice is the strongest reason to have this layer — who hears whom is inherently
multi-process — and it's covered, but not in the obvious way.

`get_current_state` only reports the caller's **own** voice state, so a new
`list_voice_states` (read group) was added to `mcp_tools.dart`. It reads the
local `voiceStatesController` cache, which is what the UI renders and what
`voice.state_update` events drive — so it reports what the user can actually
see, including whether a peer's join ever arrived.

The other half is that A joins voice **over REST**, not through her app's
`join_voice_channel`. That tool also drives the LiveKit session, and there's no
SFU in the fixture. It doesn't weaken the test: the server broadcasts
`voice.state_update` *before* it touches LiveKit, so the fan-out B renders is
identical either way. What isn't covered is the client's own LiveKit session —
media, mute propagation through the room — which needs a real
`livekit/livekit-server` in the fixture.

The server also refuses voice endpoints outright unless a LiveKit client is
configured (`voice_not_configured`), even in test mode, so the fixture sets
`LIVEKIT_*` to a URL it never dials.

## CI

Runs as its own non-blocking job on Linux under xvfb, after a release build. It
is the most expensive of the three suites (a release build plus two app
processes), so it's deliberately separate from the merge gate.
