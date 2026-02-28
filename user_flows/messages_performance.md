# Messages Performance

Last touched: 2026-02-19

## Overview

This document covers the performance characteristics and optimization strategies for the messaging system. It covers how messages are cached, rendered, and updated — including incremental diff-based rendering, avatar image caching, cached markdown-to-BBCode conversion, parallel author fetching, user cache trimming, image attachment caching, the targeted reaction update path, and the shared context menu. The `_message_node_index` enables O(1) message node lookup, and diff-based rendering avoids full teardowns on most updates. Regex objects are compiled once and cached as static variables. Unknown authors are fetched in parallel. Image attachments use a static LRU cache (cap 100). A single shared PopupMenu replaces per-message PopupMenu allocations.

## User Steps

1. User selects a channel — `Client.fetch.fetch_messages()` fetches up to 50 messages from the server, with unknown authors fetched in parallel.
2. Messages are converted from AccordKit models to dictionary shapes and stored in `_message_cache`.
3. `message_view._load_messages()` clears all message nodes and instantiates new cozy/collapsed scenes, populating `_message_node_index`.
4. User sends or receives messages — gateway fires `message.create`, cache is updated, `messages_updated` emits, diff-based update appends new node without re-rendering existing ones.
5. User edits or deletes a message — diff-based update calls `update_data()` on existing node (edit) or removes the specific node (delete), fixing cozy/collapsed layout as needed.
6. User scrolls up and clicks "Show older messages" — `fetch_older_messages()` prepends to cache (capped at 200), full re-render occurs, scroll position is restored.
7. A reaction is added/removed — `reactions_updated` fires, O(1) index lookup finds the node, only that message's reaction bar is rebuilt.

## Signal Flow

```
Channel selected (first load):
  _on_channel_selected()
    -> _message_node_index.clear()
    -> Client.fetch.fetch_messages(channel_id)
      -> REST: GET /channels/{id}/messages?limit=50
      -> Unknown authors fetched in PARALLEL (all coroutines fired, then awaited)
      -> ClientModels.message_to_dict() per message (cached regex markdown conversion)
      -> _message_cache[channel_id] = msgs
      -> _message_id_index updated
      -> trim_user_cache() called
    -> AppState.messages_updated.emit(channel_id)
    -> message_view._on_messages_updated()
      -> _message_node_index empty -> _load_messages() [FULL RENDER]
        -> Instantiate N cozy/collapsed scenes
        -> Each scene.setup(data):
          -> cozy_message: avatar (LRU cache hit or HTTP), reply ref (lazy-fetch if evicted)
          -> message_content: ClientModels.markdown_to_bbcode() (cached static regex)
          -> reaction_bar: instantiate ReactionPillScene (shared static StyleBoxFlat)
          -> image attachments: LRU cache hit or HTTP fetch (cached in static _att_image_cache)
        -> Populate _message_node_index
        -> Connect context_menu_requested signal to shared PopupMenu
        -> Animated scroll to bottom

Incremental update (new message / edit / delete):
  Gateway: message.create/update/delete
    -> Cache updated, messages_updated emitted
    -> message_view._on_messages_updated()
      -> _diff_messages() [INCREMENTAL]
        -> REMOVE: queue_free nodes not in cache, remove from index
        -> UPDATE: call node.update_data(data) for changed content (skips if editing)
        -> APPEND: instantiate only new nodes at the end
        -> FIXUP: promote collapsed->cozy or vice versa if predecessor changed
        -> Fade-in animation on appended nodes only

Reaction update (O(1) path):
  Gateway: reaction_add/remove/clear
    -> client_gateway_reactions updates _message_cache in-place
    -> AppState.reactions_updated.emit(channel_id, message_id)
    -> message_view._on_reactions_updated()
      -> O(1) lookup via _message_node_index[message_id]
      -> reaction_bar.setup() rebuilds only that message's pills
      -> NO re-render
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

### Incremental Rendering Strategy (message_view.gd)

- **First load**: When `_message_node_index` is empty (channel switch), falls back to `_load_messages()` which does a full render and populates the index.
- **Diff-based updates**: On subsequent `messages_updated` signals, `_diff_messages()` compares the cache against `_message_node_index`:
  - **REMOVE**: Nodes for deleted messages are `queue_free()`'d and removed from the index.
  - **UPDATE**: Existing nodes have `update_data(data)` called, which re-renders text content via `update_content()` without rebuilding avatar/author/timestamp. Skipped if the node is in edit mode.
  - **APPEND**: New messages at the end are instantiated and added. Only the new nodes run `setup()`.
  - **FIXUP**: After deletions, layout mismatches (collapsed message that should now be cozy due to predecessor change) are detected and nodes are replaced.
  - **FALLBACK**: If order inconsistency is detected (middle insertion), falls back to `_load_messages()` for correctness.
- **Node index**: `_message_node_index` maps message ID to scene node for O(1) lookup. Populated during `_load_messages()` and maintained by `_diff_messages()`.
- **Editing state**: No longer needs save/restore since nodes survive incremental updates. `update_content()` skips if `is_editing()` returns true.
- **Animation**: Only appended nodes get fade-in animation. No channel transition animation on incremental updates.

### Targeted Reaction Update (message_view.gd, client_gateway_reactions.gd)

- **O(1) path**: `reactions_updated` signal triggers `_on_reactions_updated()` which uses `_message_node_index` for O(1) node lookup — no linear scan needed.
- **Fallback**: If the index misses, falls back to linear scan of `message_list` children.
- **Own reaction skip**: `client_gateway_reactions.gd` skips emitting `reactions_updated` for the user's own reactions because the pill already shows the optimistic state.
- **Reaction bar rebuild**: `reaction_bar.setup()` recreates pill children. Each pill uses shared static `StyleBoxFlat` instances (active/inactive) instead of allocating new ones.

### Markdown-to-BBCode Conversion (client_markdown.gd)

- **Cached regex**: All 11 regex objects are compiled once on first call via `_ensure_compiled()` and stored as static class variables. Subsequent calls reuse the same compiled instances.
- **Regex passes**: Code blocks, inline code, strikethrough, underline, bold, italic, spoilers, blockquotes, links (manual replacement loop), emoji shortcodes (manual replacement loop).
- **Link processing**: Iterates matches in reverse and performs string concatenation for each. O(n*m) where n = result string length, m = link count.
- **Emoji processing**: Iterates emoji matches in reverse, does `EmojiData.get_by_name()` lookup and custom emoji path lookup per match.
- **BBCode sanitization**: Uses the cached `_code_splitter_regex` to split on code blocks, then character-by-character scan of non-code portions.
- **Total per message load**: For 50 messages, `markdown_to_bbcode()` runs 50 times but with zero regex compilation overhead (all 11 cached).

### Avatar Image Caching (avatar.gd)

- **Static LRU cache**: `_image_cache` is a class-level static Dictionary mapping URL to `ImageTexture` (line 7). Shared across all avatar instances. Cap is 200 entries (line 6).
- **Cache hit path**: If URL is in cache, immediately applies the texture — no HTTP request (lines 47-50). `_touch_cache()` moves the URL to the end of the access order array.
- **Cache miss path**: Creates an `HTTPRequest` child, fetches the image, tries PNG/JPG/WebP parsing, stores in cache, applies texture (lines 53-79).
- **Eviction**: LRU via `_cache_access_order` array. `_evict_cache()` removes the oldest entries when the cache exceeds 200 (lines 122-126). Note: `remove_at(0)` on an array is O(n).
- **Per-re-render impact**: On full re-render, all cozy messages call `set_avatar_url()`. With warm cache (same channel), these are cache hits. On channel switch, many may be cache misses triggering HTTP fetches.

### User Cache Management (client.gd, client_emoji.gd)

- **User cache**: `_user_cache` maps user ID to user dictionary (line 43). Cap is 500 (line 13). Trimming runs after `fetch_messages()` (client_fetch.gd line 183).
- **Trim strategy** (client_emoji.gd lines 59-80): Builds a `keep` set of the current user, current space members, and current channel message authors. Erases all others. This is O(members + messages + cache_size).
- **Parallel author fetches**: `_fetch_unknown_authors_parallel()` collects unique uncached author IDs, fires all fetch coroutines simultaneously, then awaits them all. 10 unknown authors load in ~1 round-trip instead of 10 sequential round-trips.

### Reply Reference Lookup (cozy_message.gd)

- **Per-message cost**: If a message has `reply_to`, `Client.get_message_by_id()` is called. This uses the `_message_id_index` for O(1) lookup, falling back to linear scan across all channels if the index misses.
- **Lazy fetch for evicted messages**: If the replied-to message is not in cache, a "Loading reply..." placeholder is shown and `_fetch_reply_reference()` asynchronously fetches the message from the server. On success, the reply reference is updated in-place. On failure, "[original message unavailable]" is shown. Guarded with `is_instance_valid(self)` after awaits.

### Older Messages Loading (message_view.gd)

- **Scroll position preservation**: Saves `scroll_vertical` and `max_value` before loading. After re-render and a frame yield, computes the diff and restores position. This prevents the view from jumping.
- **Full re-render**: Loading older messages still triggers a full re-render via `messages_updated`. The `_is_loading_older` flag prevents auto-scroll and triggers the correct animation path.
- **Cache cap**: `MAX_CHANNEL_MESSAGES = 200`. After prepending older messages, the combined array is capped by evicting from the back (newest). When the user returns to the channel fresh, `fetch_messages()` re-fetches the latest 50.

### Action Bar Positioning (message_view.gd)

- **Per-frame cost**: `_process()` runs every frame when the action bar is visible, calling `_position_action_bar()` (lines 112-118). This reads global rects from two Controls and performs bounds clamping.
- **Hover state machine**: 100ms debounce timer, `_hover_hide_pending` flag, and `is_bar_hovered()` check prevent flickering (lines 333-374). Minimal overhead.

### Reaction Pill Style Allocation (reaction_pill.gd)

- **Shared static StyleBoxFlat**: Two pre-allocated static `StyleBoxFlat` instances (`_style_active` and `_style_inactive`) are lazily initialized via `_ensure_styles()`. All pills share the same instances, eliminating per-pill allocation. Called during `setup()` and on every toggle.

### Image Attachment Loading (message_content.gd)

- **Static LRU cache**: `_att_image_cache` maps URL to `ImageTexture`, shared across all message_content instances. Cap is 100 entries. `_att_cache_order` tracks access order for LRU eviction.
- **Cache hit path**: If URL is in cache, immediately creates a TextureRect with the cached texture — no HTTP request.
- **Cache miss path**: Creates an `HTTPRequest`, fetches the image, tries PNG/JPG/WebP parsing, stores in cache, applies texture.
- **Image scaling**: Images larger than 400×300 are resized in-memory using `Image.resize()`. The scaled texture is cached, so re-renders use the pre-scaled version.

### List Virtualization (not yet implemented)

- **Problem**: `_load_messages()` instantiates a scene node for every message in the cache — up to 50 on initial load, and unbounded when the user clicks "Show older messages" repeatedly. Each node runs `setup()` which involves markdown regex conversion, avatar loading, embed instantiation, and PopupMenu/LongPressDetector allocation. Only ~10-15 messages are visible in the viewport at any time, so the vast majority of this work is wasted on off-screen nodes.
- **Goal**: Only instantiate and keep alive the message nodes that are currently visible (plus a small buffer above and below the viewport). As the user scrolls, recycle or create/destroy nodes at the edges.
- **Approach — ScrollContainer + virtual item management**:
  1. Maintain a `total_content_height` estimate based on message count × average item height. Use a spacer Control at the top of `message_list` sized to represent the off-screen area above the visible window.
  2. On scroll (`scroll_vertical` changed), calculate which message indices fall within the visible range (viewport top to viewport bottom, plus a buffer of ~5 messages in each direction).
  3. Only instantiate scene nodes for messages in that range. Store a mapping of message index → node. When a message index scrolls out of the buffer, `queue_free()` its node. When a new index scrolls in, instantiate and `setup()` a new node.
  4. Cozy vs collapsed layout decision still applies per-message based on the previous message's author/reply status — this can be computed from the cache array without needing the previous node to exist.
- **Height estimation**: Messages have variable height (replies, embeds, images, multi-line content). Options:
  - **Fixed estimate with correction**: Start with an average height (e.g., 60px cozy, 30px collapsed). After a node is instantiated and laid out, record its actual height. Use actual heights for measured messages, estimates for unmeasured ones. Update the top spacer accordingly.
  - **Pre-measure pass**: Not practical — measuring requires instantiation, which defeats the purpose.
- **Scroll position stability**: When recycling nodes or updating height estimates, adjust `scroll_vertical` to compensate so the user's view doesn't jump. This is the same problem already solved for "Show older messages" (lines 576-585) but needs to be generalized.
- **Impact on existing features**:
  - **Action bar hover**: Currently finds the hovered message by iterating `message_list` children. With virtualization, only visible children exist, so this still works — but the index in the child list no longer matches the index in the cache array.
  - **Editing state preservation**: Currently scans all children to save/restore. With virtualization, editing state should be tracked by message ID in `message_view`, not by scanning nodes.
  - **Reaction updates**: `_on_reactions_updated()` scans children for a matching message ID. With virtualization, if the target message is off-screen, no node exists — the cache is already updated, so the node will render correctly when it scrolls into view.
  - **Animations**: Single-message fade-in only applies to the newest message. With virtualization, this only fires if the user is scrolled to the bottom (which is the common case).
  - **Auto-scroll**: The "scroll to bottom on new message" behavior works the same — set `scroll_vertical` to max, which triggers the virtualization window to update.
- **Expected gains**: For a channel with 50 cached messages where ~12 are visible, virtualization reduces instantiated nodes from 50 to ~22 (12 visible + 5 buffer each direction). That's 28 fewer `setup()` calls, 28 fewer markdown regex conversions, 28 fewer PopupMenu allocations, and 28 fewer avatar lookups per render. For channels where the user has loaded hundreds of older messages, the savings are proportionally larger.

### Typing Indicator Animation (typing_indicator.gd)

- **Efficient idle**: `set_process(false)` when hidden (line 23). The `_process()` callback only runs while typing is visible.
- **Minimal per-frame cost**: Three sine calculations and alpha assignments (lines 25-31). Negligible.

### Gateway Message Event Processing (client_gateway.gd)

- **Message create**: Potentially awaits a user fetch if author is unknown. Converts to dict, appends to cache, enforces cap via `pop_front()`, checks unread/mention status, plays notification sound, updates DM preview. Then emits `messages_updated` — diff-based update appends one node.
- **Message update**: Linear scan to find the message in cache, replaces the dict in-place. Emits `messages_updated` — diff-based update calls `update_data()` on the existing node.
- **Message delete**: Linear scan, `remove_at()`, index cleanup. Emits `messages_updated` — diff-based update removes only the affected node and fixes layout.
- **Bulk delete**: Builds a set of IDs, reverse-iterates the cache array. Single `messages_updated` emit for all deletions.

### Shared Context Menu (message_view.gd)

- **Single PopupMenu**: A single `PopupMenu` is created in `message_view._ready()` and shared across all messages. Messages emit `context_menu_requested(pos, msg_data)` instead of managing their own PopupMenu.
- **LongPressDetector**: Each message still creates its own `LongPressDetector` instance for touch support, but it emits the same `context_menu_requested` signal instead of showing a per-message menu.
- **Reaction picker**: Moved to `message_view`, shared via `_open_reaction_picker(msg_data)`.

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
- [x] Incremental message rendering (diff-based updates instead of full re-render)
- [x] Regex caching for markdown-to-BBCode conversion
- [x] Image attachment caching (LRU, cap 100)
- [x] Batch/parallel user fetching for unknown authors
- [x] StyleBoxFlat reuse for reaction pills (two shared static instances)
- [x] Shared PopupMenu at message_view level (one for all messages)
- [x] Older message cache cap (MAX_CHANNEL_MESSAGES = 200)
- [x] Lazy-fetch reply references (placeholder + async fetch for evicted messages)
- [ ] List virtualization (only render visible messages + buffer, recycle off-screen nodes)
- [ ] Object pooling for message scenes

## Tasks

### MSGPERF-1: No list virtualization
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** performance
- **Notes:** All cached messages are instantiated as scene nodes regardless of viewport visibility (message_view.gd `_load_messages()`). With 50 messages cached and ~12 visible, 38 nodes are fully set up off-screen. Virtualize the list to only instantiate nodes within the visible range plus a small scroll buffer.

### MSGPERF-2: Avatar LRU eviction uses O(n) remove_at(0)
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** performance
- **Notes:** `_evict_cache()` calls `_cache_access_order.remove_at(0)` which is O(n) for an Array (avatar.gd line 125). With a cap of 200 this is negligible, but would matter at larger scales.
