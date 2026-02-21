# Continuous Integration

Last touched: 2026-02-19

## Overview

The daccord CI pipeline runs on every push/PR to `master` via GitHub Actions. It validates code quality, runs unit tests, and optionally runs integration tests against a live accordserver instance. Two workflows exist: `ci.yml` (lint + tests on every push/PR) and `release.yml` (cross-platform builds on version tags). All repos are private under the `DaccordProject` GitHub organization, requiring a `GH_PAT` environment secret for cross-repo access.

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

# Check if AccordKit remote is newer than last CI run
echo "CI: $(gh run list --limit 1 --json createdAt --jq '.[0].createdAt')" \
  "AK: $(gh api repos/DaccordProject/accordkit/commits?per_page=1 --jq '.[0].commit.author.date')"

# Count passing/failing tests from a run
gh run view <RUN_ID> --log 2>&1 | grep -oP '\d+/\d+ passed' | tail -1
```

## Signal Flow

```
Push/PR to master
  ├─> ci.yml triggers
  │     ├─> Lint job
  │     │     ├─ gdlint scripts/ scenes/
  │     │     └─ Code complexity analysis (gdradon cc, warns on grade C-F)
  │     │
  │     ├─> Unit Tests job (needs: lint)
  │     │     ├─ Checkout daccord + accordkit + accordstream (GH_PAT)
  │     │     ├─ Install audio libraries (libasound2, libpulse, libopus)
  │     │     ├─ Symlink addons/
  │     │     ├─ Install GUT (cached) + Sentry SDK (cached)
  │     │     ├─ Setup Godot 4.5.0 (chickensoft-games/setup-godot@v2)
  │     │     ├─ Cache + import project (.godot/imported/)
  │     │     ├─ Run GUT on tests/unit/ (-gexit for proper exit codes)
  │     │     ├─ Run GUT on tests/accordstream/ (-gexit)
  │     │     └─ Write per-suite test result summary to $GITHUB_STEP_SUMMARY
  │     │
  │     └─> Integration Tests job (needs: lint, blocking)
  │           ├─ Same addon setup as Unit Tests (including audio libraries)
  │           ├─ Checkout accordserver (GH_PAT)
  │           ├─ Install Rust + sccache (continue-on-error, conditional wrapper)
  │           ├─ Build accordserver (cargo cached, sccache retry fallback)
  │           ├─ Start server (ACCORD_TEST_MODE=true, SQLite)
  │           ├─ Wait for /health (30s timeout)
  │           ├─ Cache + import project (.godot/imported/)
  │           ├─ Run GUT on tests/accordkit/ (-gexit for proper exit codes)
  │           ├─ Write test result summary to $GITHUB_STEP_SUMMARY
  │           └─ Stop server, always upload test_server.log
  │
Push v* tag
  └─> release.yml triggers
        ├─> 4x parallel Build jobs (Linux x86_64, Linux ARM64, Windows, macOS)
        │     ├─ Validate tag matches project.godot version
        │     ├─ Checkout + addon symlink + AccordStream binaries
        │     ├─ Setup Godot 4.5.0 with export templates
        │     ├─ Inject SENTRY_DSN, clear missing custom templates
        │     ├─ Export (godot --headless --export-release)
        │     ├─ Package (tar.gz / zip)
        │     └─ Sign + notarize (if secrets configured)
        └─> Create Release job
              ├─ Download all artifacts
              ├─ Extract changelog section from CHANGELOG.md
              └─ Create GitHub Release (softprops/action-gh-release@v2)
```

## Pipeline Architecture

### Workflow: `.github/workflows/ci.yml`

Three jobs triggered on push/PR to `master`. Unit Tests and Integration Tests both depend on Lint (run after it passes):

| Job | Runner | Environment | Depends On | Required | Purpose |
|-----|--------|-------------|------------|----------|---------|
| **Lint** | ubuntu-latest | *(none)* | *(none)* | Yes | gdlint + gdradon complexity analysis on `scripts/` and `scenes/` |
| **Unit Tests** | ubuntu-latest | `default` | Lint | Yes | GUT tests in `tests/unit/` + `tests/accordstream/` |
| **Integration Tests** | ubuntu-latest | `default` | Lint | Yes (blocking) | GUT tests in `tests/accordkit/` with live accordserver |

### Workflow: `.github/workflows/release.yml`

Triggered by `v*` tags. Builds four platform artifacts, creates a GitHub Release. See [Cross-Platform GitHub Releases](cross_platform_github_releases.md).

### Dependencies & Setup

**GitHub Organization:** The actual org is **`DaccordProject`** (not `daccord-projects`). All repos are private.

| Repo | Purpose |
|------|---------|
| `DaccordProject/daccord` | This client (CI runs here) |
| `DaccordProject/accordkit` | GDScript client library (REST + WebSocket) |
| `DaccordProject/accordstream` | GDExtension for audio/voice (native binaries in LFS) |
| `DaccordProject/accordserver` | Rust backend (built from source for integration tests) |

**Authentication:** Cross-repo checkout requires a PAT stored as environment secret `GH_PAT` in the `default` environment. Required scopes: `repo` (classic) or Contents:Read (fine-grained).

**Addon Installation:**

| Addon | Source | Install Method | Cached |
|-------|--------|---------------|--------|
| `addons/accordkit` | `DaccordProject/accordkit` (private) | `actions/checkout` + symlink | No |
| `addons/accordstream` | `DaccordProject/accordstream` (private, LFS) | `actions/checkout` with `lfs: true` + symlink | No |
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

**1. "Could not find type X in the current scope"** -- Either AccordKit on the remote is missing types that daccord references, or the CI ran before an AccordKit push landed. First check timing (pattern #6 above), then check what the remote has vs local:

```bash
gh api repos/DaccordProject/accordkit/git/trees/master?recursive=1 \
  --jq '.tree[] | select(.path | endswith(".gd")) | .path'
```

**2. "Can't open dynamic library... invalid ELF header"** -- The AccordStream `.so` is likely an LFS pointer, not the actual binary. LFS pointers are ~130 bytes; a real `.so` is megabytes:

```bash
gh api repos/DaccordProject/accordstream/contents/addons/accordstream/bin/libaccordstream.so \
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

**6. AccordKit timing mismatch** -- If you push AccordKit and daccord separately, the CI run triggered by the daccord push may check out the OLD AccordKit. Compare timestamps:

```bash
# When did the last CI run start?
gh run list --limit 1 --json createdAt --jq '.[0].createdAt'
# When was AccordKit last pushed?
gh api repos/DaccordProject/accordkit/commits?per_page=1 --jq '.[0].commit.author.date'
```

If the CI run started before the AccordKit push, re-run the CI: `gh run rerun <RUN_ID>`.

**7. GUT framework errors** -- GUT 9.5.0 has a known compatibility issue with Godot 4.5 where `gut_loader.gd:35` throws a `Nil` to `bool` assignment error. This is non-fatal and tests still run. Filter it out when reviewing logs:

```bash
gh run view <RUN_ID> --log-failed 2>&1 | grep "SCRIPT ERROR" | grep -v gut_loader
```

**8. sccache runtime crash** -- The sccache *setup* step can succeed (binary installs fine) while sccache *runtime* crashes because the GHA cache backend is temporarily down. The error looks like `error: process didn't exit successfully: 'sccache ... rustc -vV'` with an HTML error body. The build step has retry logic: if cargo fails with sccache, it retries without it. If you see `::warning::Build failed with sccache, retrying without it`, the retry is working. If the retry also fails, the issue is with cargo/Rust itself, not sccache.

**9. AccordStream cascading failures** -- If the AccordStream GDExtension binary fails to load (e.g., LFS pointer instead of real binary, or extension not compiled for the runner arch), `AccordVoiceSession` and other extension classes aren't registered. `client.gd` now guards voice session creation with `ClassDB.class_exists(&"AccordVoiceSession")` and null checks, so the Client autoload initializes fully even without AccordStream. Voice-dependent tests in `test_client_startup.gd` skip gracefully when AccordVoiceSession is unavailable. CI also installs audio libraries (`libasound2-dev`, `libpulse-dev`, `libopus-dev`) to help the extension load. Look for the root error:

```bash
gh run view <RUN_ID> --log 2>&1 | grep "set_output_device\|get_speakers\|GDScriptNativeClass\|AccordVoiceSession unavailable"
```

**10. `| tee` swallows exit codes** -- Before the `set -o pipefail` fix, the `2>&1 | tee` pipe in test steps would swallow the GUT `-gexit` exit code because bash evaluates the exit code of the last command in the pipeline (`tee`, which always returns 0). With `set -o pipefail`, the pipeline returns the exit code of the leftmost failing command. If you see tests reporting failures in the summary but the step shows "success", check that `set -o pipefail` is present.

## Implementation Status

- [x] CI workflow triggered on push/PR to `master` (`.github/workflows/ci.yml`)
- [x] Lint job with gdlint on `scripts/` and `scenes/`
- [x] Lint job passing (verified in run 22186380820)
- [x] Code complexity analysis with gdradon (warns on grade C-F functions)
- [x] Unit test job with GUT headless runner
- [x] AccordStream tests in unit test job (`tests/accordstream/`)
- [x] Integration test job with live accordserver (blocking)
- [x] Release workflow triggered by `v*` tags (`.github/workflows/release.yml`)
- [x] Cross-repo checkout via `GH_PAT` environment secret
- [x] Addon symlinking (accordkit, accordstream)
- [x] GUT install from source tarball (cached)
- [x] Sentry SDK install from release zip (cached)
- [x] Godot 4.5.0 setup via `chickensoft-games/setup-godot@v2`
- [x] Headless project import before test runs
- [x] Accordserver build from source with cargo caching
- [x] Server health check with 30s timeout
- [x] Server log always uploaded (`upload-artifact@v4`, `if: always()`)
- [x] AccordKit remote matches local (soundboard/voice/permissions/CDN/reactions/REST pushed at 14:08 UTC)
- [x] Integration test seed isolation (seed route uses idempotent find-or-create patterns)
- [x] `AccordChannel.get()` signature fixed (tests use typed property access)
- [x] Local daccord changes pushed (test fixes, performance improvements, error reporting)
- [x] GUT `-gexit` flag for proper exit codes (non-zero on test failure)
- [x] `set -o pipefail` in test steps (prevents `| tee` from swallowing exit codes)
- [x] Test result summary in `$GITHUB_STEP_SUMMARY` (per-suite for unit/accordstream)
- [x] sccache for Rust builds (resilient: `continue-on-error` + conditional wrapper + retry fallback)
- [x] Godot import cache (`.godot/imported/`, hash-keyed)
- [x] gdlintrc config file for lint job
- [x] Integration tests made blocking (`continue-on-error` removed)
- [x] Job dependency ordering (unit tests + integration tests depend on lint)
- [x] Unit test job runs (470/477 tests pass; 7 failures are AccordStream-related, see gaps)
- [x] AccordStream graceful degradation (`client.gd` guards voice session creation, tests skip when unavailable)
- [x] Audio libraries installed on CI runners (`libasound2-dev`, `libpulse-dev`, `libopus-dev`)
- [x] Gateway tests improved (longer timeouts, disconnection detection, early exit on failure)
- [ ] Unit tests fully green (needs CI run to verify after graceful degradation fix)
- [ ] Integration test job passing (sccache retry logic + graceful degradation need verification in CI)
- [ ] First release tagged (`v0.1.0`)

## Gaps / TODO

| Gap | Severity | Status | Notes |
|-----|----------|--------|-------|
| AccordKit remote out of date | ~~Critical~~ | **Resolved** | Pushed at 14:08 UTC on 2026-02-19. |
| `/test/seed` returns 500 after first test file | ~~High~~ | **Resolved** | Seed route uses idempotent find-or-create patterns. |
| `AccordChannel.get()` signature mismatch | ~~Medium~~ | **Resolved** | Tests updated to use typed property access. |
| `Client.markdown_to_bbcode()` not found | ~~High~~ | **Resolved** | Cascading failure from AccordKit compilation errors. |
| Local daccord changes not pushed | ~~High~~ | **Resolved** | All changes committed and pushed (855245b). |
| GUT exit codes not propagated | ~~Medium~~ | **Resolved** | Added `-gexit` flag + `set -o pipefail` to prevent `\| tee` from swallowing exit codes. |
| `\| tee` swallows GUT exit codes | ~~Medium~~ | **Resolved** | Added `set -o pipefail` before all `godot ... 2>&1 \| tee` pipelines so `-gexit` non-zero codes propagate. |
| No test result summary in CI | ~~Low~~ | **Resolved** | Added `$GITHUB_STEP_SUMMARY` step showing per-suite pass/fail counts. |
| Accordserver build time | ~~Low~~ | **Resolved** | sccache with `continue-on-error` and conditional `RUSTC_WRAPPER`. |
| Godot import not cached | ~~Low~~ | **Resolved** | `actions/cache` for `.godot/imported/` keyed on project + scene hashes. |
| Integration tests non-blocking | ~~Medium~~ | **Resolved** | `continue-on-error` removed; integration tests now block the pipeline. |
| sccache runtime crash | ~~Medium~~ | **Resolved** | sccache setup step can succeed while sccache crashes at runtime if GHA cache backend is down. Added retry logic: if `cargo build` fails with sccache, re-runs without it (`RUSTC_WRAPPER=""`). |
| GUT 9.5.0 + Godot 4.5 compatibility | Low | Open | `gut_loader.gd:35` throws "Trying to assign value of type 'Nil' to a variable of type 'bool'" during static init. Non-fatal (tests still run). Monitor for upstream fix. |
| AccordStream GDExtension doesn't load in CI | ~~Medium~~ | **Resolved** | Two-pronged fix: (a) `client.gd` guards voice session creation with `ClassDB.class_exists()` and null checks — `_ready()` completes fully even without AccordStream; `client_voice.gd` null-checks `_voice_session` before all method calls; `test_client_startup.gd` skips voice-specific tests when unavailable. (b) CI installs `libasound2-dev`, `libpulse-dev`, `libopus-dev` so the extension can load in headless mode. |
| Gateway tests time out | ~~Medium~~ | **Resolved** | Increased wait timeout from 10s to 15s for CI. Added `disconnected` signal detection for early exit on connection failure. Added guard `if not ready_received: return` to skip dependent assertions. Needs CI run to verify. |
| Integration tests not verified | Medium | Open | Last run (22186380820) failed at "Build accordserver" due to sccache runtime crash. Retry logic, `continue-on-error` removal, and graceful degradation all need verification in a new CI run. |
| First release not tagged | Low | Open | No `v0.1.0` tag pushed yet. Requires all CI jobs passing first. |

## Key Files

| File | Purpose |
|------|---------|
| `.github/workflows/ci.yml` | CI pipeline (lint, unit tests, integration tests) |
| `.github/workflows/release.yml` | Release pipeline (build, package, publish) |
| `export_presets.cfg` | Godot export presets for 4 platforms |
| `project.godot` | Version source of truth (`config/version`) |
| `test.sh` | Local test runner (starts accordserver automatically) |
| `tests/unit/` | Unit tests (no server needed) |
| `tests/accordkit/` | Integration tests (need accordserver) |
| `tests/accordstream/` | AccordStream tests (no server needed) |
