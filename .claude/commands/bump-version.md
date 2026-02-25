---
description: Bump the app version (major, minor, or patch)
argument-hint: <major|minor|patch>
allowed-tools: Read, Edit, Bash(git tag:*), Bash(git log:*)
---

You are bumping the version of the daccord application.

## Arguments

`$ARGUMENTS` should be one of: `major`, `minor`, or `patch`. If not provided or not recognized, ask the user which bump type they want.

## Version Location

The single source of truth for the version is `project.godot` line:
```
config/version="X.Y.Z"
```

All other code reads from this via `ProjectSettings` at runtime -- no other files need updating.

## Steps

### 1. Read the current version

Read `project.godot` and extract the current `config/version` value.

### 2. Calculate the new version

Apply semantic versioning rules:
- **major**: `X.Y.Z` → `(X+1).0.0`
- **minor**: `X.Y.Z` → `X.(Y+1).0`
- **patch**: `X.Y.Z` → `X.Y.(Z+1)`

If the current version has a pre-release suffix (e.g., `1.0.0-beta.1`), strip it and bump the base version.

### 3. Update project.godot

Edit the `config/version="..."` line in `project.godot` to the new version.

### 4. Update CHANGELOG.md

Read `CHANGELOG.md`. Insert a new version heading between `## [Unreleased]` and the previous release entry:

```markdown
## [Unreleased]

## [X.Y.Z] - YYYY-MM-DD
```

Where `YYYY-MM-DD` is today's date. If there is content under `[Unreleased]`, move it under the new version heading so that `[Unreleased]` is left empty.

### 5. Prompt for changelog entries

If the `[Unreleased]` section was empty (no content to move), check `git log` for commits since the last tag to suggest changelog entries. Present them to the user and ask what should go in the changelog. Use Keep a Changelog categories: Added, Changed, Deprecated, Removed, Fixed, Security.

### 6. Report

Print a summary:
```
Version bumped: OLD → NEW
Updated: project.godot, CHANGELOG.md
```

Remind the user to commit and tag:
```
git add project.godot CHANGELOG.md
git commit -m "chore: bump version to X.Y.Z"
git tag vX.Y.Z
```
