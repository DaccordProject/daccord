---
description: Search the codebase for opportunities to convert programmatic UI/node construction into .tscn scenes
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(wc:*), Bash(git diff:*), Task, Agent
---

You are auditing the daccord codebase for GDScript code that programmatically builds node trees or UI controls that would be more maintainable as `.tscn` scene files.

## What to look for

Scan all `.gd` files under `scripts/` and `scenes/` for these patterns:

### 1. Node instantiation via `.new()`

Search for calls like `SomeNodeType.new()` where the type is a built-in Godot node (especially UI controls). Common examples:

- Layout containers: `HBoxContainer.new()`, `VBoxContainer.new()`, `GridContainer.new()`, `MarginContainer.new()`, `PanelContainer.new()`, `ScrollContainer.new()`, `HSplitContainer.new()`, `VSplitContainer.new()`, `FlowContainer.new()`, `CenterContainer.new()`
- Controls: `Label.new()`, `Button.new()`, `TextureRect.new()`, `RichTextLabel.new()`, `LineEdit.new()`, `TextEdit.new()`, `CheckBox.new()`, `OptionButton.new()`, `SpinBox.new()`, `ProgressBar.new()`, `Slider.new()`, `ColorRect.new()`, `Panel.new()`, `TabContainer.new()`
- Dialogs: `AcceptDialog.new()`, `ConfirmationDialog.new()`, `FileDialog.new()`, `PopupMenu.new()`, `PopupPanel.new()`
- Other: `Node.new()`, `Control.new()`, `Node2D.new()`, `Sprite2D.new()`, `Timer.new()`, `HTTPRequest.new()`

### 2. Tree-building patterns

Look for sequences where code creates a node, configures its properties, and adds it as a child:

```gdscript
var container = VBoxContainer.new()
container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
container.add_theme_constant_override("separation", 8)
some_parent.add_child(container)

var label = Label.new()
label.text = "Something"
container.add_child(label)
```

This pattern — especially when it spans 5+ lines or builds 2+ nodes — is a strong candidate for a `.tscn` scene.

### 3. Bulk property assignment on created nodes

Look for blocks where multiple properties are set on a freshly created node:
- `.name = ...`
- `.text = ...`
- `.size_flags_*`
- `.custom_minimum_size = ...`
- `.anchors_preset = ...`
- `.add_theme_*_override(...)`
- `.tooltip_text = ...`
- `.alignment = ...`
- `.visible = ...`
- `.modulate = ...`
- `.mouse_filter = ...`

### 4. What to IGNORE (not candidates)

Skip these — they are appropriate to keep in code:

- **Dynamic/data-driven nodes**: Nodes created in a loop based on runtime data (e.g., populating a list of messages, members, search results). The *template* for these may be a candidate, but the loop itself is fine.
- **Single-node additions**: Adding one `Timer.new()` or one `HTTPRequest.new()` with minimal config is fine in code.
- **Nodes already backed by a scene**: If the code does `var item = SomeScene.instantiate()`, that's already using a scene — skip it.
- **Test files**: Ignore `tests/` directory.
- **Addon internals**: Ignore `addons/` directory.

## How to report

For each candidate found, report:

1. **File and line range** — e.g., `scenes/admin/ban_dialog.gd:45-78`
2. **What's being built** — brief description (e.g., "Builds a confirmation panel with label + two buttons")
3. **Node count** — how many nodes are created programmatically in that block
4. **Severity** — rate the extraction opportunity:
   - **High**: 4+ nodes built in a static tree structure with lots of property setup. Clear win to move to `.tscn`.
   - **Medium**: 2-3 nodes or a mix of static structure + some dynamic content. Would benefit from partial extraction.
   - **Low**: Borderline cases — small node trees or semi-dynamic construction.
5. **Suggested approach** — brief note on how to extract (e.g., "Create `ban_confirm_panel.tscn` with the static layout, expose the label text via `@export` or `setup()` method")

## Output format

Group findings by severity (High first), then by file path. Use this format:

```
## High Priority

### scenes/admin/some_dialog.gd:45-78
**What:** Builds a form layout with 3 labels, 2 inputs, and a button bar
**Nodes:** 8
**Suggestion:** Extract to `some_form.tscn`. Expose input fields as exported node paths. Connect button signals in the parent script.

---

## Medium Priority
...

## Low Priority
...

## Summary
- X high-priority candidates (Y total nodes)
- X medium-priority candidates (Y total nodes)
- X low-priority candidates (Y total nodes)
```

## Execution

1. Use Grep to find all `.new()` instantiation of Godot node types across `scripts/` and `scenes/`
2. For each match, read the surrounding context (20-30 lines) to determine if it's a tree-building pattern
3. Filter out false positives (dynamic/loop-based, single nodes, already scene-backed)
4. Compile the report grouped by severity
5. Present findings to the user — do NOT make any code changes unless explicitly asked
