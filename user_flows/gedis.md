# Gedis

## Overview

Gedis is a proposed Godot addon that provides a local, in-memory key-value store with a Redis-like API. Values in the store can have watchers attached so UI components are notified when specific keys change, replacing the current pattern of manual signal wiring, cache lookups, and full re-renders. This would significantly reduce boilerplate for scalar and small-collection state (selected guild, current user, layout mode, unread flags), though it offers diminishing returns for scale-sensitive collections like message lists and member rosters where targeted differential updates already exist.

## Current Pain Points

### Pattern 1: Signal Boilerplate in AppState
`AppState` (app_state.gd) declares **60+ signals** (lines 3-142), each with a corresponding setter method that updates a `var` and emits the signal. Every UI component that cares about a piece of state must:
1. Connect to the signal in `_ready()`
2. Implement a callback that reads the new value
3. Trigger a refresh (often a full re-render)

Example — channel_list.gd connects to 3 AppState signals (lines 23-25), and each callback triggers `load_guild()` which clears and rebuilds the entire channel tree.

### Pattern 2: Duplicate State Tracking
Components maintain local variables that mirror AppState:
- `channel_list.gd` line 14: `active_channel_id` mirrors `AppState.current_channel_id`
- `guild_bar.gd` line 11: `active_guild_id` mirrors `AppState.current_guild_id`
- `message_view.gd` line 11: `current_channel_id` mirrors `AppState.current_channel_id`
- `dm_list.gd` line 9: `active_dm_id` (parallel tracking with no AppState equivalent)

These shadow copies drift if a signal is missed or if initialization order is wrong.

### Pattern 3: Full Re-renders on Any Change
Most `*_updated` signals cause entire subtrees to be torn down and rebuilt:
- `guilds_updated` → `guild_bar._populate_guilds()` clears all guild icons, recreates them
- `channels_updated` → `channel_list.load_guild()` clears all channel items, recreates them
- `dm_channels_updated` → `dm_list._populate_dms()` clears all DM items, recreates them

Only `message_view.gd` attempts differential updates via `_diff_messages()` (line 373), and even that falls back to full re-render frequently.

### Pattern 4: Scattered Cache Dictionaries in Client
`client.gd` manages 12+ cache dictionaries (lines 83-101): `_user_cache`, `_guild_cache`, `_channel_cache`, `_dm_channel_cache`, `_message_cache`, `_member_cache`, `_role_cache`, `_voice_state_cache`, `_thread_message_cache`, `_forum_post_cache`, `_unread_channels`, `_channel_mention_counts`. Each has bespoke get/set helpers and its own invalidation logic.

## Proposed Design

### API Surface

Gedis would be an autoload singleton with a Redis-inspired API:

```gdscript
# Basic key-value operations
Gedis.set("ui:current_guild_id", guild_id)
var gid: String = Gedis.get("ui:current_guild_id", "")

# Hash operations (nested dictionaries)
Gedis.hset("guild", guild_id, guild_dict)
Gedis.hget("guild", guild_id)        # -> Dictionary
Gedis.hgetall("guild")               # -> Dictionary of all guilds
Gedis.hdel("guild", guild_id)

# List operations (ordered collections)
Gedis.lset("messages:{channel_id}", messages_array)
Gedis.lget("messages:{channel_id}")  # -> Array

# Key existence and deletion
Gedis.has("ui:current_guild_id")     # -> bool
Gedis.del("ui:current_guild_id")
Gedis.keys("guild:*")               # -> Array of matching keys (glob pattern)
```

### Watch System

The core feature: attach callbacks to keys or key patterns that fire when values change.

```gdscript
# Watch a specific key
Gedis.watch("ui:current_guild_id", _on_guild_changed)

# Watch a key pattern (glob)
Gedis.watch("guild:*", _on_any_guild_changed)

# Watch a hash field
Gedis.hwatch("channel", channel_id, _on_channel_changed)

# Unwatch (for cleanup in _exit_tree)
Gedis.unwatch("ui:current_guild_id", _on_guild_changed)
```

Watch callbacks receive the key and new value:

```gdscript
func _on_guild_changed(key: String, value: Variant) -> void:
    # value is the new guild_id string
    _load_channels_for(value)
```

### Key Namespace Convention

```
ui:*                    # UI state (selected guild, channel, layout mode, toggles)
user:*                  # User cache (user:{user_id} -> Dictionary)
guild:*                 # Guild cache (guild:{guild_id} -> Dictionary)
channel:*               # Channel cache (channel:{channel_id} -> Dictionary)
dm:*                    # DM channel cache (dm:{channel_id} -> Dictionary)
messages:*              # Message lists (messages:{channel_id} -> Array)
members:*               # Member lists (members:{guild_id} -> Array)
roles:*                 # Role lists (roles:{guild_id} -> Array)
voice:*                 # Voice state (voice:{channel_id} -> Array)
unread:*                # Unread flags (unread:{channel_id} -> bool)
mentions:*              # Mention counts (mentions:{channel_id} -> int)
```

## User Steps

From a developer's perspective, using gedis:

1. **Register watchers** in `_ready()` instead of connecting to AppState signals
2. **Read state** via `Gedis.get()` / `Gedis.hget()` instead of `Client.get_*()` accessors
3. **Write state** via `Gedis.set()` / `Gedis.hset()` — watchers fire automatically
4. **Unwatch** in `_exit_tree()` to prevent dangling callbacks

## Signal Flow

### Current Architecture
```
User clicks guild
  → guild_bar emits guild_selected(id)
    → sidebar connects, calls AppState.select_guild(id)
      → AppState sets current_guild_id, emits guild_selected signal
        → channel_list._on_guild_selected → load_guild() (full re-render)
        → message_view._on_guild_selected → clear messages
        → guild_bar._on_guilds_updated → _populate_guilds() (full re-render)
        → (N other components with manual signal connections)

Gateway delivers message
  → ClientGateway parses event
    → Client updates _message_cache[channel_id]
      → Client emits AppState.messages_updated(channel_id)
        → message_view._on_messages_updated → _load_messages() (full re-render)
```

### With Gedis
```
User clicks guild
  → guild_bar calls Gedis.set("ui:current_guild_id", id)
    → Gedis fires watchers for "ui:current_guild_id"
      → channel_list._on_guild_changed(key, id) → load channels for id
      → guild_bar._on_guild_changed(key, id) → update active pill

Gateway delivers message
  → ClientGateway parses event
    → Client calls Gedis.lset("messages:{channel_id}", updated_array)
      → Gedis fires watchers for "messages:{channel_id}"
        → message_view._on_messages_changed(key, messages) → diff and patch
```

The key difference: no manual signal declarations, no signal connections, no intermediary AppState methods. Components declare what state they care about and gedis handles notification.

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | Current signal bus with 60+ signals and 20+ state vars — gedis replaces this |
| `scripts/autoload/client.gd` | Current data cache with 12+ dictionaries — gedis replaces the cache layer |
| `scripts/autoload/client_models.gd` | Dictionary shape converters — unchanged, still converts AccordKit models to dicts |
| `scenes/sidebar/guild_bar/guild_bar.gd` | Example: 3 signal connections + full re-render on `guilds_updated` |
| `scenes/sidebar/channels/channel_list.gd` | Example: 3 signal connections + full re-render on `channels_updated` |
| `scenes/messages/message_view.gd` | Example: 12+ signal connections, mix of full re-render and diff |
| `scenes/sidebar/direct/dm_list.gd` | Example: 3 signal connections + full re-render on `dm_channels_updated` |

## Implementation Details

### Gedis Core (addon)

The addon would live in `addons/gedis/` and provide a single autoload:

**Storage:** A flat `Dictionary` for scalar keys and a nested `Dictionary` for hash/list keys. No persistence (purely in-memory for the app lifecycle). Optionally, a `dump()` / `restore()` API for session save/restore if needed later.

**Watch dispatch:** Internally, a `Dictionary` mapping key patterns to arrays of `Callable`. On every `set()` / `hset()` / `del()`, iterate registered watchers and invoke matching callbacks. Pattern matching uses `String.match()` (Godot's glob-style matching).

**Thread safety:** Godot's main thread model means no mutex is needed — all set/get/watch operations are synchronous on the main thread. Gateway events arrive via signals which are also main-thread.

**Change detection:** Only fire watchers when the new value differs from the old value (using `!=` comparison). This prevents cascading re-renders when a cache refresh writes the same data.

### Migration Path from AppState

AppState's current state variables and their gedis equivalents:

| AppState Variable | Gedis Key | Type |
|---|---|---|
| `current_guild_id` | `ui:current_guild_id` | `String` |
| `current_channel_id` | `ui:current_channel_id` | `String` |
| `is_dm_mode` | `ui:is_dm_mode` | `bool` |
| `replying_to_message_id` | `ui:replying_to_message_id` | `String` |
| `editing_message_id` | `ui:editing_message_id` | `String` |
| `current_layout_mode` | `ui:layout_mode` | `int` |
| `sidebar_drawer_open` | `ui:sidebar_drawer_open` | `bool` |
| `member_list_visible` | `ui:member_list_visible` | `bool` |
| `voice_channel_id` | `ui:voice_channel_id` | `String` |
| `is_voice_muted` | `ui:voice_muted` | `bool` |
| `is_video_enabled` | `ui:video_enabled` | `bool` |
| `is_screen_sharing` | `ui:screen_sharing` | `bool` |
| `is_imposter_mode` | `ui:imposter_mode` | `bool` |

### Migration Path from Client Caches

| Client Cache | Gedis Key Pattern | Type |
|---|---|---|
| `_guild_cache` | `guild:{guild_id}` (hash) | `Dictionary` per guild |
| `_channel_cache` | `channel:{channel_id}` (hash) | `Dictionary` per channel |
| `_dm_channel_cache` | `dm:{channel_id}` (hash) | `Dictionary` per DM |
| `_user_cache` | `user:{user_id}` (hash) | `Dictionary` per user |
| `_role_cache` | `roles:{guild_id}` | `Array` |
| `_voice_state_cache` | `voice:{channel_id}` | `Array` |
| `_unread_channels` | `unread:{channel_id}` | `bool` |
| `_channel_mention_counts` | `mentions:{channel_id}` | `int` |

### Where Gedis Helps Most

**Scalar UI state** (selected guild, layout mode, toggle flags): Biggest win. Currently each requires a var + signal declaration + setter method in AppState, plus manual connections in every interested component. With gedis: one `set()` call, watchers fire automatically.

**Small lookup caches** (guilds, channels, roles, DM channels): Good fit. Typically < 100 entries. Watchers replace the `*_updated` signals that trigger full re-renders. Components can watch specific IDs they display rather than rebuilding everything.

**Unread/mention tracking**: Good fit. Currently scattered across `_unread_channels`, `_channel_mention_counts`, and manual `_update_guild_unread()`. With gedis, setting `unread:{channel_id}` automatically notifies the guild bar, channel list, and DM list via pattern watches.

### Where Gedis Offers Diminishing Returns

**Message lists** (`_message_cache`): The message cache can hold up to 200 messages per channel (`MAX_CHANNEL_MESSAGES`, client.gd line 16). `message_view.gd` already implements differential updates (`_diff_messages()`, line 373) with a `_message_node_index` for O(1) message lookups (line 23). Replacing this with gedis watchers would lose the fine-grained diffing — a watcher on `messages:{channel_id}` would fire on every append, delivering the entire array. The current approach is better for this use case.

**Member lists** (`_member_cache`): Similar scale concern. Member lists use virtual scrolling with object pooling (see memberlist_performance.md). The member cache can be large for popular servers. Gateway events update individual members, and the current `_member_id_index` (client.gd line 104) enables O(1) targeted updates. Gedis would regress this to O(n) watch callbacks receiving the full array.

**High-frequency events** (typing indicators, speaking state): These fire rapidly and are transient. The overhead of gedis change detection and watcher dispatch could add latency. Current direct signal emission is more efficient for fire-and-forget events.

### Boilerplate Reduction Estimate

A typical UI component currently requires:

```gdscript
# Current: channel_list.gd (3 signal connections + callbacks)
func _ready():
    AppState.channels_updated.connect(_on_channels_updated)
    AppState.imposter_mode_changed.connect(_on_imposter_mode_changed)
    AppState.channel_selected.connect(_on_app_channel_selected)

func _on_channels_updated(guild_id: String) -> void:
    if guild_id != _current_guild_id: return
    load_guild(guild_id)

func _on_imposter_mode_changed(_active: bool) -> void:
    if _current_guild_id.is_empty(): return
    load_guild(_current_guild_id)
```

With gedis:

```gdscript
# Proposed: channel_list.gd
func _ready():
    Gedis.hwatch("channel", "*", _on_channel_changed)

func _on_channel_changed(_key: String, channel: Dictionary) -> void:
    if channel.get("guild_id", "") != Gedis.get("ui:current_guild_id", ""):
        return
    _update_channel_item(channel)
```

For the guild bar, which currently tears down and rebuilds all guild icons on `guilds_updated`, gedis enables per-guild updates — a watcher on `guild:{id}` can update just the unread badge or icon without rebuilding the entire bar.

## Implementation Status

- [ ] Gedis addon created in `addons/gedis/`
- [ ] Core KV store (`set`, `get`, `has`, `del`, `keys`)
- [ ] Hash operations (`hset`, `hget`, `hgetall`, `hdel`)
- [ ] List operations (`lset`, `lget`)
- [ ] Watch/unwatch system with glob pattern matching
- [ ] Change detection (only fire watchers on actual value change)
- [ ] Autoload registration
- [ ] Migrate AppState UI state vars to gedis keys
- [ ] Migrate Client cache dictionaries to gedis hashes
- [ ] Update UI components to use gedis watchers instead of signal connections
- [ ] Unit tests for core KV operations
- [ ] Unit tests for watch dispatch and pattern matching
- [ ] Performance benchmarks comparing signal dispatch vs gedis watch dispatch

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Addon does not exist yet | High | Entire feature is proposed, no code written |
| Migration strategy for AppState signals | Medium | ~60 signals to migrate; needs incremental approach where gedis and AppState coexist during transition |
| Batch update support | Medium | Gateway events often update multiple related keys (e.g., new message + unread flag + mention count). Need a `Gedis.multi()` / `Gedis.exec()` pattern to batch writes and fire watchers once |
| Pattern watch performance | Low | `String.match()` glob matching on every write could be slow if many pattern watchers are registered. May need an index or trie for pattern lookup |
| Memory overhead vs current approach | Low | Current caches are plain Dictionaries with zero overhead. Gedis adds a watch registry per key. Likely negligible for daccord's scale but worth measuring |
| No persistence layer | Low | By design, gedis is in-memory only. Session restore would need a separate dump/restore mechanism if config-backed state moves into gedis |
| Message/member list integration | Low | These scale-sensitive collections should stay with their current targeted-update approach; gedis should not attempt to replace them |
