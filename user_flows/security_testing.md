# Security Testing

## Overview

This document maps daccord's client-side security surface: authentication and token handling, input sanitization, encrypted storage, network transport, credential exposure, and permission gating. It identifies what is implemented, what has known weaknesses, and what testing should cover. Server-side security (accordserver) is out of scope -- this covers only the Godot client.

## Security Areas

### 1. Token Storage & Encrypted Config

Tokens and server credentials are persisted in per-profile config files (`user://profiles/<slug>/config.cfg`) using Godot's `ConfigFile.save_encrypted_pass()`. The encryption key is derived deterministically from a hardcoded salt and the OS user data directory, so anyone with filesystem access and the app binary can reproduce the key.

**Key files:**

| File | Role |
|------|------|
| `scripts/autoload/config.gd:205-206` | `_derive_key()` -- returns `_SALT + OS.get_user_data_dir()` where `_SALT = "daccord-config-v1"` |
| `scripts/autoload/config.gd:282` | `save()` calls `_config.save_encrypted_pass(path, key)` |
| `scripts/autoload/config.gd:283-292` | **Silent plaintext fallback** -- if encrypted save fails, falls back to unencrypted `_config.save(path)` with only a `push_warning` |
| `scripts/autoload/config.gd:215-220` | `get_servers()` reads `token` from config sections |
| `scripts/autoload/config_profiles.gd:72,96,104` | Profile registry (`user://profile_registry.cfg`) saved **unencrypted** -- contains profile names and password hashes |

**Test vectors:**

- Verify config files on disk are encrypted (not readable as plaintext).
- Simulate an encrypted save failure (e.g., read-only filesystem) and confirm the client does not silently downgrade to plaintext.
- Confirm the profile registry does not contain tokens or passwords (only hashes).
- Confirm exported `.daccord-profile` files strip `token` and `password` keys (`config.gd:583-593`).

### 2. Profile Password Hashing

Profile unlock passwords use single-round SHA-256 with a deterministic salt (`"daccord-profile-v1" + slug`). There is no key-stretching (no PBKDF2, bcrypt, or Argon2), making offline dictionary attacks against the registry hash file feasible.

**Key files:**

| File | Role |
|------|------|
| `scripts/autoload/config_profiles.gd:205-213` | `_hash_password()` -- `SHA256(salt + slug + password)` |
| `scripts/autoload/config_profiles.gd:176-183` | `verify_profile_password()` -- compares hash |

**Test vectors:**

- Confirm password hashes are stored in the registry, not plaintext passwords.
- Attempt a brute-force timing attack against `verify_profile_password()` to check for timing-safe comparison (GDScript string `==` is not constant-time).

### 3. HTTPS Downgrade to HTTP

When an HTTPS connection fails (any error), the client automatically retries with HTTP and sends the Bearer token in plaintext. If the HTTP attempt succeeds, the downgraded URL is persisted to config, making all future connections unencrypted.

**Key files:**

| File | Role |
|------|------|
| `scripts/autoload/client_connection.gd` | HTTPS-only connections (no HTTP fallback) |
| `scripts/autoload/client.gd` | WebSocket URL derived from base URL (always `wss://` for HTTPS) |

**Test vectors:**

- Connect to a server with a self-signed cert (HTTPS fails) and observe whether the client silently downgrades to HTTP.
- Confirm the token is retransmitted over the HTTP connection.
- Check that the downgraded HTTP URL is written back to config.
- Verify the gateway WebSocket URL also downgrades to `ws://`.

### 4. BBCode Injection

daccord renders messages through `RichTextLabel` with `bbcode_enabled = true`. The `markdown_to_bbcode()` pipeline sanitizes user-authored messages, but several paths bypass or weaken the sanitizer.

**Key files:**

| File | Role |
|------|------|
| `scripts/autoload/client_markdown.gd:106-160` | `_sanitize_bbcode_tags()` -- allowlist-based tag filter |
| `scripts/autoload/client_markdown.gd:109-122` | Allowed tag prefixes: `b`, `i`, `s`, `u`, `code`, `url=`, `url]`, `/url]`, `bgcolor=`, `color=`, `indent`, `img=`, `font_size=`, `lb` |
| `scenes/messages/message_content.gd:35-36` | **System message injection** -- raw server content concatenated into BBCode with no sanitization |
| `scenes/messages/message_content.gd:84-89` | **Attachment filename injection** -- `fname` from server data inserted into `[url=...]` BBCode unsanitized |
| `scripts/autoload/client_markdown.gd:97-100` | Custom emoji path inserted into `[img=...]` without escaping |

**System message injection (highest risk):**

```gdscript
# message_content.gd:35-36
text_content.text = "[i][color=#8a8e94]" + raw_text + "[/color][/i]"
```

`raw_text` is server-supplied content with zero sanitization. A compromised server (or MITM on HTTP) can inject arbitrary BBCode tags.

**Attachment filename injection:**

```gdscript
# message_content.gd:84-89
att_label.text = "[color=#00aaff][url=%s]%s[/url][/color]" % [url, fname]
```

`fname` comes from `att.get("filename", "file")` -- if it contains `[` characters, they are interpreted as BBCode.

**Test vectors:**

- Send a message containing raw BBCode tags (e.g., `[url=https://evil.com]click me[/url]`) and confirm the sanitizer escapes them.
- Craft a message with an `[img=` prefix to test whether arbitrary image paths load.
- Simulate a system message with injected BBCode (e.g., `[url=https://evil.com]admin notice[/url]`) and confirm it renders unsanitized (known gap).
- Create an attachment with a filename like `test[url=https://evil.com]click[/url].txt` and observe rendering.
- Send a message with `[code][url=https://evil.com]inside code[/url][/code]` to test code block bypass.

### 5. URL Scheme Blocking

Markdown links (`[text](url)`) are checked against a blocklist of dangerous schemes before conversion. However, the blocklist is incomplete, and raw BBCode `[url=...]` tags that pass the sanitizer's prefix check are not scheme-checked.

**Key files:**

| File | Role |
|------|------|
| `scripts/autoload/client_markdown.gd:73-78` | Blocks `javascript:`, `data:`, `file:`, `vbscript:` -- replaces with `#blocked` |
| `scenes/messages/message_content.gd:131-141` | `_on_meta_clicked()` only calls `OS.shell_open()` for `http://` and `https://` URLs |
| `scenes/messages/embed.gd:227-230` | Embed `_on_meta_clicked()` has the same `http(s)://` guard |

**Test vectors:**

- Send a Markdown link with `javascript:alert(1)` and confirm it is blocked.
- Send a Markdown link with `file:///etc/passwd` and confirm it is blocked.
- Test unblocked schemes: `mailto:`, `smb://`, `ftp://`, custom protocol handlers.
- Confirm that even if a dangerous URL passes through BBCode, `_on_meta_clicked` refuses to open it via `OS.shell_open()`.

### 6. Token Exposure in URLs

The Add Server dialog accepts tokens in the URL format `host?token=value`. This means tokens appear in the UI text input and could be logged or shared.

**Key files:**

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/add_server_dialog.gd:39-82` | `parse_server_url()` extracts `token` from query string |
| `scenes/sidebar/guild_bar/auth_dialog.gd:3-7` | `auth_completed` signal carries `password` as parameter |

**Test vectors:**

- Paste a URL with `?token=secret` and confirm the token is not visible in logs, error reports, or breadcrumbs.
- Verify the token from URL parsing is stored only in the encrypted config, not persisted elsewhere.
- Confirm `error_reporting.gd:53-55` redacts `token=` query parameters in error messages.

### 7. Error Reporting PII Scrubbing

Error reporting is opt-in and disabled by default. PII scrubbing covers the event message but not stack traces, breadcrumb data, or Sentry tags.

**Key files:**

| File | Role |
|------|------|
| `scripts/autoload/error_reporting.gd:35-41` | `_before_send()` gates on consent and scrubs event message |
| `scripts/autoload/error_reporting.gd:49-59` | `scrub_pii_text()` redacts Bearer tokens, `token=` params, and URLs with ports |
| `scripts/autoload/error_reporting.gd:75-82` | Breadcrumbs include `space_id` and `channel_id` |
| `scripts/autoload/error_reporting.gd:121-136` | `update_context()` sets space/channel IDs as Sentry tags |
| `project.godot:74` | `send_default_pii=false` |

**Test vectors:**

- Trigger an error containing a Bearer token in the message and confirm it is redacted.
- Trigger an error containing a Bearer token in a stack trace and confirm whether it is redacted (known gap: only `event.message` is scrubbed).
- Confirm the consent dialog appears on first launch and defaults to disabled.
- Confirm the Sentry DSN is empty in development builds (injected at CI time only).

### 8. Password Generation (PRNG)

The auth dialog generates random passwords using `randi()`, which is Godot's non-cryptographic PRNG. Generated passwords are 12 characters from a 70-character alphabet.

**Key files:**

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/auth_dialog.gd:128-134` | `_generate_password()` uses `randi() % CHARS.length()` |

**Test vectors:**

- Confirm generated passwords have sufficient entropy for their purpose (registration convenience, not high-security).
- Note that `randi()` is not a CSPRNG -- if the RNG state is predictable, passwords are predictable.

### 9. Client-Side Permission Gating

Permissions are enforced on the server; the client checks are UI-only gating (hiding buttons, disabling the composer). This is by design. Imposter mode substitutes permissions for UI simulation but does not affect API calls.

**Key files:**

| File | Role |
|------|------|
| `scripts/autoload/client_permissions.gd:10-31` | `has_permission()` -- short-circuits for admin/owner |
| `scripts/autoload/client_permissions.gd:37-41` | Imposter mode substitution |
| `scenes/messages/composer/composer.gd:302` | Composer disabled in imposter mode |

**Test vectors:**

- Enable imposter mode and confirm no API mutations are possible (composer is disabled, no messages sent).
- Attempt to bypass client permission checks by calling `Client` methods directly -- confirm the server rejects unauthorized requests.

### 10. Voice Debug Logging

A hardcoded `DEBUG_VOICE_LOGS = true` flag writes all voice events (including user IDs) to `user://voice_debug.log`. This file persists indefinitely with no rotation.

**Key files:**

| File | Role |
|------|------|
| `scripts/autoload/client.gd:6-7` | `DEBUG_VOICE_LOGS = true`, `VOICE_LOG_PATH = "user://voice_debug.log"` |

**Test vectors:**

- Join a voice channel and confirm `voice_debug.log` is written.
- Inspect the log for PII (user IDs, display names, IP addresses).
- Confirm no tokens or credentials are written to the voice log.

### 11. Rate Limiting

The client has no proactive rate limiting on message sends, reactions, or most mutations. Server-side `429` responses are handled with up to 3 retries respecting `Retry-After`.

**Key files:**

| File | Role |
|------|------|
| `addons/accordkit/rest/accord_rest.gd:88-97` | 429 retry handler |
| `scenes/messages/composer/composer.gd:100` | Typing indicator 8-second throttle |
| `scripts/autoload/updater.gd:55-61` | Update check 1-hour throttle |

**Test vectors:**

- Rapidly send messages and confirm the server rate-limits appropriately (client sends all requests).
- Confirm 429 responses are handled gracefully with retry.

### 12. Config Import Safety

Importing a `.daccord-profile` file replaces the entire in-memory config. While export strips tokens, import does not strip anything -- a crafted import file could inject arbitrary config values including tokens.

**Key files:**

| File | Role |
|------|------|
| `scripts/autoload/config.gd:583-593` | `export_config()` strips `token` and `password` |
| `scripts/autoload/config.gd:598-614` | `import_config()` loads file verbatim, creates `.pre-import.bak` backup |

**Test vectors:**

- Export a profile and confirm it contains no tokens or passwords.
- Craft a malicious import file with extra config keys and confirm whether they are accepted.
- Confirm the pre-import backup is created.

## Implementation Status

- [x] Encrypted config storage (`save_encrypted_pass()`)
- [x] Token/password stripping in config export
- [x] Pre-import backup on config import
- [x] BBCode sanitizer with tag allowlist (`_sanitize_bbcode_tags`)
- [x] Dangerous URL scheme blocking for Markdown links (`javascript:`, `data:`, `file:`, `vbscript:`)
- [x] `_on_meta_clicked` restricts `OS.shell_open()` to `http(s)://`
- [x] PII scrubbing in error reports (Bearer tokens, `token=` params, URLs)
- [x] Error reporting opt-in, disabled by default
- [x] `send_default_pii=false` in project settings
- [x] Profile password hashing (SHA-256)
- [x] 429 rate-limit handling with retry
- [x] Typing indicator throttle
- [x] Sentry DSN not committed to source (CI-injected)
- [x] Constant-time password hash comparison
- [x] Key-stretched password hashing (PBKDF2-HMAC-SHA256, 10k iterations)
- [x] HTTPS enforcement (no silent HTTP downgrade -- user confirmation required)
- [x] System message BBCode sanitization
- [x] Attachment filename BBCode escaping
- [x] Custom emoji path BBCode escaping (scheme allowlist + `[` escaping)
- [x] PII scrubbing in breadcrumbs (scrub_pii_text applied at input boundary)
- [x] Dangerous scheme blocking for raw BBCode `[url=]` tags
- [x] CSPRNG for password generation (`Crypto.generate_random_bytes`)
- [x] Voice debug log rotation / conditional flag (off by default, 1MB rotation)
- [x] Client-side rate limiting on message sends (500ms cooldown)
- [x] Config import validation / key allowlisting (token/password stripped)
- [x] Random per-profile salt for password hashing

## Gaps / TODO

| Gap | Severity | Status | Notes |
|-----|----------|--------|-------|
| HTTPS silently downgrades to HTTP | High | **FIXED** | User confirmation dialog required before downgrading. Downgraded URL no longer auto-persisted. |
| System messages have no BBCode sanitization | High | **FIXED** | `[` characters escaped with `[lb]` in system messages. |
| Silent fallback to plaintext config storage | High | **FIXED** | Plaintext fallback removed. On encrypted save failure, emits `config_save_failed` signal and keeps data in memory. |
| Attachment filename BBCode injection | Medium | **FIXED** | `fname` escaped with `[lb]` before BBCode insertion. |
| Custom emoji path unsanitized in BBCode | Medium | **FIXED** | Paths validated against scheme allowlist (`http://`, `https://`, `user://profiles/`, `res://`) and `[` characters escaped. |
| `[img=` on sanitizer allowlist | Medium | Mitigated | Custom emoji paths now scheme-checked. `[img=` still on the allowlist for converter-produced tags; arbitrary `[img=res://` in user messages still possible but limited to valid Godot resource paths. |
| Profile password hash uses SHA-256, no key-stretching | Medium | **FIXED** | PBKDF2-HMAC-SHA256 with 10,000 iterations and random per-profile salt. Legacy hashes auto-upgrade on successful verify. |
| Config encryption key is deterministic | Medium | Open | `config.gd:_derive_key()` still uses `_SALT + OS.get_user_data_dir()`. Improving this requires platform-specific keychain integration. |
| PII scrubbing only covers event.message | Medium | **FIXED** | Breadcrumb messages now scrubbed through `scrub_pii_text()` at input boundary. Stack trace scrubbing limited by SentryEvent API. |
| Config import accepts arbitrary keys | Medium | **FIXED** | Import now strips `token` and `password` keys. |
| `DEBUG_VOICE_LOGS` hardcoded true | Low | **FIXED** | Now configurable via settings (default off). Log rotation at 1MB. |
| Password generation uses `randi()` (not CSPRNG) | Low | **FIXED** | Uses `Crypto.generate_random_bytes()`. |
| URL scheme blocklist is incomplete | Low | Mitigated | `_is_dangerous_scheme()` checks applied to both markdown links and raw BBCode `[url=]` tags. `_on_meta_clicked` still restricts `OS.shell_open()` to `http(s)://`. |
| Nonce generator exists but is unused | Low | Open | `snowflake.gd:generate_nonce()` uses `randi()` -- not used in production. |
| No client-side message send rate limiting | Low | **FIXED** | 500ms cooldown between sends in composer. |
| Profile registry saved unencrypted | Low | Mitigated | Registry contains password hashes (now PBKDF2 with random salt, not trivially reversible). No tokens stored. |
