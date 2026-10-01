# Curated experiences, host API 1

The master server reviews and distributes immutable signed WASM game releases.
Community servers pin enabled versions and own lobbies, membership, turns,
results and persisted game state. The Flutter client renders guest commands and
submits scoped actions. No guest receives a credential or an HTTP/socket API.

## Legacy inventory and cutover

The client has no Lua/native execution UI. Its only legacy consumers are SDK
contracts/tests: `plugin_manifest.dart`, `plugins_api.dart`, six gateway streams
and their client forwarding properties. The server has ZIP/source delivery,
space-installed plugins, voice-channel sessions, arbitrary action forwarding,
client-submitted leaderboard scores and a `plugin.*` gateway filter. Keep the
authenticated REST/gateway transport pattern; replace the contracts and state
authority. Arcade sessions belong to spaces, independently of voice/channels.
Legacy executable installations cannot be converted into reviewed WASM packages.
Retire routes atomically when the replacement is wired; archive old database
tables through the migration, with no execution or automatic reinstallation.

## Runtime decision

Host v1 implements a deliberately restricted, valid WebAssembly core profile in
pure Dart. Supported modules have only types, the three imports below, functions,
two exports and code. All values are i32. Instructions are `i32.const`,
`local.get`, direct `call`, `drop`, `i32.add/sub/mul` and function `end`. Calls
must target earlier functions, proving an acyclic call graph. No loops,
branches, recursion, memory, tables, globals, start functions, custom sections,
indirect calls, WASI or ambient capabilities are admitted. Unsupported compiler
output is rejected during review, installation and client validation.

This limited profile is enough for chess/Pong presentation and input because
game rules run on the community server. It avoids adding native binary/JIT
dependencies and has the same enforcement in Dart VM, Flutter JS and Flutter
WASM builds. It is not a general Wasm runtime. A future profile can broaden the
instruction set only with new review/runtime gates and a new host API version.
Serein's explicit fuel/resource/capability boundaries informed the isolation
design; its local extension lifecycle is not reused as multiplayer authority.
See the [Serein runtime reference](https://github.com/ViceVerse-cz/Serein/blob/baec1df/crates/extensions/src/runtime.rs).
`wasm_run` was not selected because its web fuel API returns null; `wasd`'s
published interpreter has no execution budget and its browser backend delegates
to browser WebAssembly. These were inspected as candidates, not shipped.

## ABI

Imports in module `daccord_v1`, in this order:

| Import | i32 parameters | Result | Scope |
|---|---|---|---|
| `read_state` | key, index | i32 | Immutable authoritative session snapshot |
| `draw` | kind, semantic id, x, y, width, height, value | none | Atomic Flutter frame, render only |
| `action` | kind, a, b | none | At most one proposed session action, input only |

Exports are `render() -> ()` and `input(kind,a,b) -> ()`. Draw coordinates use
a 1024 square logical canvas. Kind 0 is a chess square with a bounded built-in
piece glyph; kind 1 is a Pong rectangle. Assets in v1 are host-owned glyphs and
colors; embedded files, paths and URLs are denied. Flutter supplies keyboard,
pointer and semantic controls; modules never construct widgets.

Chess reads key 0, indices 0–63 (a1=0). Piece values are 0=empty, 1–6 white
pawn/knight/bishop/rook/queen/king, 7–12 black equivalents. Action kind 0 carries
source/destination square indices; promotion selection is a host control.
Pong reads key 1, indices 0–11: x/y/width/height for left paddle, right paddle
and ball. Its action carries normalized paddle input. Both use session revision
checks, authenticated participant identity and server-side rule validation.

## Resource and lifecycle boundaries

Modules are at most 64 KiB, sections at most 256 entries, function bodies at
most 4096 instructions, operand stack at most 128 i32s, call depth at most 32,
and each invocation at most 10000 instructions. Frames contain at most 128
commands, state reads at most 256, input at most one action. All buffers are
bounded before allocation. No guest persistent storage is exposed. Infinite
loops and memory/table growth are rejected before invocation, including web.
Frames/actions are committed only after the whole invocation succeeds.

A host grant binds account, server, space, pinned release, session and lifecycle
generation. Check it on every host call and before accepting output. Navigation,
account changes, logout, disable/removal, membership loss, revocation and session
end invalidate it. Server permissions and release approval are checked again at
the authoritative action boundary. Lost gateway events trigger a fresh snapshot;
session revision conflicts refresh state rather than replaying a move.

## Creator tooling and validation

Run `python3 tools/experiences/build_reference.py` to reproduce the chess and
Pong modules/packages. No external compiler is required; the small builder is
the initial SDK for the bounded profile. Submit the exact manifest/module JSON
for review. Publication binds the exact payload, digest and publisher to a
review record; a manifest's own assertion of trust has no meaning.

Run `dart test` in `packages/experience_runtime` and the same tests with
`dart test -p chrome` for browser enforcement. Runtime tests exercise reference
frames/input, truncated binaries, infinite loops, recursive calls, denied
capabilities, output floods and revocation during execution. Platform support
is gated on actual validation: API-level portability or a successful compile
does not count as a physical-device result. Track desktop/mobile/web build and
device evidence in `validation.md` before declaring #360/#365 complete.
