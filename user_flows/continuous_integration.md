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
  │     ├─> Lint job (gdlint scripts/ scenes/)
  │     ├─> Unit Tests job
  │     │     ├─ Checkout daccord + accordkit + accordstream (GH_PAT)
  │     │     ├─ Symlink addons/
  │     │     ├─ Install GUT (cached) + Sentry SDK (cached)
  │     │     ├─ Setup Godot 4.6.0 (chickensoft-games/setup-godot@v2)
  │     │     ├─ Import project (godot --headless --import .)
  │     │     └─ Run GUT on tests/unit/
  │     └─> Integration Tests job (continue-on-error)
  │           ├─ Same addon setup as Unit Tests
  │           ├─ Checkout accordserver (GH_PAT)
  │           ├─ Install Rust + build accordserver (cargo cached)
  │           ├─ Start server (ACCORD_TEST_MODE=true, SQLite)
  │           ├─ Wait for /health (30s timeout)
  │           ├─ Run GUT on tests/accordkit/
  │           └─ Stop server, upload test_server.log on failure
  │
Push v* tag
  └─> release.yml triggers
        ├─> 4x parallel Build jobs (Linux x86_64, Linux ARM64, Windows, macOS)
        │     ├─ Validate tag matches project.godot version
        │     ├─ Checkout + addon symlink + AccordStream binaries
        │     ├─ Setup Godot 4.6.0 with export templates
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

Three parallel jobs triggered on push/PR to `master`:

| Job | Runner | Environment | Required | Purpose |
|-----|--------|-------------|----------|---------|
| **Lint** | ubuntu-latest | *(none)* | Yes | gdlint on `scripts/` and `scenes/` |
| **Unit Tests** | ubuntu-latest | `default` | Yes | GUT tests in `tests/unit/` |
| **Integration Tests** | ubuntu-latest | `default` | No (`continue-on-error`) | GUT tests in `tests/accordkit/` with live accordserver |

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

**Godot Version:** `4.6.0` (must be full semver for `chickensoft-games/setup-godot@v2`). Renderer: GL Compatibility. Export templates needed for release only.

### Caching Strategy

| Cache | Key | Path | Benefit |
|-------|-----|------|---------|
| GUT framework | `gut-9.5.0` | `addons/gut` | Skip 2s download |
| Sentry SDK | `sentry-godot-1.3.2` | `addons/sentry` | Skip 5s download |
| Rust cargo registry | `Linux-cargo-{Cargo.lock hash}` | `~/.cargo/registry`, `~/.cargo/git`, `.accordserver_repo/target` | Skip multi-minute server build |

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

**7. GUT framework errors** -- GUT 9.5.0 has a known compatibility issue with Godot 4.6 where `gut_loader.gd:35` throws a `Nil` to `bool` assignment error. This is non-fatal and tests still run. Filter it out when reviewing logs:

```bash
gh run view <RUN_ID> --log-failed 2>&1 | grep "SCRIPT ERROR" | grep -v gut_loader
```

## Implementation Status

- [x] CI workflow triggered on push/PR to `master` (`.github/workflows/ci.yml`)
- [x] Lint job with gdlint on `scripts/` and `scenes/`
- [x] Unit test job with GUT headless runner
- [x] Integration test job with live accordserver (continue-on-error)
- [x] Release workflow triggered by `v*` tags (`.github/workflows/release.yml`)
- [x] Cross-repo checkout via `GH_PAT` environment secret
- [x] Addon symlinking (accordkit, accordstream)
- [x] GUT install from source tarball (cached)
- [x] Sentry SDK install from release zip (cached)
- [x] Godot 4.6.0 setup via `chickensoft-games/setup-godot@v2`
- [x] Headless project import before test runs
- [x] Accordserver build from source with cargo caching
- [x] Server health check with 30s timeout
- [x] Server log upload on failure (`upload-artifact@v4`)
- [x] Lint job passing
- [x] AccordKit remote matches local (soundboard/voice/permissions/CDN/reactions/REST pushed at 14:08 UTC)
- [x] Integration test seed isolation (seed route uses idempotent find-or-create patterns)
- [x] `AccordChannel.get()` signature fixed (local test changes use property access; needs push)
- [ ] Local daccord changes pushed (test fixes, performance improvements, error reporting)
- [ ] Unit test job passing (needs push + CI run; should pass once AccordKit types resolve)
- [ ] Integration test job passing (needs push + CI run; gateway timeouts may persist)
- [ ] AccordStream binary loads in CI (LFS config correct; may need PAT LFS scope)
- [ ] Integration tests made blocking (remove `continue-on-error` once passing)
- [ ] sccache for Rust builds
- [ ] First release tagged (`v0.1.0`)

## Gaps / TODO

| Gap | Severity | Status | Notes |
|-----|----------|--------|-------|
| AccordKit remote out of date | ~~Critical~~ | **Resolved** | Pushed at 14:08 UTC on 2026-02-19 (soundboard, voice, multipart, auth, permissions, CDN, reactions, REST). Last CI run was at 13:24 UTC (44 min earlier), so the CI hasn't tested against the updated AccordKit yet. All "AccordSound not found" / "sound() not found" / "update_voice_state too many args" errors are from this timing gap. |
| `/test/seed` returns 500 after first test file | ~~High~~ | **Resolved** | Seed route uses idempotent find-or-create patterns. `INSERT OR IGNORE` on members prevents duplicates. Token rotation is safe. |
| `AccordChannel.get()` signature mismatch | ~~Medium~~ | **Resolved (local)** | Fixed in local working tree (`test_spaces_api.gd`, `test_users_api.gd`, `test_members_api.gd`, `test_full_lifecycle.gd`) to use property access on typed RefCounted objects. **Not yet pushed** -- must be committed and pushed for CI to pass. |
| `Client.markdown_to_bbcode()` not found | ~~High~~ | **Resolved** | Was a cascading failure from AccordKit compilation errors. Will resolve once CI runs against updated AccordKit. |
| Local daccord changes not pushed | High | Open | Test fixes, member index performance improvements, regex caching, error reporting refactoring all exist locally but haven't been committed/pushed. CI will fail until these are pushed alongside the AccordKit update. |
| GUT 9.5.0 + Godot 4.6 compatibility | Low | Open | `gut_loader.gd:35` throws "Trying to assign value of type 'Nil' to a variable of type 'bool'" during static init. Non-fatal (tests still run), but indicates a compatibility issue with `ProjectSettings.get()` returning null for an unset `exclude_addons` property. Monitor for upstream fix. |
| AccordStream binary invalid in CI | Medium | Open | LFS config is correct (`.gitattributes` tracks `.so/.dll/.dylib`, CI uses `lfs: true`). Local binary is a real 28MB ELF. Causes `set_output_device() not found in base GDScriptNativeClass` because the extension doesn't load. Check that `GH_PAT` has LFS read access, or that the accordstream repo's LFS storage quota isn't exceeded. |
| Gateway tests time out | Medium | Open | `test_gateway_connect.gd` and `test_gateway_events.gd` fail because the bot never receives the `ready` signal within 10s. The WebSocket gateway connection + identify handshake may have server-side issues. Needs CI run to verify after AccordKit update. |
| Integration tests non-blocking | Medium | Open | `continue-on-error: true` means integration failures don't fail the CI pipeline. Should be removed once integration tests pass reliably. |
| Accordserver build time | Low | Open | Cold Rust build takes several minutes; cached ~1 minute. Could use `sccache` (`RUSTC_WRAPPER=sccache`) with GHA cache backend. |
| Godot import not cached | Low | Open | `godot --headless --import .` re-imports every run. Caching `.godot/imported/` could save time but may cause stale import issues. |

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
