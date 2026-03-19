---
description: Migrate a user flow into a technical maintenance document in agentsdb
argument-hint: <flow-name or file>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(wc:*), Task, mcp__agentsdb__agents_search, mcp__agentsdb__agents_context_write
---

You are converting a product-oriented user flow document into a technical maintenance document written by engineers for engineers, and storing it in agentsdb.

## Arguments

`$ARGUMENTS` contains the flow name (e.g., "theming", "messaging") or an existing filename (e.g., "messaging.md", "content_embedding"). The flow must already exist in `user_flows/`.

## Context

User flows are written as product/PM handover documents — they describe what a feature does from the user's perspective, with signal flows and implementation status. Technical maintenance documents are the engineering counterpart: they explain how the code actually works so that an engineer picking up the feature for the first time can orient quickly, make changes safely, and debug issues.

## Task

### 1. Read the user flow

Read the user flow document from `user_flows/<name>.md`. If the file doesn't exist, list available flows and ask which one to migrate.

### 2. Search agentsdb for existing entries

Search agentsdb for any existing `maintenance` kind entries related to this flow to avoid duplicating work:

```
agents_search(query: "<flow name> maintenance", filters: { kind: ["maintenance"] })
```

If a maintenance doc already exists, inform the user and ask whether to overwrite or skip.

### 3. Detect stubbed user flows

A user flow is considered **stubbed** if it is ≤30 lines long. Stubbed flows are intentionally minimal — they document the feature's existence and key files without full detail. Check the line count:

```
wc -l user_flows/<name>.md
```

If the flow is stubbed, **skip step 4** and go directly to **step 5 (Write stubbed maintenance document)**.

### 4. Deep-read the referenced source files (full flows only)

From the user flow's Key Files table and any other file references in the document:

1. Read every referenced source file (`.gd`, `.tscn`, `.tres`, `.gdshader`, etc.)
2. For each file, note:
   - Public API surface (exported vars, public methods, signals)
   - Internal architecture (private methods, state machines, caches)
   - Dependencies (what it imports/preloads, what autoloads it uses)
   - Gotchas (type inference issues, Godot quirks, ordering constraints)
   - Error handling patterns
   - Performance considerations (caching, lazy loading, pooling)

### 5. Write stubbed maintenance document (stubbed flows only)

If the user flow is stubbed, produce a minimal maintenance stub instead of a full document. Use this template:

```markdown
# <Feature Name> — Maintenance Guide (Stub)

## Quick Orientation

1-2 sentences summarizing what this subsystem does and where to find it.

## File Map

| File | Purpose | Lines |
|------|---------|-------|
| `path/to/file.gd` | One-line role | ~N |

Copy the Key Files table from the user flow, adding approximate line counts.

## Dependencies

### Upstream (this feature depends on)
- List autoloads/modules this feature uses

### Downstream (depends on this feature)
- List what would break if this feature changes

## Notes

This is a stub. The source user flow is intentionally minimal. Expand this document when the feature gets significant development work.
```

After writing, skip to **step 7 (Store in agentsdb)**.

### 6. Write the full maintenance document (full flows only)

Compose a single markdown document following the template below. This is a **technical reference**, not a product spec. Focus on:

- How to find and navigate the code
- How the pieces connect (call chains, signal wiring, data flow)
- What to watch out for when making changes
- How to test changes
- Known tech debt and fragile areas

### 7. Store in agentsdb

Write the document to agentsdb using `agents_context_write`:

```
agents_context_write(
  content: "<the full markdown document>",
  kind: "maintenance",
  confidence: 0.95,
  scope: "delta",
  sources: ["user_flows/<name>.md"]
)
```

### 8. Stub the user flow (full flows only)

After successfully writing to agentsdb, **replace the full user flow with a stub**. The detailed content now lives in agentsdb as the maintenance document — the user flow should be reduced to a compact reference.

Use this format (modeled on `user_flows/ui_animations.md`):

```markdown
# <Feature Name>

Priority: <N>
Depends on: <deps>
Status: Complete

<1-2 sentence summary of what the feature covers, mentioning key subsystems and entry points.>

## Key Files

| File | Role |
|------|------|
| `path/to/file.gd` | Concise one-line role description |
```

Rules for stubbing:
- Keep the header (title, priority, depends on, status)
- Write a single paragraph summary — compress the Overview section into 1-2 sentences
- Keep the Key Files table but **shorten each Role column** to a concise phrase (no line numbers, no method lists)
- **Remove** all other sections: User Steps, Signal Flow, Implementation Details, Implementation Status, Gaps/TODO
- The resulting file should be ~30 lines or fewer

Do NOT stub if the flow was already stubbed (≤30 lines) in step 3.

## Maintenance Document Template

The output document MUST follow this structure. Sections marked (optional) can be omitted if not applicable.

```markdown
# <Feature Name> — Maintenance Guide

## Quick Orientation

2-3 sentences: what this subsystem does, where to find it, and the one thing an engineer should know before touching it.

## File Map

| File | Purpose | Lines |
|------|---------|-------|
| `path/to/file.gd` | One-line role | ~N |

Sort by importance (entry point first, then helpers, then models/resources).

## Architecture

### Data Flow
Describe how data moves through the system: entry points, transformations, caching, and output. Use a compact ASCII diagram if helpful.

### Signal Wiring
List the key signals, who emits them, and who connects to them. Format:
- `SignalName` — emitted by `file.gd:method()` → connected in `other.gd:_ready()`

### State Management
What state does this subsystem own? Where is it stored (autoload, node, config, cache)? What invalidates it?

## Code Walkthrough

### Entry Points
Where does execution start? What triggers this feature? (User action, gateway event, timer, etc.)

### Core Logic
Walk through the main code path(s) with file:line references. Focus on the "why" behind non-obvious decisions.

### Edge Cases
Document known edge cases, boundary conditions, and how they're handled (or not).

## Dependencies

### Upstream (this feature depends on)
- `Autoload/Module` — what it provides to this feature

### Downstream (depends on this feature)
- `Component/System` — what breaks if this feature changes

## Testing

### Existing Tests
List test files and what they cover.

### How to Test Manually
Steps an engineer would follow to verify changes work.

### Untested Areas
What has no test coverage and would need manual verification.

## Gotchas

Numbered list of things that will bite you:
1. Specific pitfall with file:line reference and explanation
2. ...

## Tech Debt

| Item | Severity | Notes |
|------|----------|-------|
| Description | High/Medium/Low | What needs to happen and why |
```

## Quality Rules

Before writing to agentsdb, verify:
1. Every file path in the document exists (use Glob)
2. Every signal name is declared in the referenced file (use Grep)
3. Line references are within +/- 10 lines of actual
4. Gotchas are based on actual code patterns, not speculation
5. The document would let a new engineer start working on this feature within 15 minutes of reading it

## What NOT to Include

- User-facing steps (that's what the user flow is for)
- Product requirements or feature wishlists
- Implementation status checklists (the code either exists or it doesn't)
- Marketing language or feature descriptions aimed at non-engineers
