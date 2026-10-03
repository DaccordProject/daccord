---
title: Creating Arcade Extensions
description: Build, test, review, and publish custom Arcade packages for your own Daccord server.
order: 1
section: developer
---

# Creating Arcade Extensions

You can create a custom Arcade package for your community and distribute it
through a reviewed game directory. This guide walks through a Chess package
with its own name, publisher, and board layout, then explains how your server
can trust and enable it.

## What you can build today

Arcade extensions use **host API 1**, a small, bounded WebAssembly (WASM)
presentation and input API. The community server owns the game rules, players,
turns, scores, and saved state. The client draws the package's commands and
sends proposed actions to the server for validation.

| Goal | Current support |
| --- | --- |
| Custom Chess or Pong presentation | Build a package using the existing authority and host-owned drawing primitives. |
| A private directory for your server | Run your own Accord Master Server, review packages, and configure your community server to trust its public signing key. |
| A game with different rules | Implement and review a new server authority, extend the shared contract and client host, and release compatible software. |
| General chat tools or integrations | Use AccordServer's authenticated APIs separately; Arcade packages cannot access chat, credentials, files, or the network. |

The legacy Lua/native plugin system and **daccord-editor** are retired for new
Arcade packages. Host API 1 currently accepts only `chess` / `turn_based` and
`pong` / `real_time`, with two players and up to 16 spectators. Artwork, colors,
piece glyphs, and interaction controls belong to the host; packages cannot
bundle custom images, URLs, HTML, or Flutter widgets.

## 1. Get the reference builder

Install Python 3 and clone the client repository:

```sh
git clone https://github.com/DaccordProject/daccord.git
cd daccord
python3 tools/experiences/build_reference.py --output /tmp/arcade-reference
```

This writes `chess.json`, `chess.wasm`, `pong.json`, and `pong.wasm` without an
external compiler. A package is a JSON object containing `manifest` and
`module`, where `module` is the base64-encoded WASM binary. The manifest's
`module_sha256` hashes the decoded binary.

The builder is the initial SDK. Ordinary Rust, C, AssemblyScript, or WASI
compiler output generally uses features outside this profile and is rejected.
See the [host API reference](../experiences/architecture.md) for the exact
instruction set, ABI, and execution limits.

## 2. Make your first custom package

From the repository root, save this as `tools/experiences/build_community_chess.py`.
It keeps Chess's rules and square identities, but draws a smaller board centered
inside the logical canvas.

```python
import base64
import hashlib
import json
from pathlib import Path

from build_reference import call, const, module, package

render = b""
for cell in range(64):
    # draw(kind, semantic_id, x, y, width, height, piece_value)
    values = [0, cell, 128 + (cell % 8) * 96,
              128 + (7 - cell // 8) * 96, 96, 96]
    render += b"".join(const(value) for value in values)
    # read_state(0, cell), then draw the returned piece value.
    render += const(0) + const(cell) + call(0) + call(1)

wasm = module("chess", render=render)
custom = package("chess")
custom["manifest"].update(
    id="community-chess",
    name="Community Chess",
    description="A compact Chess board for our community.",
    publisher="Your Community",
    version="1.0.0",
    platforms=["linux"],  # Add platforms only after validating them.
    module_sha256=hashlib.sha256(wasm).hexdigest(),
)
custom["module"] = base64.b64encode(wasm).decode("ascii")

output = Path("/tmp/arcade-community")
output.mkdir(parents=True, exist_ok=True)
(output / "community-chess.wasm").write_bytes(wasm)
(output / "community-chess.json").write_text(
    json.dumps(custom, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
```

Run it from the repository root:

```sh
python3 tools/experiences/build_community_chess.py
```

Use your own package ID and publisher. IDs and versions must be 1–64 ASCII
letters, digits, dots, underscores, or hyphens. Keep `authority="chess"`,
`session_mode="turn_based"`, `host_api=1`, `runtime="wasm-bounded-v1"`, and the
capabilities in their exact order: `session.read`, `session.action`, `draw`.
Unknown manifest fields are rejected. Every binary change needs a new module
hash; every published change needs a new version.

## 3. Understand rendering and input

The module imports these functions from `daccord_v1`, in this order:

| Function | Parameters | Result |
| --- | --- | --- |
| `read_state` | `key, index` | One `i32` from the authoritative snapshot. |
| `draw` | `kind, semantic_id, x, y, width, height, value` | A drawing command, during `render` only. |
| `action` | `kind, a, b` | One proposed action, during `input` only. |

Export `render() -> ()` and `input(kind, a, b) -> ()`. All parameters and state
values are `i32`. The canvas uses coordinates from 0 to 1024. Chess reads state
key 0 at indices 0–63; drawing kind 0 uses the square index as its semantic ID
and the returned piece value. Preserve these IDs when changing the layout so
pointer, keyboard, and accessibility controls still identify the correct square.
The reference input forwards the host's kind/source/destination to `action`;
the server checks the authenticated player, turn, revision, and legal move.

Pong reads state key 1 at indices 0–11, containing x/y/width/height for each
paddle and the ball. Drawing kind 1 describes its rectangles. The trusted host
provides paddle controls and real-time transport.

Modules are limited to 64 KiB and packages to 100,000 bytes. Each invocation has
an instruction budget of 10,000, at most 256 state reads, 128 drawing commands,
and one proposed action. Memory, loops, branches, recursion, WASI, filesystem,
network, and persistent guest storage are outside host API 1.

## 4. Test before requesting review

With Dart installed, run the portable host checks:

```sh
cd packages/experience_runtime
dart pub get
dart test
dart test -p chrome
```

These checks validate the runtime and reference packages; they do not validate
your custom package automatically. Exercise your exact binary with
`ExperienceModule.decode`, call `render` against a known board snapshot, and
call `input` with representative moves. The
[runtime tests](https://github.com/DaccordProject/daccord/blob/master/packages/experience_runtime/test/runtime_test.dart)
show how to supply `readState` and a valid lifecycle grant. Install the reviewed
package on a development server and play it with two accounts, including
keyboard input, reconnects, spectators, and disable/update behavior.

Declare only platforms you actually tested. The reference builder lists all
platforms as a fixture; that list is not release evidence. In particular, do
not copy its iOS entry without physical-device validation. Keep platform
results with the package's review material; the project's
[validation record](../experiences/validation.md) describes the required evidence.

## 5. Review and publish the exact package

Send the package JSON, source, reproducible build steps, publisher identity,
license information, and platform test results to the operator of your chosen
directory. The official directory requires review by its maintainers; it has
no public self-service upload. You can run your own directory for your server.

On your **Accord Master Server**, configure:

| Variable | Value |
| --- | --- |
| `EXPERIENCE_REVIEW_TOKEN` | A separate secret of at least 32 characters for reviewer authentication. |
| `EXPERIENCE_SIGNING_KEY` | A securely generated Ed25519 32-byte seed, encoded as 64 hex characters. |
| `EXPERIENCE_SIGNING_KEY_ID` | A stable identifier for this signing key. |
| `EXPERIENCE_REVIEWER_ID` | The operator-assigned identity recorded for publication. |

Generate an Ed25519 key pair with a trusted key-generation tool and retain its
32-byte public key for community-server configuration. Keep the signing seed
and reviewer token on the directory server. Server-registration credentials
cannot publish games.

After the reviewer has inspected the exact package, encode its bytes in a
submission file:

```sh
python3 - <<'PY'
import base64
import json
from pathlib import Path

payload = Path("/tmp/arcade-community/community-chess.json").read_bytes()
Path("/tmp/arcade-community/submission.json").write_text(
    json.dumps({"payload": base64.b64encode(payload).decode("ascii")}),
    encoding="utf-8",
)
PY
```

The reviewer sends that file to `POST /api/v1/experiences` on their directory,
with `Content-Type: application/json` and `Authorization: Bearer <review token>`.
The directory validates the package and signs its exact bytes, recording the
publisher, digest, key ID, reviewer, and immutable version. Formatting or
editing a signed payload changes its identity. A duplicate ID/version returns
a conflict; publish a new version instead.

Use `GET /api/v1/experiences/community-chess/1.0.0` to inspect the resulting
release. Reviewer-only `PATCH` on that same path accepts
`{"status":"delisted"}` or `{"status":"revoked"}`. Revocation is permanent.

## 6. Enable it on your own server

On **AccordServer**, set:

```text
EXPERIENCES_ENABLED=true
EXPERIENCE_DIRECTORY_URL=https://your-directory.example
EXPERIENCE_TRUSTED_KEYS={"your-key-id":"your-64-character-hex-public-key"}
```

The key ID must match the directory's signing key ID. Provision the public key
through your operator configuration. Directory URLs require HTTPS; HTTP is
allowed only for loopback development. Restart or redeploy the server after
changing these environment variables.

A member with **Manage Space** can then open **Space Settings → Arcade**, find
the reviewed version, and choose **Enable**. Installing the first game creates
the space's single Arcade channel. See
[Managing Arcade](../administration/managing-arcade.md) for channel placement,
lobbies, updates, and cleanup. Community servers accept reviewed directory
releases rather than direct file uploads or arbitrary installation URLs.

The server checks current approval and the pinned version's signature during
installation and execution. Directory outages, untrusted keys, delisting, or
revocation prevent fresh execution and stop affected sessions. Plan for the
directory to remain available while people play.

## Adding a completely new game

Use the example above to learn packaging; changing `authority` to a new name
will fail validation. A new rules engine requires coordinated changes to
AccordServer's authoritative state/actions, the contract validators in both
server repositories, the client's state/input/rendering host, and tests for
permissions, persistence, concurrent actions, resource bounds, and supported
platforms. Broader WASM features require a new host API profile and validation
gates. Start with the [architecture reference](../experiences/architecture.md)
and propose the authority to the project maintainers, or maintain compatible
forks of these components for your own deployment.
