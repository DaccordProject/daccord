---
description: Query issues from the GlitchTip error tracking instance (Sentry-compatible API)
argument-hint: [list|show <id>|events <id>|resolve <id>|search <query>]
allowed-tools: Bash(curl:*), Read, Grep, Glob, Task
---

You are querying the daccord GlitchTip instance for error tracking data. GlitchTip exposes a Sentry-compatible API.

## Configuration

- **Instance:** `https://crash.daccord.gg`
- **Organization:** `daccord`
- **API base:** `https://crash.daccord.gg/api/0`
- **Auth:** Bearer token from `$GLITCHTIP_TOKEN` environment variable

All `curl` commands must include:
```
-H "Authorization: Bearer $(printenv GLITCHTIP_TOKEN)"
```

**Important:** Always use `$(printenv GLITCHTIP_TOKEN)` instead of `$GLITCHTIP_TOKEN` in curl commands. Direct variable expansion may fail silently in some environments, sending an empty Authorization header.

## Arguments

`$ARGUMENTS` determines the action. If empty, default to `list`.

### `list` (default)

List unresolved issues across all projects.

```bash
curl -s -H "Authorization: Bearer $(printenv GLITCHTIP_TOKEN)" \
  "https://crash.daccord.gg/api/0/organizations/daccord/issues/?query=is:unresolved" | python3 -m json.tool
```

### `list all`

List all issues (including resolved).

```bash
curl -s -H "Authorization: Bearer $(printenv GLITCHTIP_TOKEN)" \
  "https://crash.daccord.gg/api/0/organizations/daccord/issues/?query=" | python3 -m json.tool
```

### `show <issue_id>`

Retrieve detailed info for a specific issue, including activity and tags.

```bash
curl -s -H "Authorization: Bearer $(printenv GLITCHTIP_TOKEN)" \
  "https://crash.daccord.gg/api/0/organizations/daccord/issues/<issue_id>/" | python3 -m json.tool
```

### `events <issue_id>`

List events (occurrences) for a specific issue, with full stacktraces.

```bash
curl -s -H "Authorization: Bearer $(printenv GLITCHTIP_TOKEN)" \
  "https://crash.daccord.gg/api/0/organizations/daccord/issues/<issue_id>/events/?full=true" | python3 -m json.tool
```

### `resolve <issue_id>`

Mark an issue as resolved.

```bash
curl -s -X PUT -H "Authorization: Bearer $(printenv GLITCHTIP_TOKEN)" \
  -H "Content-Type: application/json" \
  -d '{"status": "resolved"}' \
  "https://crash.daccord.gg/api/0/organizations/daccord/issues/<issue_id>/" | python3 -m json.tool
```

### `search <query>`

Search issues with a custom Sentry query string.

```bash
curl -s -H "Authorization: Bearer $(printenv GLITCHTIP_TOKEN)" \
  "https://crash.daccord.gg/api/0/organizations/daccord/issues/?query=<url_encoded_query>" | python3 -m json.tool
```

Common query filters:
- `is:unresolved` -- only open issues (default)
- `is:resolved` -- only resolved issues
- `level:error` -- only errors (not warnings/info)
- `first-release:1.0` -- issues from a specific release
- `assigned:me` -- issues assigned to you

### `projects`

List available projects in the organization.

```bash
curl -s -H "Authorization: Bearer $(printenv GLITCHTIP_TOKEN)" \
  "https://crash.daccord.gg/api/0/organizations/daccord/projects/" | python3 -m json.tool
```

## Presentation

When displaying results, format them as a readable summary:

### For issue lists:
```
| # | ID | Title | Level | Events | Users | First Seen | Last Seen |
|---|-----|-------|-------|--------|-------|------------|-----------|
```

### For a single issue:
- **Title** and **culprit** (file/function where the error occurred)
- **Level** (error/warning/info)
- **Status** (resolved/unresolved)
- **Event count** and **user count**
- **First/last seen** timestamps
- **Tags** if present
- **Latest stacktrace** if showing events

### For events:
Show the most recent events with:
- Timestamp
- Error message
- Stacktrace (formatted as code block)
- Tags and user info if present

## Error Handling

- If `$GLITCHTIP_TOKEN` is empty or unset, tell the user to set it: `export GLITCHTIP_TOKEN=<token>`
- If a 401/403 is returned, the token may be expired -- tell the user to check their API key
- If a 404 is returned, the organization, project, or issue ID may be wrong
