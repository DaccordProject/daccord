# Continuous Integration

Priority: 39
Depends on: Test Coverage
Status: Complete

CI runs on every PR to `master` via GitHub Actions. Two workflows: `ci.yml` (lint + unit tests + integration tests) and `release.yml` (CI gate + cross-platform builds on `v*` tags). AccordKit is in-tree, so no external checkout needed.

## Key Files

| File | Role |
|------|------|
| `.github/workflows/ci.yml` | CI pipeline: lint, unit tests, integration tests |
| `.github/workflows/release.yml` | Release pipeline: CI gate, build, package, installer, publish |
| `test.sh` | Local test runner (starts accordserver automatically) |
| `lint.sh` | Local linting script |
| `export_presets.cfg` | Godot export presets for all platforms |
| `project.godot` | Version source of truth (`config/version`) |
| `gdlintrc` | gdlint configuration |
| `.gutconfig.json` | GUT test framework configuration |
| `dist/installer.iss` | Windows installer (Inno Setup) |
| `tests/unit/` | Unit tests (no server needed) |
| `tests/accordkit/` | Integration tests (need accordserver) |
| `tests/livekit/` | LiveKit adapter tests (no server needed) |
