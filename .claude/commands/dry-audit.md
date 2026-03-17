---
description: Review changed code for reuse, quality, and efficiency, then fix any issues found
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(wc:*), Bash(git diff:*), Task, Agent
---

You are auditing the daccord codebase for repetitive (WET) code and opportunities to DRY it up. This is a Godot 4.5 GDScript project — lean on Godot-native patterns (Resources, base scenes, utility nodes, `class_name`, scene inheritance) rather than pure-code abstractions.

## What to look for

Scan all `.gd` files under `scripts/` and `scenes/` (skip `addons/`, `tests/`, `.godot/`).

### 1. Duplicated code blocks

Search for near-identical blocks of code appearing in 2+ files. Common culprits:

- **Dialog setup boilerplate**: Repeated patterns for creating/configuring dialogs (setting title, connecting confirmed/canceled signals, adding to tree, showing)
- **REST call + error handling**: Repeated `await Client.fetch.some_endpoint()` → check result → show error toast patterns
- **Signal wiring**: Identical `connect()` chains repeated across files
- **Theme/style application**: Same `add_theme_*_override()` calls duplicated across UI scripts
- **Permission checks**: Repeated `Client.permissions.has_permission(...)` guard blocks with similar structure
- **Node traversal/cleanup**: Repeated loops doing `for child in container.get_children(): child.queue_free()`
- **Popup/toast patterns**: Identical error display or confirmation flows

### 2. Copy-paste with minor variation

Look for blocks that are structurally identical but differ only in:
- String literals (endpoint names, signal names, property keys)
- Variable names
- One or two parameters

These are strong candidates for a shared helper function, utility method, or parameterized Resource.

### 3. Verbose code that Godot can simplify

- **Manual property copying** between objects → use `Resource` subclasses or dictionaries
- **Long chains of `if/elif` on type** → use polymorphism, `match`, or a dispatch dictionary
- **Manually building identical node structures** in multiple scripts → use a shared `.tscn` scene with `instantiate()`
- **Repeated animation/tween setup** → extract to a utility function or AnimationPlayer resource
- **Repeated input handling patterns** → consolidate into shared input handler
- **Manual serialization/deserialization** that mirrors a model's properties → use `Resource.duplicate()` or a generic converter
- **Repeated `get_node()` / `$Path` chains** that could be `@onready` vars or `@export NodePath`

### 4. Opportunities for Godot-native DRY patterns

Suggest these Godot patterns where appropriate:

- **Custom Resources (`class_name` + `extends Resource`)**: For shared data shapes passed between systems. Cheaper than dictionaries, typed, serializable, inspector-editable.
- **Scene inheritance**: If multiple `.tscn` scenes share a common structure, use an inherited scene rather than duplicating nodes.
- **Base class scripts**: If multiple scripts share 50%+ of their methods, extract a common base class.
- **Autoload utility methods**: Small, stateless helpers that are called from 3+ files belong on an existing autoload (or a new lightweight utility autoload).
- **`@export` and `@export_group`**: Replace hardcoded values that vary per-instance with exports, reducing the need for separate scripts.
- **Callable/lambda patterns**: Replace repetitive signal-connect-to-one-liner patterns with inline callables.
- **`set()` and `get()` with StringName**: When setting the same group of properties on different objects, use a loop over property names.

### 5. Line count reduction opportunities

Beyond deduplication, look for:

- **Unnecessary intermediate variables** that are used exactly once on the next line
- **Verbose null/empty checks** that can use GDScript shorthand (`if not array:` instead of `if array.size() == 0:`)
- **Redundant `else` after `return`/`continue`/`break`**
- **Multi-line expressions** that fit cleanly on one line within the 100-char limit
- **Repeated dictionary key access** that should be extracted to a local var
- **Chained `if` guards** that can be combined with `and`/`or`
- **Explicit boolean returns** like `if x: return true else: return false` → `return x`

### 6. What to IGNORE

- **Intentional repetition for readability**: Sometimes two similar blocks are clearer than one abstracted version. If the duplication is 3 lines or fewer and the abstraction would obscure intent, skip it.
- **Test files**: Tests are allowed to be repetitive for clarity.
- **Addon code**: Do not modify `addons/` — it's external.
- **Premature abstraction**: Don't suggest extracting code that only appears once just because it *might* be reused someday.

## How to report

For each opportunity found, report:

1. **Files and line ranges** — all locations where the duplication occurs
2. **Pattern name** — short label (e.g., "Dialog setup boilerplate", "REST error handling")
3. **Occurrence count** — how many times this pattern appears
4. **Lines saved (estimate)** — rough count of lines that would be removed after consolidation
5. **Suggested fix** — specific, actionable approach:
   - Name the helper/base class/resource to create
   - Show a brief sketch of the shared code (3-5 lines max)
   - List which files would call it
   - Mention the Godot pattern being used (Resource, scene inheritance, utility function, etc.)

## Output format

Group findings by estimated impact (highest lines-saved first):

```
## High Impact (20+ lines saved)

### "Dialog setup boilerplate" — 6 occurrences
**Files:**
- scenes/admin/ban_dialog.gd:30-52
- scenes/admin/report_dialog.gd:28-50
- scenes/admin/nickname_dialog.gd:25-44
- ...
**Lines saved:** ~90
**Fix:** Add `DialogHelper.show_dialog(parent, title, on_confirm)` utility method to a shared script. Handles signal wiring, tree insertion, and popup display. Each call site reduces from ~15 lines to 1-2.

---

## Medium Impact (5-19 lines saved)
...

## Low Impact (<5 lines saved)
...

## Quick Wins (single-line simplifications)

| File:Line | Before | After |
|-----------|--------|-------|
| `scenes/foo.gd:42` | `if arr.size() == 0:` | `if not arr:` |
| ... | ... | ... |

## Summary
- X high-impact patterns (Y total lines saveable)
- X medium-impact patterns (Y total lines saveable)
- X low-impact patterns (Y total lines saveable)
- X quick wins
- **Total estimated line reduction: ~N lines**
```

## Execution

1. Use Grep to find common repeated patterns across `scripts/` and `scenes/` (start with high-frequency patterns: `add_child`, `queue_free`, `add_theme_`, `push_error`, dialog/popup patterns)
2. For each cluster of matches, read the surrounding context to confirm true duplication vs coincidental similarity
3. Identify the minimal shared abstraction that covers all occurrences without over-engineering
4. Compile the report grouped by impact
5. Present findings to the user — do NOT make any code changes unless explicitly asked
