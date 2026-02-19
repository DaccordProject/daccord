---
description: Add or update a user flow document in user_flows/
argument-hint: <flow-name or file> [description]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(wc:*), Task
---

You are updating the daccord user flows documentation. The user_flows/ directory contains markdown documents that describe user-facing flows, verified against the actual codebase.

## Arguments

`$ARGUMENTS` contains the flow name (e.g., "settings", "notifications") or an existing filename (e.g., "messaging.md", "messaging"). An optional description may follow.

## Existing documents

Read `user_flows/README.md` to see the current index of documents.

## Task

### If updating an existing flow:

1. Read the existing document in `user_flows/`
2. Explore the relevant source files referenced in the document's "Key Files" table
3. Check for any new code, signals, or features that have been added since the document was written
4. Update the document with corrected line numbers, new features, changed behavior, and updated gaps
5. Verify every file path still exists, every signal is still declared, and every gap still reflects actual missing code

### If creating a new flow:

1. Explore the codebase to find all relevant files for the flow
2. Read each file to understand signals, methods, and implementation details
3. Write the new document following the template below
4. Add an entry to `user_flows/README.md` in the index table (assign the next number)

## Document Template

Every user flow document MUST follow this structure:

```markdown
# [Flow Name]

## Overview
2-3 sentence description of the flow.

## User Steps
Numbered steps from the user's perspective.

## Signal Flow
ASCII diagram showing the signal chain from user action to UI update.

## Key Files
| File | Role |
|------|------|
| `path/to/file.gd` | What this file does in this flow |

## Implementation Details
### Subsection per component
- Code walkthrough with line references (e.g., "line 42")
- Signal declarations and connections
- Data flow and caching behavior

## Implementation Status
- [x] Feature that works
- [ ] Feature that doesn't work yet

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| Description of gap | High/Medium/Low | Details with line references |
```

## Verification Rules

Before finishing, verify:
1. Every file path referenced in the document exists in the codebase (use Glob)
2. Every signal name mentioned is declared in the referenced file (use Grep)
3. Line number references are approximately correct (within +/- 5 lines)
4. Every gap listed reflects actual missing code, not just missing documentation

## Conventions

- Reference line numbers as `(line 42)` or `(lines 42-50)` inline
- Use `client.gd:42` format in tables and Key Files
- Severity levels: High (core functionality missing), Medium (usability gap), Low (nice-to-have)
- Signal names should match GDScript exactly (e.g., `guild_selected` not `guildSelected`)
- Dictionary shapes should show actual key names from the code
- Always note hardcoded values that should come from the server
