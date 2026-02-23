---
description: Run tests, fix lint errors, break down large files, and clean up debug artifacts
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(./test.sh:*), Bash(bash lint.sh:*), Bash(wc:*), Bash(git status:*), Bash(git diff:*), Task
---

You are performing a "spring clean" of the daccord codebase. Work through each phase in order. Fix issues as you go rather than just reporting them.

## Phase 1: Run Tests

Run the unit tests (no server needed):

```
./test.sh unit
```

If any tests fail:
1. Read the failing test file and the source file it tests
2. Determine whether the bug is in the source code or the test
3. Fix the root cause (prefer fixing source code bugs; only fix tests if the test expectation is wrong)
4. Re-run `./test.sh unit` to confirm the fix

Do NOT skip failing tests or mark them as expected failures. Every test should pass.

## Phase 2: Run Linter

Run the project linter:

```
bash lint.sh
```

Review the output for:
- **Naming convention violations** -- Rename files/folders to match the project convention (snake_case)
- **gdlint errors** -- Fix GDScript static analysis issues (unused variables, naming, trailing whitespace, line length, etc.)
- **Complexity warnings** -- Note any high-complexity functions for Phase 3

Fix all lint issues directly in the source files. Re-run `bash lint.sh` to confirm all issues are resolved.

## Phase 3: Break Down Large Files

Find all `.gd` files over 800 lines:

```
wc -l scripts/**/*.gd scenes/**/*.gd
```

For each file over 800 lines:
1. Read the file and identify logical groupings of functionality
2. Extract cohesive groups into new files (helper classes, sub-components, or utility scripts)
3. Update all references to the extracted code
4. Keep the public API of the original file intact -- other files should not need changes beyond imports

Common extraction patterns:
- Large `match` or `if/elif` blocks handling different cases -> separate handler functions or scripts
- Utility/helper methods that don't use instance state -> standalone utility script
- Signal handler methods that form a logical group -> sub-component script
- Data transformation / parsing logic -> dedicated parser script

Do NOT extract code if it would create circular dependencies or files under ~50 lines.

## Phase 4: Clean Up Debug Logs and Build Artifacts

### Debug logs
Search for debug print statements that should not be in production code:

- `print(` statements that are clearly debug/temporary (e.g., "DEBUG", "TODO", "FIXME", "test", variable dumps)
- `print_debug(` calls
- Commented-out `print(` statements

Remove them. Keep `print(` statements that are intentional logging (error messages, warnings, startup info).

Use your judgement: a `print("Error: ...")` or `push_error(...)` is intentional. A `print(some_variable)` or `print("HERE")` is debug noise.

### Build artifacts
Search for and remove:
- `.import` files for assets that no longer exist
- Orphaned `.uid` files with no corresponding `.gd` or `.tscn`
- Temporary files (`*.tmp`, `*.bak`, `*.orig`)
- Empty directories under `scenes/` and `scripts/`

Do NOT delete:
- `.godot/` directory contents (managed by Godot)
- `addons/` directory contents
- Any file tracked by git that isn't clearly an artifact

## Phase 5: Verify

After all phases:
1. Run `./test.sh unit` one final time to confirm nothing is broken
2. Run `bash lint.sh` one final time to confirm it's clean
3. Summarize what was done:
   - Number of test failures fixed
   - Number of lint issues fixed
   - Files that were broken down (with before/after line counts)
   - Debug logs and artifacts removed
