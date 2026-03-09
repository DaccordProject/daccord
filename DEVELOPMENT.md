# Development Guide

Local setup and CI-equivalent commands for daccord contributors.

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| **Godot 4.5** | Run/export the game | [godotengine.org/download](https://godotengine.org/download) — add to `PATH` |
| **Python 3 + gdtoolkit** | GDScript lint | `pip install gdtoolkit` |
| **Rust stable** | Build accordserver (integration/e2e tests) | `rustup install stable` |
| **AccordServer** | Test server | Clone as a sibling: `../accordserver/` |

### godot-livekit addon

Binaries are not tracked in git. Download and install before running:

```bash
gh release download --repo NodotProject/godot-livekit \
  --pattern "godot-livekit-release.zip" --dir /tmp
unzip -o /tmp/godot-livekit-release.zip -d /tmp/extracted
cp -R /tmp/extracted/addons/godot-livekit addons/godot-livekit
```

### AccordServer location

`test.sh` expects accordserver at `../accordserver` relative to the daccord repo root:

```
parent/
  daccord/       ← this repo
  accordserver/  ← clone here
```

Clone it:

```bash
git clone https://github.com/daccord-projects/accordserver ../accordserver
```

## Running Tests Locally

### CI-equivalent commands

| CI Job | Local Command |
|--------|---------------|
| Lint | `gdlint scripts/ scenes/` |
| Unit tests | `./test.sh unit` |
| Integration tests | `./test.sh integration` |
| All (excl. GodotLite) | `./test.sh` |
| Lint with full report | `./lint.sh` |

### Test suites

```bash
./test.sh              # All tests (unit + accordkit unit/integration + livekit)
./test.sh unit         # Unit tests only — no server needed, fast
./test.sh integration  # AccordKit unit + REST integration tests
./test.sh accordkit    # Same as integration
./test.sh livekit      # LiveKit adapter tests — no server needed
./test.sh gateway      # Gateway/e2e tests — requires non-headless Godot
```

### Tips

- **Tail server logs during integration tests:**
  ```bash
  tail -f test_server.log
  ```

- **Run against a remote test server** (skips local `cargo build`):
  ```bash
  ACCORD_TEST_URL=http://<host>:39099 ./test.sh accordkit
  ```
  The remote server must have `ACCORD_TEST_MODE=true`.

- **GodotLite export validation** only runs in CI — no local equivalent needed.

## Lint

```bash
gdlint scripts/ scenes/          # Quick check — same as CI
./lint.sh                        # Full report with naming checks and complexity
```

See `gdlintrc` for configured limits.
