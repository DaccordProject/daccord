# Continuous Integration

Last touched: 2026-02-27

## Overview

The daccord CI pipeline runs on every PR to `master` via GitHub Actions. It validates code quality, runs unit tests, and optionally runs integration tests against a live accordserver instance. Two workflows exist: `ci.yml` (lint + tests on PRs) and `release.yml` (CI gate + cross-platform builds on version tags). The release workflow calls `ci.yml` via `workflow_call` as a prerequisite before building. AccordKit is developed in-tree under `addons/accordkit/`, so no external checkout is needed for it.

## User Steps

### Check CI Status

1. Run `gh run list --limit 10` to see recent CI runs with status, commit message, and timing.
2. Find the run ID in the output (seventh column).
3. Run `gh run view <RUN_ID>` to see per-job pass/fail breakdown.
4. For a one-liner: `gh run list --branch master --limit 1 --json conclusion --jq '.[0].conclusion'` returns `success` or `failure`.

### Inspect a Failing Run

1. Run `gh run view <RUN_ID> --log-failed` to see only the logs from failed steps.
2. Pipe through grep to find specific errors: `gh run view <RUN_ID> --log-failed 2>&1 | grep -i "error\|failed\|parse error"`.
3. For per-job results: `gh run view <RUN_ID> --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'`.
4. For failed step names: `gh run view <RUN_ID> --json jobs --jq '.jobs[] | "\(.name): \(.conclusion) (\(.steps | map(select(.conclusion == "failure")) | .[0].name // "all passed"))"'`.

### Watch a Run in Progress

1. Run `gh run watch <RUN_ID>` to get live terminal updates until the run completes.
2. To watch the most recent run: `gh run watch $(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')`.

### Re-run Failed Jobs

1. Run `gh run rerun <RUN_ID> --failed` to re-run only the jobs that failed (saves time).
2. Run `gh run rerun <RUN_ID>` to re-run the entire workflow.

### Download Artifacts

1. Run `gh run view <RUN_ID> --json artifacts --jq '.artifacts[].name'` to list artifacts.
2. Run `gh run download <RUN_ID> --name accordserver-log` to download a specific artifact (e.g., server logs from failed integration tests).
3. Run `gh run download <RUN_ID>` to download all artifacts.

### Open in Browser

1. Run `gh run view <RUN_ID> --web` to open the run in the GitHub Actions web UI.
2. Or get just the URL: `gh run view <RUN_ID> --json url --jq '.url'`.

### Run Tests Locally Before Pushing

1. Run `./test.sh unit` to run unit tests locally (no server needed, fast).
2. Run `./test.sh integration` to run integration tests (starts accordserver automatically).
3. Run `./test.sh` to run all tests.
4. Watch server logs while integration tests run: `tail -f test_server.log`.

### Useful One-Liners

```bash
# Show the last 5 failures with their commit messages
gh run list --limit 20 --json conclusion,displayTitle,databaseId \
  --jq '[.[] | select(.conclusion == "failure")] | .[:5][] | "\(.databaseId) \(.displayTitle)"'

# Count passing/failing tests from a run
gh run view <RUN_ID> --log 2>&1 | grep -oP '\d+/\d+ passed' | tail -1
```

## Signal Flow

```
PR to master
  ├─> ci.yml triggers
  │     ├─> Lint job
  │     │     ├─ gdlint scripts/ scenes/
  │     │     └─ Code complexity analysis (gdradon cc, warns on grade C-F)
  │     │
  │     ├─> Unit Tests job (needs: lint)
  │     │     ├─ Checkout daccord (with LFS)
  │     │     ├─ Checkout godot-livekit (NodotProject/godot-livekit, public, LFS)
  │     │     ├─ Install audio libraries (libasound2, libpulse, libopus)
  │     │     ├─ Symlink addons/godot-livekit
  │     │     ├─ Install GUT (cached) + Sentry SDK (cached, GH_PAT)
  │     │     ├─ Setup Godot 4.5.0 (chickensoft-games/setup-godot@v2)
  │     │     ├─ Cache + import project (.godot/imported/)
  │     │     ├─ Run GUT on tests/unit/ (-gexit for proper exit codes)
  │     │     ├─ Run GUT on tests/livekit/ (-gexit, continue-on-error)
  │     │     └─ Write per-suite test result summary to $GITHUB_STEP_SUMMARY
  │     │
  │     └─> Integration Tests job (needs: lint, blocking)
  │           ├─ Checkout daccord (with LFS)
  │           ├─ Checkout godot-livekit (NodotProject/godot-livekit, public, LFS)
  │           ├─ Checkout accordserver (DaccordProject/accordserver, GH_PAT)
  │           ├─ Install audio libraries (libasound2, libpulse, libopus)
  │           ├─ Symlink addons/godot-livekit
  │           ├─ Install GUT (cached) + Sentry SDK (cached, GH_PAT)
  │           ├─ Install Rust + sccache (continue-on-error, conditional wrapper)
  │           ├─ Build accordserver (cargo cached, sccache retry fallback)
  │           ├─ Start server (ACCORD_TEST_MODE=true, SQLite)
  │           ├─ Wait for /health (30s timeout)
  │           ├─ Cache + import project (.godot/imported/)
  │           ├─ Run AccordKit unit tests: tests/accordkit/unit (-gexit, required)
  │           ├─ Run REST integration tests: tests/accordkit/integration (-gexit, required)
  │           ├─ Run gateway + e2e tests: tests/accordkit/gateway + tests/accordkit/e2e (-gexit, continue-on-error)
  │           ├─ Write per-suite test result summary to $GITHUB_STEP_SUMMARY
  │           └─ Stop server, always upload test_server.log

Push v* tag
  └─> release.yml triggers
        ├─> CI job (uses: ./.github/workflows/ci.yml, secrets: inherit)
        │     └─ Runs the full ci.yml pipeline as a prerequisite gate
        │
        ├─> 4x parallel Build jobs (needs: ci) (Linux x86_64, Linux ARM64, Windows, macOS)
        │     ├─ Validate tag matches project.godot version
        │     ├─ Install audio libraries (Linux only)
        │     ├─ Install GUT + Sentry SDK (cached)
        │     ├─ Install godot-livekit addon (latest release asset from NodotProject/godot-livekit)
        │     ├─ Remove godot-livekit if platform binary missing (prevents crash)
        │     ├─ Setup Godot 4.5.0 with export templates
        │     ├─ Inject SENTRY_DSN, clear missing custom templates
        │     ├─ Export (godot --headless --export-release)
        │     ├─ Package (tar.gz / zip)
        │     └─ Sign + notarize (if secrets configured)
        │
        ├─> Windows Installer job (needs: build)
        │     ├─ Download Windows build artifact
        │     ├─ Compile installer with Inno Setup
        │     └─ Sign installer (if secrets configured)
        │
        └─> Create Release job (needs: build, windows-installer)
              ├─ Download all artifacts
              ├─ Extract changelog section from CHANGELOG.md
              └─ Create GitHub Release (softprops/action-gh-release@v2)
```

## Pipeline Architecture

### Workflow: `.github/workflows/ci.yml`

Three jobs triggered on PR to `master` (also callable via `workflow_call` from `release.yml`). Unit Tests and Integration Tests both depend on Lint (run after it passes):

| Job | Runner | Environment | Depends On | Required | Purpose |
|-----|--------|-------------|------------|----------|---------|
| **Lint** | ubuntu-latest | *(none)* | *(none)* | Yes | gdlint + gdradon complexity analysis on `scripts/` and `scenes/` |
| **Unit Tests** | ubuntu-latest | `default` | Lint | Yes | GUT tests in `tests/unit/` + `tests/livekit/` (LiveKit tests are `continue-on-error`) |
| **Integration Tests** | ubuntu-latest | `default` | Lint | Yes (blocking) | GUT tests in `tests/accordkit/` with live accordserver (split into 3 steps: AK unit, REST integration, gateway+e2e) |

### Workflow: `.github/workflows/release.yml`

Triggered by `v*` tags. First runs CI as a prerequisite gate, then builds four platform artifacts, builds a Windows installer, and creates a GitHub Release. See [Cross-Platform GitHub Releases](cross_platform_github_releases.md).

### Dependencies & Setup

**GitHub Organization:** The actual org is **`DaccordProject`** (not `daccord-projects`).

| Repo | Visibility | Purpose |
|------|------------|---------|
| `DaccordProject/daccord` | Private | This client (CI runs here). AccordKit is in-tree at `addons/accordkit/`. |
| `NodotProject/godot-livekit` | Public | GDExtension for voice/video (native binaries in LFS) |
| `DaccordProject/accordserver` | Private | Rust backend (built from source for integration tests) |

**Authentication:** `GH_PAT` is stored as an environment secret in the `default` environment. It is used for:
- Checking out `DaccordProject/accordserver` (private, integration tests only)
- Downloading the Sentry SDK release asset (`getsentry/sentry-godot`)

The godot-livekit checkout does not require `GH_PAT` (public repo). AccordKit is in-tree and needs no checkout.

**Addon Installation:**

| Addon | Source | Install Method | Cached |
|-------|--------|---------------|--------|
| `addons/accordkit` | In-tree (this repo) | Part of main checkout | N/A |
| `addons/godot-livekit` | `NodotProject/godot-livekit` (public, LFS) | CI: `actions/checkout` with `lfs: true` + symlink. Release: latest release asset download. | No |
| `addons/gut` | `bitwes/Gut` v9.5.0 (public) | Source tarball from GitHub tags | Yes (`actions/cache`) |
| `addons/sentry` | `getsentry/sentry-godot` v1.3.2 (public) | Release zip from GitHub | Yes (`actions/cache`) |

**Godot Version:** `4.5.0` (must be full semver for `chickensoft-games/setup-godot@v2`). Renderer: GL Compatibility. Export templates needed for release only.

### Caching Strategy

| Cache | Key | Path | Benefit |
|-------|-----|------|---------|
| GUT framework | `gut-9.5.0` | `addons/gut` | Skip 2s download |
| Sentry SDK | `sentry-godot-1.3.2` | `addons/sentry` | Skip 5s download |
| Godot import | `godot-import-{version}-{project+scenes hash}` | `.godot/imported` | Skip re-import (~10-30s) |
| Rust cargo registry | `Linux-cargo-{Cargo.lock hash}` | `~/.cargo/registry`, `~/.cargo/git`, `.accordserver_repo/target` | Skip multi-minute server build |
| sccache | GHA-managed (`continue-on-error`) | GHA cache backend | Incremental Rust compilation caching; falls back to plain `cargo` if sccache setup fails OR if sccache crashes at runtime (retry logic) |

## Debugging CI Failures

### Common Failure Patterns

**1. "Could not find type X in the current scope"** -- A script references a type that doesn't exist. Since AccordKit is in-tree, this means the type was removed or renamed. Check for recent refactors:

```bash
git log --oneline -10 -- addons/accordkit/
```

**2. "Can't open dynamic library... invalid ELF header"** -- The godot-livekit `.so` is likely an LFS pointer, not the actual binary. LFS pointers are ~130 bytes; a real `.so` is megabytes:

```bash
gh api repos/NodotProject/godot-livekit/contents/addons/godot-livekit/bin/libgodot-livekit.linux.x86_64.so \
  --jq '.size'
```

**3. "Invalid call. Nonexistent function 'X'"** -- An autoload failed to compile, so its methods don't exist at runtime. Look further up in the logs for the compilation error:

```bash
gh run view <RUN_ID> --log-failed 2>&1 | grep "SCRIPT ERROR" | head -20
```

**4. Step timeouts** -- The `Import project` and test steps have timeouts. Check if import hung:

```bash
gh run view <RUN_ID> --json jobs \
  --jq '.jobs[].steps[] | select(.name == "Import project") | "\(.name): \(.conclusion)"'
```

**5. Secret/authentication failures** -- If private repo checkouts fail, the `GH_PAT` secret may have expired:

```bash
gh run view <RUN_ID> --json jobs \
  --jq '.jobs[].steps[] | select(.name | test("Checkout")) | "\(.name): \(.conclusion)"'
```

**6. GUT framework errors** -- GUT 9.5.0 has a known compatibility issue with Godot 4.5 where `gut_loader.gd:35` throws a `Nil` to `bool` assignment error. This is non-fatal and tests still run. Filter it out when reviewing logs:

```bash
gh run view <RUN_ID> --log-failed 2>&1 | grep "SCRIPT ERROR" | grep -v gut_loader
```

**7. sccache runtime crash** -- The sccache *setup* step can succeed (binary installs fine) while sccache *runtime* crashes because the GHA cache backend is temporarily down. The error looks like `error: process didn't exit successfully: 'sccache ... rustc -vV'` with an HTML error body. The build step has retry logic: if cargo fails with sccache, it retries without it. If you see `::warning::Build failed with sccache, retrying without it`, the retry is working. If the retry also fails, the issue is with cargo/Rust itself, not sccache.

**8. LiveKit cascading failures** -- If the godot-livekit GDExtension binary fails to load (e.g., LFS pointer instead of real binary, or extension not compiled for the runner arch), extension classes aren't registered. `client.gd` guards voice session creation with `ClassDB.class_exists()` and null checks, so the Client autoload initializes fully even without LiveKit. Voice-dependent tests skip gracefully when the extension is unavailable. CI installs audio libraries (`libasound2-dev`, `libpulse-dev`, `libopus-dev`) to help the extension load. Look for the root error:

```bash
gh run view <RUN_ID> --log 2>&1 | grep "set_output_device\|get_speakers\|GDScriptNativeClass"
```

**9. `| tee` swallows exit codes** -- Before the `set -o pipefail` fix, the `2>&1 | tee` pipe in test steps would swallow the GUT `-gexit` exit code because bash evaluates the exit code of the last command in the pipeline (`tee`, which always returns 0). With `set -o pipefail`, the pipeline returns the exit code of the leftmost failing command. If you see tests reporting failures in the summary but the step shows "success", check that `set -o pipefail` is present.

## Implementation Status

- [x] CI workflow triggered on PR to `master` (`.github/workflows/ci.yml`)
- [x] CI callable via `workflow_call` (used by `release.yml` as prerequisite gate)
- [x] Lint job with gdlint on `scripts/` and `scenes/`
- [x] Code complexity analysis with gdradon (warns on grade C-F functions)
- [x] Unit test job with GUT headless runner
- [x] LiveKit tests in unit test job (`tests/livekit/`, `continue-on-error`)
- [x] Integration test job with live accordserver (blocking)
- [x] Integration tests split into 3 steps: AK unit (required), REST integration (required), gateway+e2e (`continue-on-error`)
- [x] Release workflow triggered by `v*` tags (`.github/workflows/release.yml`)
- [x] Release workflow gates on CI passing before building
- [x] AccordKit in-tree (no external checkout needed)
- [x] godot-livekit checkout from `NodotProject/godot-livekit` (public, LFS)
- [x] Accordserver checkout via `GH_PAT` (integration tests only)
- [x] GUT install from source tarball (cached)
- [x] Sentry SDK install from release zip (cached)
- [x] Godot 4.5.0 setup via `chickensoft-games/setup-godot@v2`
- [x] Headless project import before test runs
- [x] Accordserver build from source with cargo caching
- [x] Server health check with 30s timeout
- [x] Server log always uploaded (`upload-artifact@v4`, `if: always()`)
- [x] Integration test seed isolation (seed route uses idempotent find-or-create patterns)
- [x] GUT `-gexit` flag for proper exit codes (non-zero on test failure)
- [x] `set -o pipefail` in test steps (prevents `| tee` from swallowing exit codes)
- [x] Test result summary in `$GITHUB_STEP_SUMMARY` (per-suite for unit/livekit and AK unit/rest/gateway)
- [x] sccache for Rust builds (resilient: `continue-on-error` + conditional wrapper + retry fallback)
- [x] Godot import cache (`.godot/imported/`, hash-keyed)
- [x] gdlintrc config file for lint job
- [x] Integration tests made blocking (`continue-on-error` removed from required steps)
- [x] Job dependency ordering (unit tests + integration tests depend on lint)
- [x] LiveKit graceful degradation (`client.gd` guards voice session creation, tests skip when unavailable)
- [x] Audio libraries installed on CI runners (`libasound2-dev`, `libpulse-dev`, `libopus-dev`)
- [x] Gateway tests improved (longer timeouts, disconnection detection, early exit on failure)
- [x] Releases tagged (v0.1.0 through v0.1.3)
- [x] Windows installer job in release workflow (Inno Setup)

## Tasks

### CI-1: GUT 9.5.0 + Godot 4.5 compatibility
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** testing
- **Notes:** `gut_loader.gd:35` throws "Trying to assign value of type 'Nil' to a variable of type 'bool'" during static init. Non-fatal (tests still run). Monitor for upstream fix.
## Key Files

| File | Purpose |
|------|---------|
| `.github/workflows/ci.yml` | CI pipeline (lint, unit tests, integration tests) |
| `.github/workflows/release.yml` | Release pipeline (CI gate, build, package, installer, publish) |
| `export_presets.cfg` | Godot export presets for 4 platforms |
| `project.godot` | Version source of truth (`config/version`) |
| `test.sh` | Local test runner (starts accordserver automatically) |
| `lint.sh` | Local linting script |
| `gdlintrc` | gdlint configuration |
| `.gutconfig.json` | GUT test framework configuration |
| `dist/installer.iss` | Windows installer (Inno Setup) |
| `tests/unit/` | Unit tests (no server needed) |
| `tests/accordkit/` | Integration tests (need accordserver) |
| `tests/livekit/` | LiveKit tests (no server needed) |
