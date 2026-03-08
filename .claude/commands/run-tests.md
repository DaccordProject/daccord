---
description: Run lint, unit tests, and integration tests; enforce 800-line file limit
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(./test.sh:*), Bash(bash lint.sh:*), Bash(wc:*), Bash(git diff:*), Task
---

You are running the full test and lint pipeline for the daccord codebase. Work through each phase in order. Fix issues as you go rather than just reporting them.

## Phase 1: Run Linter

```
bash lint.sh
```

Review the output for:
- **gdlint errors** — Fix GDScript static analysis issues (unused variables, naming, trailing whitespace, line length, etc.)
- **Naming convention violations** — Rename files/folders to match snake_case convention
- **Line length** — Lines over 100 characters must be wrapped

Fix all lint issues directly in the source files. Re-run `bash lint.sh` to confirm clean output before moving on.

## Phase 2: Run Unit Tests

Unit tests require no server. Run:

```
./test.sh unit
```

If any tests fail:
1. Read the failing test file and the source file it tests
2. Determine whether the bug is in the source code or the test
3. Fix the root cause (prefer fixing source code bugs; only fix tests if the test expectation is genuinely wrong)
4. Re-run `./test.sh unit` to confirm the fix

Do NOT skip failing tests or mark them as expected failures. Every test must pass.

## Phase 3: Run Integration Tests

Integration tests require an accordserver instance. Run:

```
./test.sh integration
```

The test runner starts the server automatically. If any tests fail:
1. Check whether the failure is a transient seed/cascade issue (re-run once to confirm)
2. If repeatable, read the failing test and the relevant AccordKit source
3. Fix the root cause in the source code or test
4. Re-run `./test.sh integration` to confirm

## Phase 4: Enforce 800-Line File Limit

Find all GDScript files over 800 lines:

```
wc -l **/*.gd
```

Or search recursively:

```
find . -name "*.gd" -not -path "./.godot/*" -not -path "./addons/gut/*" | xargs wc -l | sort -rn | head -20
```

For each file over 800 lines:
1. Read the file and identify logical groupings
2. Extract cohesive groups into new files (helper classes, secondary scripts, utility modules)
3. Update all references to the extracted code
4. Keep the original file's public API intact — other files should not need changes beyond imports

Common extraction patterns:
- Large `match`/`if-elif` blocks for different cases → separate handler scripts
- Utility/helper methods with no instance state → standalone utility script
- Signal handler groups that form a logical cluster → sub-component script
- Data transformation or parsing logic → dedicated parser/converter script

Do NOT extract code if it would create circular dependencies or produce files under ~50 lines.

## Phase 5: Verify

After all phases complete:
1. Run `bash lint.sh` — must be clean
2. Run `./test.sh unit` — all tests must pass
3. Run `./test.sh integration` — all tests must pass
4. Confirm no `.gd` files remain over 800 lines

Summarize what was fixed:
- Lint issues resolved (count and categories)
- Unit test failures fixed
- Integration test failures fixed
- Files refactored to stay under 800 lines (with before/after line counts)
