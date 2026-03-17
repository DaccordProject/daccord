# File Sharing

Last touched: 2026-03-17
Priority: 30
Depends on: Messaging

## Overview

File sharing covers uploading files as message attachments, rendering received attachments (images inline, other files as download links), and the full server-side storage pipeline. The upload path is wired end-to-end: the composer's upload button opens a file picker, selected files appear as pending attachments, and on send the client constructs a multipart/form-data request that the server stores to disk and persists in the `attachments` database table. Attachment data is returned in message JSON responses and rendered by the client. Clipboard image paste (Ctrl+V), large-text-to-file conversion, drag-and-drop file upload, an upload progress indicator, and an attachment count limit (max 10) are all implemented.

## User Steps

### Sending a file attachment
1. User clicks the **Upload** button (paperclip icon) in the composer.
2. A native `FileDialog` opens, allowing the user to choose one or more files.
3. Selected files appear in the **AttachmentBar** above the composer input, showing filename and size with a remove button for each.
4. User optionally adds message text.
5. User clicks Send or presses Enter.
6. The composer transfers pending files to `AppState.pending_attachments` and emits `message_sent`.
7. An "Uploading..." indicator is shown in the attachment bar while the request is in flight.
8. `message_view` reads `AppState.pending_attachments`, passes them to `Client.send_message_to_channel()`.
9. `ClientMutations` calls `MessagesApi.create_with_attachments()`, which builds a `MultipartForm` with `payload_json` (message metadata) and `files[N]` parts.
10. `AccordRest.make_multipart_request()` sends the raw bytes via `HTTPRequest.request_raw()` to `POST /channels/{id}/messages/upload`.
11. The server handler (`create_message_multipart`) saves files to `storage_path/attachments/{channel_id}/{message_id}/{filename}`, inserts rows into the `attachments` DB table, and broadcasts the message via gateway with the attachment data included.
12. All clients render the attachment — images inline, other files as clickable download links.
13. The "Uploading..." indicator is dismissed when `messages_updated` fires.

### Pasting an image from clipboard
1. User copies an image (e.g. screenshot) to the system clipboard.
2. User presses **Ctrl+V** in the composer.
3. `_try_paste_image()` (line 177) calls `DisplayServer.clipboard_get_image()`.
4. If an image is found, it is encoded as PNG and added to `_pending_files` with a timestamped filename (`clipboard_<timestamp>.png`).
5. The attachment bar updates to show the pasted image.
6. User sends the message as usual.

### Pasting large text
1. User pastes text longer than 4 KB into the composer.
2. After the paste lands, `_check_large_paste_deferred()` (line 196) detects the length exceeds `LARGE_TEXT_THRESHOLD` (4096 bytes).
3. A clickable info label appears: "Large paste detected (X KB). Click here to attach as .txt instead."
4. If the user clicks the label, the text is converted to a `pasted_text.txt` attachment and the composer text is cleared.
5. If the user ignores it, the text remains in the input as a normal message.

### Drag-and-drop file upload
1. User drags one or more files from their file manager onto the application window.
2. `Window.files_dropped` signal fires, handled by `_on_window_files_dropped()` (line 242).
3. Each dropped file is processed through `_add_file_from_path()` with the same validation (size limit, attachment count limit).
4. Files appear in the attachment bar ready to send.

### Receiving attachments
1. A message arrives via the gateway with an `attachments` array.
2. `ClientModels.message_to_dict()` converts each `AccordAttachment` to a UI dictionary with CDN URLs (lines 280-301).
3. `message_content.gd` iterates attachments (lines 82-134):
   - **Images** (`content_type` starts with `image/`): downloaded via HTTPRequest, displayed inline as a scaled TextureRect (max 400x300). Clicking opens an in-app lightbox.
   - **Videos** (`content_type` starts with `video/`): shown as a placeholder with a play triangle; click opens in browser.
   - **Audio** (`content_type` starts with `audio/`): inline audio player with play/pause, progress slider, and time label.
   - **All files**: rendered as a clickable BBCode link showing filename and human-readable size.
4. Clicking a file link opens it in the system browser via `OS.shell_open()`.

### Sending text-only messages (unchanged)
When no files are attached, `ClientMutations` falls back to the existing `MessagesApi.create()` JSON path (line 80), so the upload path is additive and does not affect existing messaging.

## Signal Flow

```
[Upload button clicked]  [Ctrl+V paste]  [File drag-and-drop]
        |                      |                 |
        v                      v                 v
  _on_upload_button()    _try_paste_image()  _on_window_files_dropped()
  (line 266)             (line 177)          (line 242)
        |                      |                 |
        v                      v                 v
  FileDialog             DisplayServer       _add_file_from_path() x N
  .files_selected        .clipboard_get_image()  (line 281)
        |                      |                 |
        v                      v                 |
  _on_files_selected()   image → PNG encode      |
  (line 277)             (line 181)              |
        |                      |                 |
        v                      v                 v
  _add_file_from_path()  append to           _can_add_attachment() check
  x N (line 281)         _pending_files      (line 254, max 10)
  — _can_add_attachment() check (max 10)         |
  — reads file via FileAccess                    |
  — validates size (25 MB max)                   |
  — detects MIME type from extension             |
  — appends to _pending_files array              |
        |                      |                 |
        +------+---------------+-----------------+
               |
               v
  _update_attachment_bar()             (line 306)
  — shows filenames + sizes + remove buttons in AttachmentBar
               |
               v
  [User clicks Send / presses Enter]
               |
               v
  composer._on_send()                  (line 62)
  — copies _pending_files to AppState.pending_attachments
  — clears _pending_files
  — shows "Uploading..." indicator (line 77)
  — emits AppState.message_sent(text)
               |
               v
  message_view._on_message_sent()      (line 386)
  — reads AppState.pending_attachments
  — clears AppState.pending_attachments
  — calls Client.send_message_to_channel(cid, text, reply_to, attachments)
               |
               v
  ClientMutations.send_message_to_channel()   (line 62)
  — if attachments.is_empty(): client.messages.create(cid, data)
  — else: client.messages.create_with_attachments(cid, data, attachments)
               |
               v
  MessagesApi.create_with_attachments()       (line 49)
  — builds MultipartForm with payload_json + files[N] parts
  — calls AccordRest.make_multipart_request("POST", ".../messages/upload", form)
               |
               v
  AccordRest.make_multipart_request()         (line 109)
  — form.build() → PackedByteArray
  — form.get_content_type() → "multipart/form-data; boundary=..."
  — HTTPRequest.request_raw(url, headers, method, body_bytes)
               |
               v
  Server: create_message_multipart()   (messages.rs line 141)
  — extracts payload_json + file parts from multipart body
  — creates message row in DB
  — saves files to disk via storage::save_attachment()
  — inserts attachment rows via db::attachments::insert_attachment()
  — broadcasts message.create gateway event with attachments
               |
               v
  Gateway: MESSAGE_CREATE event
               |
               v
  Client._on_message_create() → caches message
               |
               v
  AppState.messages_updated.emit(channel_id)
               |
               v
  message_view._on_messages_updated() → re-renders message list
  composer._hide_upload_indicator()    → hides "Uploading..."
               |
               v
  message_content.setup() → renders attachments (lines 82-134)
               |
               ├── Image? → _load_image_attachment() → HTTPRequest → TextureRect
               │              click → AppState.image_lightbox_requested
               ├── Video? → _create_video_placeholder() → click opens in browser
               ├── Audio? → _create_audio_player() → inline play/pause
               └── File?  → RichTextLabel with [url] BBCode link
```

### Large text paste flow
```
[Ctrl+V in composer with text on clipboard]
        |
        v
  _check_large_paste_deferred()        (line 196)
  — waits one frame for paste to land
  — checks text.length() >= LARGE_TEXT_THRESHOLD (4096)
        |
        v
  error_label shows clickable prompt
        |
        v (if user clicks)
  _on_large_paste_clicked()            (line 219)
  — converts text_input.text to UTF-8 PackedByteArray
  — appends as "pasted_text.txt" to _pending_files
  — clears text_input
  — updates attachment bar
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/composer/composer.gd` | Upload button handler (line 266), FileDialog creation (lines 267-275), file reading and MIME detection (lines 281-304), pending attachment bar (lines 306-330), send with attachments (lines 62-96), clipboard paste (lines 177-194), large text paste detection (lines 196-235), drag-and-drop (lines 239-250), attachment count limit (lines 254-262), upload indicator (lines 362-378) |
| `scenes/messages/composer/composer.tscn` | Composer scene with UploadButton (line 63), AttachmentBar (line 54) |
| `scenes/messages/message_content.gd` | Renders attachments — images inline (lines 90-102), video placeholders (lines 104-108), audio players (lines 110-114), file links (lines 117-134), image download with LRU cache (lines 239-295), lightbox click handler (lines 311-316), GIF fallback (lines 377-397), size formatting (lines 330-335) |
| `scenes/messages/image_lightbox.gd` | Image lightbox overlay — shows texture scaled to viewport (line 10-22), click-to-close backdrop (line 24), Escape key (line 28) |
| `scenes/messages/image_lightbox.tscn` | Lightbox scene: dark overlay, centered image, close button |
| `scenes/messages/message_view.gd` | Reads `AppState.pending_attachments` and passes to `Client.send_message_to_channel()` (lines 386-390) |
| `scripts/autoload/app_state.gd` | `pending_attachments: Array` state variable (line 228), `message_sent` signal (line 6), `send_message()` (line 277), `image_lightbox_requested` signal (line 123) |
| `scripts/autoload/client.gd` | `send_message_to_channel()` with attachments parameter (line 447) |
| `scripts/autoload/client_mutations.gd` | `send_message_to_channel()` branches on attachments (lines 62-97): JSON-only vs multipart |
| `scripts/autoload/client_models.gd` | `message_to_dict()` converts `AccordAttachment` to UI dictionary with CDN URLs (lines 280-301) |
| `addons/accordkit/rest/accord_rest.gd` | `make_multipart_request()` sends raw byte body via `request_raw()` (lines 109-160), `_build_headers_for_content_type()` (lines 174-180) |
| `addons/accordkit/rest/endpoints/messages_api.gd` | `create_with_attachments()` builds MultipartForm and calls multipart endpoint (lines 49-64) |
| `addons/accordkit/rest/multipart_form.gd` | `MultipartForm` builder: `add_field()`, `add_json()`, `add_file()`, `build()`, `get_content_type()` |
| `addons/accordkit/models/attachment.gd` | `AccordAttachment` model: id, filename, description, content_type, size, url, width, height |
| `addons/accordkit/models/message.gd` | `AccordMessage.attachments` array (line 19), parsing (lines 65-69) |
| `addons/accordkit/utils/cdn.gd` | `AccordCDN.attachment()` builds CDN URLs (lines 50-57) |
| `scenes/main/main_window.gd` | Lightbox instantiation on `image_lightbox_requested` (lines 668-675) |

### Server-side key files (accordserver)

| File | Role |
|------|------|
| `src/routes/messages.rs` | `create_message` (line 102) for JSON-only, `create_message_multipart` (line 141) for file uploads, `message_row_to_json_with_attachments` (line 379) serializes attachments, `messages_to_json` (line 401) batch-loads attachments, `detect_image_dimensions` (line 413) for PNG/JPEG |
| `src/routes/mod.rs` | Routes `POST /channels/{id}/messages/upload` to `create_message_multipart` |
| `src/db/attachments.rs` | `insert_attachment()`, `get_attachments_for_message()`, `get_attachments_for_messages()` batch query |
| `src/storage.rs` | `save_attachment()` writes files to `storage_path/attachments/{channel_id}/{message_id}/{filename}`, `sanitize_filename()` prevents directory traversal, `MAX_ATTACHMENT_SIZE` = 25 MB |
| `src/models/attachment.rs` | `Attachment` struct: id, filename, description, content_type, size, url, width, height |
| `src/models/message.rs` | `CreateMessage` struct deserialized from `payload_json` |
| `migrations/002_expand_schema.sql` | `CREATE TABLE attachments` with foreign key to `messages(id) ON DELETE CASCADE` |

## Implementation Details

### Upload button and FileDialog (`composer.gd`)

The upload button is connected in `_ready()` (line 27): `upload_button.pressed.connect(_on_upload_button)`. The handler (line 266) lazily creates a `FileDialog` with `FILE_MODE_OPEN_FILES` for multi-file selection and `ACCESS_FILESYSTEM` for full system access. The `files_selected` signal is connected to `_on_files_selected()` (line 277).

### File reading and validation (`composer.gd`)

`_add_file_from_path()` (line 281) first checks `_can_add_attachment()` to enforce the 10-file limit, then opens the file with `FileAccess`, reads the entire content into a `PackedByteArray`, and validates against `MAX_FILE_SIZE` (25 MB, line 4). If the file is too large, an error message is shown in `error_label`. The file's MIME type is guessed from its extension via `_guess_content_type()` (line 332), which maps common extensions (png, jpg, gif, webp, svg, bmp, mp4, mp3, pdf, etc.) to MIME types.

Each pending file is stored as a dictionary: `{filename, content, content_type, size}`.

### Attachment count limit (`composer.gd`)

`_can_add_attachment()` (line 254) checks `_pending_files.size() >= MAX_ATTACHMENT_COUNT` (10, matching the server's `MAX_ATTACHMENTS`). If at the limit, it shows an error message and returns false. This is called from `_add_file_from_path()`, `_try_paste_image()`, `_check_large_paste_deferred()`, and `_on_window_files_dropped()`.

### Clipboard image paste (`composer.gd`)

In `_on_text_input()` (line 98), Ctrl+V is intercepted before the default paste handler. `_try_paste_image()` (line 177) calls `DisplayServer.clipboard_get_image()`. If an image is present, it is encoded to PNG via `image.save_png_to_buffer()`, given a timestamped filename, and appended to `_pending_files`. The event is consumed so the image data is not pasted as text. If no image is on the clipboard, normal text paste proceeds and `_check_large_paste_deferred()` is called.

### Large text paste detection (`composer.gd`)

`_check_large_paste_deferred()` (line 196) awaits one frame for the paste to land in the TextEdit, then checks if `text.length() >= LARGE_TEXT_THRESHOLD` (4096 bytes, line 6). If so, it shows a clickable prompt in `error_label` offering to convert the text to a `.txt` attachment. `_on_large_paste_clicked()` (line 219) converts the text to a UTF-8 `PackedByteArray`, appends it as `pasted_text.txt`, and clears the composer.

### Drag-and-drop (`composer.gd`)

`_ready_drop()` (line 239) connects to `get_window().files_dropped`, Godot's native window drop signal. `_on_window_files_dropped()` (line 242) checks visibility, guest/imposter mode, then iterates the dropped file paths through `_add_file_from_path()`, respecting the attachment count limit.

### Pending attachment preview (`composer.gd`)

`_update_attachment_bar()` (line 306) clears and rebuilds the `AttachmentBar` HBoxContainer. For each pending file, it creates a Label (filename + formatted size) and a flat "x" Button connected to `_remove_pending_file()` (line 327). The bar is hidden when no files are pending.

### Upload progress indicator (`composer.gd`)

`_show_upload_indicator()` (line 362) shows "Uploading..." in the attachment bar when files are being sent. `_hide_upload_indicator()` (line 373) removes it when `messages_updated` fires (connected in `_ready()` line 36), signaling the server has processed the upload and broadcast the message.

### Send flow with attachments

`_on_send()` (line 62) allows sending when either text or files are present (`text.is_empty() and _pending_files.is_empty()` guard). It copies `_pending_files` into `AppState.pending_attachments` (line 72), clears the local array, shows the upload indicator if files were present (line 77), then emits `message_sent`. This avoids changing the `message_sent` signal signature, which would require updating all listeners.

`message_view._on_message_sent()` (line 386) reads and clears `AppState.pending_attachments`, passing them to `Client.send_message_to_channel()`.

### Multipart request path (`AccordRest`)

`make_multipart_request()` (line 109) mirrors `make_request()` but uses `form.build()` for a `PackedByteArray` body and `form.get_content_type()` for the Content-Type header. It calls Godot's `HTTPRequest.request_raw()` (line 124) instead of `request()`. Rate limiting, retry logic, and response parsing are identical to the JSON path.

### MessagesApi multipart method

`create_with_attachments()` (line 49) builds a `MultipartForm` with `add_json("payload_json", data)` for message metadata and `add_file("files[N]", filename, content, content_type)` for each file. It calls `make_multipart_request("POST", "/channels/{id}/messages/upload", form)`.

### ClientMutations routing

`send_message_to_channel()` (line 62) now accepts an `attachments: Array = []` parameter. When empty, it calls the existing `client.messages.create(cid, data)` JSON path (line 80). When files are present, it calls `client.messages.create_with_attachments(cid, data, attachments)` (lines 82-84).

### Server: multipart handler (`messages.rs`)

`create_message_multipart()` (line 141) uses axum's `Multipart` extractor. It iterates fields:
- `payload_json` → deserialized into `CreateMessage`
- `files[N]` → extracted as `(filename, content_type, bytes)` tuples, limited to `MAX_ATTACHMENTS` (10)

After creating the message row, it saves each file via `storage::save_attachment()` and inserts an attachment record via `db::attachments::insert_attachment()`. For image content types, `detect_image_dimensions()` (line 413) reads PNG IHDR or JPEG SOF markers to extract width/height.

### Server: attachment storage (`storage.rs`)

`save_attachment()` validates against `MAX_ATTACHMENT_SIZE` (25 MB), creates the directory `storage_path/attachments/{channel_id}/{message_id}/`, sanitizes the filename (removing `/`, `\`, null bytes, leading dots), and writes the bytes. Returns the relative URL `/cdn/attachments/{channel_id}/{message_id}/{filename}`.

### Server: attachment database (`db/attachments.rs`)

`insert_attachment()` generates a snowflake ID and inserts into the `attachments` table. `get_attachments_for_message()` fetches all attachments for a single message. `get_attachments_for_messages()` batch-fetches attachments for multiple messages in one query (used by `messages_to_json` for list/search responses).

### Server: attachment serialization (`messages.rs`)

`message_row_to_json_with_attachments()` (line 379) replaces the old `message_row_to_json_with_reactions()`. It takes an `&[Attachment]` slice and serializes them alongside the message. `messages_to_json()` (line 401) batch-loads both reactions and attachments for all messages in a list response.

The old `message_row_to_json()` (line 375) still exists as a convenience wrapper that passes empty attachments and no reactions.

### Attachment rendering (`message_content.gd`)

In `setup()` (line 56), after rendering text, it iterates the `attachments` array (lines 82-134):

**Image attachments** (lines 90-102): If `content_type` starts with `"image/"` and URL is non-empty, creates a placeholder `Control` container sized to `min(width, 400)` x `min(height, 300)`, then calls `_load_image_attachment()` asynchronously.

**Video attachments** (lines 104-108): Creates a dark placeholder with a play triangle and filename; click opens in browser.

**Audio attachments** (lines 110-114): Creates an inline audio player with play/pause button, progress slider, time label, and filename. Supports OGG and MP3 decoding.

**`_load_image_attachment()`** (lines 239-295): Uses a static LRU cache (`IMAGE_CACHE_CAP = 100`). Downloads the image via HTTPRequest, tries PNG/JPG/WebP/BMP decoding in sequence (lines 267-273). For GIFs (which Godot can't decode natively), shows a "GIF - Click to view" fallback (line 277). Scales to fit within max dimensions preserving aspect ratio (lines 282-289), creates a TextureRect with `STRETCH_KEEP_ASPECT`.

**Image lightbox** (lines 311-316): Each image TextureRect has a click handler that emits `AppState.image_lightbox_requested`. `main_window.gd` (line 668) instantiates `image_lightbox.tscn`, which displays the image scaled to 85%x75% of the viewport with a dark backdrop. Click backdrop or press Escape to close.

**File links** (lines 117-134): Every attachment (including images) gets a RichTextLabel with BBCode: `[color=link][url=...]filename[/url][/color] (size)`. The `meta_clicked` signal is connected so clicking opens `OS.shell_open()`.

**File size formatting** (lines 330-335): Displays B, KB, or MB.

### CDN URL construction (`cdn.gd`)

`AccordCDN.attachment()` (line 50) builds `{cdn_url}/attachments/{channel_id}/{attachment_id}/{filename}`. Used by `ClientModels.message_to_dict()` (line 286) when the attachment URL doesn't already start with `http`.

### Existing upload patterns (emoji and soundboard)

The codebase has two working upload flows that use base64 data URIs rather than multipart:
- **Emoji upload** (`scenes/admin/emoji_management_dialog.gd`): Opens a FileDialog for PNG/GIF, reads the file, encodes as `data:image/png;base64,...`, sends via JSON to `POST /spaces/{id}/emojis`.
- **Soundboard upload** (`scenes/admin/soundboard_management_dialog.gd`): Same pattern for OGG/MP3/WAV, sends to `POST /spaces/{id}/soundboard`.

Message attachments use the multipart approach instead, since files can be much larger (25 MB vs 256 KB for emoji).

## Implementation Status

- [x] `AccordAttachment` model with full field set and serialization
- [x] `MultipartForm` builder for constructing multipart/form-data bodies
- [x] `AccordCDN.attachment()` for building CDN download URLs
- [x] `ClientModels.message_to_dict()` converts attachments with CDN URL resolution
- [x] Inline image rendering (PNG, JPG, WebP, BMP) with aspect-preserving scaling
- [x] GIF fallback ("GIF - Click to view" opens in browser)
- [x] Video attachment placeholder with play button
- [x] Audio attachment inline player (OGG/MP3)
- [x] Image attachment click-to-expand (lightbox)
- [x] File download links with filename and human-readable size
- [x] Clickable links open in system browser via `OS.shell_open()`
- [x] Upload button connected with click handler in composer
- [x] FileDialog for selecting one or more files to attach
- [x] Pending attachment preview bar in composer (filename, size, remove button)
- [x] Client-side file size validation (25 MB max)
- [x] MIME type detection from file extension
- [x] Multipart request path in `AccordRest` (`make_multipart_request`)
- [x] `MessagesApi.create_with_attachments()` for file uploads
- [x] `ClientMutations.send_message_to_channel()` routes to multipart when attachments present
- [x] `AppState.pending_attachments` carries files from composer to message_view without changing signal
- [x] Clipboard image paste (Ctrl+V with `DisplayServer.clipboard_get_image()`)
- [x] Large text paste detection and conversion to `.txt` attachment (4 KB threshold)
- [x] Drag-and-drop file upload onto application window
- [x] Upload progress indicator ("Uploading..." in attachment bar)
- [x] Attachment count limit in composer UI (max 10, matching server)
- [x] Static LRU image cache for attachment rendering (cap 100)
- [x] Server: `POST /channels/{id}/messages/upload` multipart endpoint
- [x] Server: `db/attachments.rs` with insert and batch query
- [x] Server: `storage::save_attachment()` with filename sanitization and size limit
- [x] Server: `messages_to_json()` batch-loads attachments for all list/search responses
- [x] Server: `create_message_multipart()` saves files and inserts attachment rows
- [x] Server: `detect_image_dimensions()` for PNG and JPEG
- [x] Server: attachment file cleanup on message delete
- [ ] SVG image rendering (Godot `Image` class has no SVG buffer loader)
- [ ] Server: image dimension detection for WebP/GIF formats

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| SVG images render as file links only | Low | Godot's `Image` class cannot load SVG from buffer; would need a custom SVG rasterizer or open in browser like GIFs |
| Server: WebP/GIF dimension detection | Low | `detect_image_dimensions()` only handles PNG and JPEG; WebP and GIF images lack `width`/`height` in attachment data, so client uses fallback 400x300 sizing |
| No per-file upload progress bar | Low | `HTTPRequest` doesn't support chunked upload progress callbacks; the "Uploading..." indicator is binary (shown/hidden), not a percentage bar |
| Clipboard paste only works with Ctrl+V | Low | macOS users expect Cmd+V; Godot maps Cmd to `meta_pressed` not `ctrl_pressed` on macOS — needs platform check |

## Tasks

### FILES-1: SVG image rendering
- **Status:** open
- **Impact:** 1
- **Effort:** 3
- **Tags:** general
- **Notes:** Godot `Image` class has no `load_svg_from_buffer()`. Would require either a GDExtension SVG rasterizer or opening SVGs in browser like GIFs. Low priority since SVG attachments are uncommon in chat.

### FILES-2: Server WebP/GIF dimension detection
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** general
- **Notes:** `detect_image_dimensions()` in `messages.rs` (line 413) only handles PNG IHDR and JPEG SOF markers. WebP RIFF/VP8 and GIF logical screen descriptor parsing needed. Without dimensions, client falls back to 400x300 placeholder sizing.
