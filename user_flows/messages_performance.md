# Messages Performance

Last touched: 2026-02-19

## Overview

This document covers the performance characteristics and optimization strategies for the messaging system. It covers how messages are cached, rendered, and updated — including the full re-render strategy, avatar image caching, markdown-to-BBCode conversion costs, user cache trimming, and the targeted reaction update path. The primary bottleneck is the full scene tree rebuild on every `messages_updated` signal; optimizations like the `_message_id_index`, avatar LRU cache, and targeted `reactions_updated` path mitigate some cost.

## User Steps

1. User selects a channel — `Client.fetch.fetch_messages()` fetches up to 50 messages from the server.
2. Messages are converted from AccordKit models to dictionary shapes and stored in `_message_cache`.
3. `message_view._load_messages()` clears all message nodes and instantiates new cozy/collapsed scenes for each message.
4. User sends or receives messages — gateway fires `message.create`, cache is updated, `messages_updated` emits, full re-render occurs.
5. User scrolls up and clicks "Show older messages" — `fetch_older_messages()` prepends to cache, full re-render occurs, scroll position is restored.
6. A reaction is added/removed — `reactions_updated` fires, only the affected message's reaction bar is rebuilt (no full re-render).

## Signal Flow

```
Channel selected:
  _on_channel_selected()
    -> Client.fetch.fetch_messages(channel_id)
      -> REST: GET /channels/{id}/messages?limit=50
      -> For each unknown author: REST GET /users/{id} (sequential, blocking)
      -> ClientModels.message_to_dict() per message (regex-heavy markdown conversion)
      -> _message_cache[channel_id] = msgs
      -> _message_id_index updated
      -> trim_user_cache() called
    -> AppState.messages_updated.emit(channel_id)
    -> message_view._on_messages_updated()
      -> _load_messages() [FULL RE-RENDER]
        -> Save editing state
        -> queue_free() all message children
        -> Instantiate N cozy/collapsed scenes
        -> Each scene.setup(data):
          -> cozy_message: avatar.set_avatar_url() (HTTP fetch or LRU cache hit)
          -> message_content: ClientModels.markdown_to_bbcode() (9+ regex passes)
          -> reaction_bar: instantiate ReactionPillScene per reaction
          -> image attachments: HTTPRequest per image (async)
        -> Restore editing state
        -> Animated scroll to bottom

Reaction update (optimized path):
  Gateway: reaction_add/remove/clear
    -> client_gateway_reactions updates _message_cache in-place
    -> AppState.reactions_updated.emit(channel_id, message_id)
    -> message_view._on_reactions_updated()
      -> Linear scan of message_list children to find matching message_id
      -> reaction_bar.setup() rebuilds only that message's pills
      -> NO full re-render
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/message_view.gd` | Full re-render loop (`_load_messages`), scene instantiation, scroll management, action bar positioning via `_process()` |
| `scenes/messages/cozy_message.gd` | Per-message setup: avatar load, reply reference lookup, mention check, context menu creation |
| `scenes/messages/collapsed_message.gd` | Lighter per-message setup: no avatar, timestamp parsing, mention check |
| `scenes/messages/message_content.gd` | Markdown-to-BBCode rendering, attachment HTTP fetches, embed instantiation, inline edit mode |
| `scenes/messages/reaction_bar.gd` | Clears and recreates all `ReactionPillScene` children on every `setup()` call |
| `scenes/messages/reaction_pill.gd` | Creates a new `StyleBoxFlat` on every `_update_active_style()` call (called during setup and toggle) |
| `scenes/common/avatar.gd` | Static LRU image cache (cap 200), HTTP fetch for uncached avatars, shader material creation |
| `scripts/autoload/client.gd` | `_message_cache`, `_message_id_index`, `MESSAGE_CAP` (50), `USER_CACHE_CAP` (500) |
| `scripts/autoload/client_fetch.gd` | `fetch_messages()` / `fetch_older_messages()` — sequential author fetches, model conversion |
| `scripts/autoload/client_gateway.gd` | `on_message_create/update/delete` — cache mutation, cap enforcement via `pop_front()` |
| `scripts/autoload/client_gateway_reactions.gd` | In-place reaction cache mutation, `reactions_updated` signal (skips own reactions for optimistic UI) |
| `scripts/autoload/client_markdown.gd` | `markdown_to_bbcode()` — 9+ compiled regexes per call, BBCode sanitization pass |
| `scripts/autoload/client_emoji.gd` | Custom emoji disk cache, download dedup via `_emoji_download_pending`, user cache trimming |
| `scripts/autoload/client_models.gd` | `message_to_dict()` conversion, `_format_timestamp()` per message, `is_user_mentioned()` check |

## Implementation Details

### Message Cache Architecture (client.gd, client_fetch.gd)

- **In-memory cache**: `_message_cache` is a `Dictionary` keyed by channel ID, each value an `Array` of message dictionaries (line 47). No persistence across sessions.
- **Message cap**: `MESSAGE_CAP = 50` (line 11). When a new message arrives via gateway, `pop_front()` evicts the oldest if the array exceeds 50 (client_gateway.gd line 184). This bounds memory but means scrolling up requires a server fetch.
- **Message ID index**: `_message_id_index` maps message ID to channel ID for O(1) lookup (client.gd line 58). `get_message_by_id()` uses the index first, falls back to linear scan across all channels if the index is stale (lines 266-277).
- **Index maintenance**: Old index entries are cleared before replacing a channel's cache (client_fetch.gd line 175-177). New entries are added for each message (line 180-181). Gateway events maintain the index on create (client_gateway.gd line 182) and delete (line 255).

### Full Re-render Strategy (message_view.gd)

- **Trigger**: Every `messages_updated` signal causes `_load_messages()` to run (line 304-306). This includes new messages, edits, deletes, and older message loads — all trigger a complete teardown and rebuild of the message list.
- **Teardown cost**: Iterates all children of `message_list`, calling `queue_free()` on each non-persistent node (lines 189-192). Persistent nodes (older_btn, empty_state, loading_label) are skipped.
- **Rebuild cost**: For each of the up to 50+ messages, instantiates either a `CozyMessageScene` or `CollapsedMessageScene`, calls `setup()`, and connects hover signals (lines 205-227). Each `setup()` involves:
  - **cozy_message**: avatar URL set (HTTP or cache), author label styling, reply reference lookup via `Client.get_message_by_id()` (linear scan), mention check scanning member list, context menu creation, `message_content.setup()`.
  - **collapsed_message**: timestamp parsing, `message_content.setup()`, mention check.
  - **message_content**: `ClientModels.markdown_to_bbcode()` (9+ regex passes), embed setup, attachment HTTP requests, reaction bar instantiation.
- **Editing state preservation**: Before clearing, saves the editing message ID and text content by iterating children (lines 173-183). After rebuild, restores by scanning new children (lines 230-238). Two full scans of the child list per re-render when editing.
- **Animation decisions**: Tracks `_old_message_count` to detect single-message appends vs channel transitions. Single new messages get a fade-in on the last child (lines 243-250). Channel transitions get a full container fade (lines 251-258).
- **Frame yield**: `await get_tree().process_frame` before animated scroll (line 263) ensures layout is computed before scrolling.

### Targeted Reaction Update (message_view.gd, client_gateway_reactions.gd)

- **Optimized path**: `reactions_updated` signal (line 308) triggers `_on_reactions_updated()` which only rebuilds the affected message's reaction bar — no full re-render.
- **Finding the message**: Linear scan of `message_list` children comparing `_message_data["id"]` (lines 312-321). For 50 messages, this is negligible.
- **Own reaction skip**: `client_gateway_reactions.gd` skips emitting `reactions_updated` for the user's own reactions (lines 47-49, 73-75) because the pill already shows the optimistic state.
- **Reaction bar rebuild**: `reaction_bar.setup()` calls `queue_free()` on all pill children and recreates them (reaction_bar.gd lines 6-7). Creates new `ReactionPillScene` instances for each reaction.

### Markdown-to-BBCode Conversion Cost (client_markdown.gd)

- **Per-call cost**: Every `markdown_to_bbcode()` invocation compiles 9+ regex objects from scratch (lines 9-66). These are local variables, not cached between calls.
- **Regex passes**: Code blocks, inline code, strikethrough, underline, bold, italic, spoilers, blockquotes, links (manual replacement loop), emoji shortcodes (manual replacement loop).
- **Link processing**: Iterates matches in reverse and performs string concatenation for each (lines 43-55). O(n*m) where n = result string length, m = link count.
- **Emoji processing**: Iterates emoji matches in reverse, does `EmojiData.get_by_name()` lookup and custom emoji path lookup per match (lines 67-79).
- **BBCode sanitization**: Character-by-character scan of the non-code portions, checking each `[` against an allowed prefix list (lines 85-140). O(n*p) where p = number of allowed prefixes (18).
- **Total per message load**: For 50 messages, `markdown_to_bbcode()` runs 50 times, compiling 450+ regex objects. These are not cached.

### Avatar Image Caching (avatar.gd)

- **Static LRU cache**: `_image_cache` is a class-level static Dictionary mapping URL to `ImageTexture` (line 7). Shared across all avatar instances. Cap is 200 entries (line 6).
- **Cache hit path**: If URL is in cache, immediately applies the texture — no HTTP request (lines 47-50). `_touch_cache()` moves the URL to the end of the access order array.
- **Cache miss path**: Creates an `HTTPRequest` child, fetches the image, tries PNG/JPG/WebP parsing, stores in cache, applies texture (lines 53-79).
- **Eviction**: LRU via `_cache_access_order` array. `_evict_cache()` removes the oldest entries when the cache exceeds 200 (lines 122-126). Note: `remove_at(0)` on an array is O(n).
- **Per-re-render impact**: On full re-render, all cozy messages call `set_avatar_url()`. With warm cache (same channel), these are cache hits. On channel switch, many may be cache misses triggering HTTP fetches.

### User Cache Management (client.gd, client_emoji.gd)

- **User cache**: `_user_cache` maps user ID to user dictionary (line 43). Cap is 500 (line 13). Trimming runs after `fetch_messages()` (client_fetch.gd line 183).
- **Trim strategy** (client_emoji.gd lines 59-80): Builds a `keep` set of the current user, current guild members, and current channel message authors. Erases all others. This is O(members + messages + cache_size).
- **Sequential author fetches**: `fetch_messages()` fetches unknown authors one at a time with `await` (client_fetch.gd lines 157-168). If 10 messages have unknown authors, that's 10 sequential HTTP requests before the messages display. This is the most impactful performance bottleneck for initial channel loads.

### Reply Reference Lookup (cozy_message.gd)

- **Per-message cost**: If a message has `reply_to`, `Client.get_message_by_id()` is called (line 66). This uses the `_message_id_index` for O(1) lookup, falling back to linear scan across all channels if the index misses (client.gd lines 266-277).
- **Index miss fallback**: Iterates all channels' message arrays. With 10 channels × 50 messages each = 500 iterations worst case.
- **Missing reply**: If the referenced message isn't in cache (e.g., it was evicted or from before the user joined), the reply reference is simply not shown — no additional fetch is made.

### Older Messages Loading (message_view.gd)

- **Scroll position preservation**: Saves `scroll_vertical` and `max_value` before loading (lines 576-577). After re-render and a frame yield, computes the diff and restores position (lines 583-585). This prevents the view from jumping.
- **Full re-render**: Loading older messages still triggers a full re-render via `messages_updated` (client_fetch.gd line 259). The `_is_loading_older` flag prevents auto-scroll and triggers the correct animation path (line 261).
- **Cache growth**: Older messages prepend to the existing array (client_fetch.gd line 254-255). There's no cap on accumulated messages — repeated "Show older" presses grow the cache unboundedly. Only `MESSAGE_CAP` limits the tail via `pop_front()` on new messages.

### Action Bar Positioning (message_view.gd)

- **Per-frame cost**: `_process()` runs every frame when the action bar is visible, calling `_position_action_bar()` (lines 112-118). This reads global rects from two Controls and performs bounds clamping.
- **Hover state machine**: 100ms debounce timer, `_hover_hide_pending` flag, and `is_bar_hovered()` check prevent flickering (lines 333-374). Minimal overhead.

### Reaction Pill Style Allocation (reaction_pill.gd)

- **New StyleBoxFlat per call**: `_update_active_style()` creates a brand new `StyleBoxFlat` with 12 property sets on every invocation (lines 77-99). Called during `setup()` and on every toggle. For a message with 5 reactions, that's 5 StyleBoxFlat allocations on render.

### Image Attachment Loading (message_content.gd)

- **Per-attachment HTTP fetch**: Each image attachment creates an `HTTPRequest`, fetches the image, tries PNG/JPG/WebP parsing, and creates an `ImageTexture` (lines 109-149). No caching — re-rendered messages re-fetch images.
- **Image scaling**: Images larger than 400×300 are resized in-memory using `Image.resize()` (lines 135-142). This is a CPU-bound operation.
- **HTTPRequest lifecycle**: The HTTPRequest node is added as a child, then freed after completion (lines 110-117). Multiple image attachments create multiple concurrent HTTP requests.

### Typing Indicator Animation (typing_indicator.gd)

- **Efficient idle**: `set_process(false)` when hidden (line 23). The `_process()` callback only runs while typing is visible.
- **Minimal per-frame cost**: Three sine calculations and alpha assignments (lines 25-31). Negligible.

### Gateway Message Event Processing (client_gateway.gd)

- **Message create** (lines 160-231): Potentially awaits a user fetch if author is unknown. Converts to dict, appends to cache, enforces cap via `pop_front()`, checks unread/mention status, plays notification sound, updates DM preview. Then emits `messages_updated` triggering full re-render.
- **Message update** (lines 233-244): Linear scan to find the message in cache, replaces the dict in-place. Emits `messages_updated` triggering full re-render.
- **Message delete** (lines 246-257): Linear scan, `remove_at()`, index cleanup. Emits `messages_updated` triggering full re-render.
- **Bulk delete** (lines 259-275): Builds a set of IDs, reverse-iterates the cache array. Single `messages_updated` emit for all deletions.

### Context Menu / PopupMenu Creation (cozy_message.gd, collapsed_message.gd)

- **Per-message cost**: Each message node creates its own `PopupMenu` in `_ready()` with 5 items and a signal connection (cozy_message.gd lines 34-41, collapsed_message.gd lines 27-34). For 50 messages, that's 50 PopupMenus allocated.
- **LongPressDetector**: Each message also creates a `LongPressDetector` instance (cozy_message.gd line 44, collapsed_message.gd line 37).

## Implementation Status

- [x] Message cache with 50-message cap per channel
- [x] Message ID index for O(1) lookup
- [x] User cache with 500-user cap and LRU-style trimming
- [x] Avatar image LRU cache (200 entries, shared static)
- [x] Targeted reaction update path (no full re-render for reactions)
- [x] Own-reaction optimistic UI (skips gateway signal for self)
- [x] Typing indicator disabled when hidden (no idle processing)
- [x] Scroll position preservation on older message load
- [x] Single-message fade-in animation (avoids channel transition animation)
- [x] Emoji download deduplication
- [x] Custom emoji disk caching
- [ ] Incremental message rendering (diff-based updates instead of full re-render)
- [ ] Regex caching for markdown-to-BBCode conversion
- [ ] Image attachment caching
- [ ] Batch/parallel user fetching for unknown authors
- [ ] Object pooling for message scenes
- [ ] StyleBoxFlat reuse for reaction pills

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Full re-render on every update | High | `_load_messages()` clears and recreates all message nodes for every `messages_updated` signal (message_view.gd line 304). A single new message, edit, or delete destroys and rebuilds 50+ scene instances. Implement incremental insert/update/remove to avoid full teardown. |
| Regex objects compiled per call | Medium | `markdown_to_bbcode()` creates 9+ `RegEx` objects as local variables on every invocation (client_markdown.gd lines 9-66). For 50 messages, that's 450+ regex compilations per channel load. Cache compiled regexes as static class variables. |
| Sequential author fetches on channel load | High | `fetch_messages()` awaits each unknown author fetch one at a time (client_fetch.gd lines 157-168). 10 unknown authors = 10 sequential HTTP round-trips before messages display. Batch these into parallel requests or use a bulk user endpoint. |
| No image attachment caching | Medium | Image attachments are re-fetched via HTTP on every full re-render (message_content.gd lines 109-149). Unlike avatars, there is no cache. Add an image cache similar to the avatar LRU cache. |
| StyleBoxFlat allocated per pill per render | Low | `_update_active_style()` creates a new StyleBoxFlat with 12 property assignments every time (reaction_pill.gd lines 77-99). Use two pre-allocated static StyleBoxFlat instances (active/inactive) instead. |
| PopupMenu created per message node | Low | Each cozy and collapsed message allocates its own PopupMenu and LongPressDetector in `_ready()` (cozy_message.gd lines 34-44, collapsed_message.gd lines 27-37). 50 messages = 50 PopupMenus. Share a single PopupMenu at the message_view level, similar to the shared action bar. |
| Unbounded cache growth from older messages | Low | Repeated "Show older messages" prepends to the cache array without any cap (client_fetch.gd line 254). Only the tail is capped via `pop_front()` on new messages. A channel with long history could accumulate hundreds of cached messages. |
| Avatar LRU eviction uses O(n) remove_at(0) | Low | `_evict_cache()` calls `_cache_access_order.remove_at(0)` which is O(n) for an Array (avatar.gd line 125). With a cap of 200 this is negligible, but would matter at larger scales. |
| Reply reference fetch for evicted messages | Low | If the replied-to message is not in cache, the reply reference is silently omitted (cozy_message.gd lines 64-76). No lazy fetch is attempted. For conversations with frequent replies to older messages, reply context is lost. |
