---
description: Access and control Firefox via remote debugging (WebDriver BiDi)
argument-hint: [status|tabs|screenshot|eval <js>|navigate <url>|html|text|click <sel>|type <sel> <text>|title|url|reload|back|forward|new_tab|close_tab|cookies|console_log|network]
allowed-tools: Bash(python3 .claude/scripts/firefox_bidi.py:*), Read(/tmp/firefox_screenshot.png)
---

You are controlling a Firefox browser instance via WebDriver BiDi remote debugging.

## Prerequisites

Firefox must be running with remote debugging enabled:
```bash
MOZ_REMOTE_DEBUGGING=1 firefox --remote-debugging-port=9222
```
The browser will show "Browser is under remote control" when active.

## Helper Script

All commands go through `.claude/scripts/firefox_bidi.py`. Run commands as:
```bash
python3 .claude/scripts/firefox_bidi.py <command> [args...]
```

## Arguments

`$ARGUMENTS` determines the action. If empty, default to `status`.

### Core commands

| Command | Args | Description |
|---------|------|-------------|
| `status` | | Check connection and tab count |
| `tabs` | | List all open tabs with context IDs and URLs |
| `screenshot` | `[context_id]` | Capture tab screenshot to `/tmp/firefox_screenshot.png` |
| `title` | `[context_id]` | Get page title |
| `url` | `[context_id]` | Get current URL |

### Navigation

| Command | Args | Description |
|---------|------|-------------|
| `navigate` | `<url> [context_id]` | Navigate to a URL |
| `reload` | `[context_id]` | Reload the page |
| `back` | `[context_id]` | Go back in history |
| `forward` | `[context_id]` | Go forward in history |

### DOM inspection

| Command | Args | Description |
|---------|------|-------------|
| `html` | `[selector] [context_id]` | Get outerHTML of an element (default: `document.body`) |
| `text` | `[selector] [context_id]` | Get innerText of an element (default: `document.body`) |
| `eval` | `<expression> [context_id]` | Evaluate arbitrary JavaScript |

### Interaction

| Command | Args | Description |
|---------|------|-------------|
| `click` | `<selector> [context_id]` | Click an element by CSS selector |
| `type` | `<selector> <text> [context_id]` | Type text into an input element |

### Tab management

| Command | Args | Description |
|---------|------|-------------|
| `new_tab` | `[url]` | Open a new tab, optionally navigate to a URL |
| `close_tab` | `<context_id>` | Close a specific tab (use `tabs` to get context IDs) |

### Debugging

| Command | Args | Description |
|---------|------|-------------|
| `cookies` | `[context_id]` | Get document cookies |
| `console_log` | `[context_id]` | Capture `console.log` output (first call installs logger, subsequent calls retrieve logs) |
| `network` | `[context_id]` | Get recent network requests from Performance API |

## Context IDs

Most commands accept an optional `context_id` to target a specific tab. If omitted, the first tab is used. Run `tabs` to list available context IDs.

## Workflow Tips

1. **Start with `status`** to verify Firefox is reachable
2. **Use `tabs`** to see what's open and get context IDs for multi-tab work
3. **Use `screenshot`** + Read the image to visually inspect the page
4. **Use `text`** with a CSS selector to read specific page content without HTML noise
5. **Use `eval`** for anything the built-in commands don't cover — full JS access
6. **Use `console_log`** twice: first call installs the logger, second retrieves captured logs
7. **Chain commands** for multi-step interactions: navigate → wait → screenshot → verify

## Error Handling

- If Firefox is not running or remote debugging is not enabled, the script will print a connection error
- If a CSS selector matches no element, commands return "Element not found"
- If a BiDi method fails, the script prints the error type and message
- Stale sessions (from previous connections) require a Firefox restart to clear

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FIREFOX_BIDI_PORT` | `9222` | Remote debugging port |
| `FIREFOX_SCREENSHOT_PATH` | `/tmp/firefox_screenshot.png` | Screenshot output path |
