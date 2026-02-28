# File Sharing

Last touched: 2026-02-19

## Overview

File sharing covers uploading files as message attachments, rendering received attachments (images inline, other files as download links), and the full server-side storage pipeline. The upload path is now wired end-to-end: the composer's upload button opens a file picker, selected files appear as pending attachments, and on send the client constructs a multipart/form-data request that the server stores to disk and persists in the `attachments` database table. Attachment data is returned in message JSON responses and rendered by the client. Clipboard image paste and drag-and-drop are not yet implemented.

## User Steps

### Sending a file attachment
1. User clicks the **Upload** button (paperclip icon) in the composer.
2. A native `FileDialog` opens, allowing the user to choose one or more files.
3. Selected files appear in the **AttachmentBar** above the composer input, showing filename and size with a remove button for each.
4. User optionally adds message text.
5. User clicks Send or presses Enter.
6. The composer transfers pending files to `AppState.pending_attachments` and emits `message_sent`.
7. `message_view` reads `AppState.pending_attachments`, passes them to `Client.send_message_to_channel()`.
8. `ClientMutations` calls `MessagesApi.create_with_attachments()`, which builds a `MultipartForm` with `payload_json` (message metadata) and `files[N]` parts.
9. `AccordRest.make_multipart_request()` sends the raw bytes via `HTTPRequest.request_raw()` to `POST /channels/{id}/messages/upload`.
10. The server handler (`create_message_multipart`) saves files to `storage_path/attachments/{channel_id}/{message_id}/{filename}`, inserts rows into the `attachments` DB table, and broadcasts the message via gateway with the attachment data included.
11. All clients render the attachment — images inline, other files as clickable download links.

### Receiving attachments
1. A message arrives via the gateway with an `attachments` array.
2. `ClientModels.message_to_dict()` converts each `AccordAttachment` to a UI dictionary with CDN URLs (lines 280-301).
3. `message_content.gd` iterates attachments (lines 38-74):
   - **Images** (`content_type` starts with `image/`): downloaded via HTTPRequest, displayed inline as a scaled TextureRect (max 400x300).
   - **All files**: rendered as a clickable BBCode link showing filename and human-readable size.
4. Clicking a file link opens it in the system browser via `OS.shell_open()`.

### Sending text-only messages (unchanged)
When no files are attached, `ClientMutations` falls back to the existing `MessagesApi.create()` JSON path (line 80), so the upload path is additive and does not affect existing messaging.

## Signal Flow

```
[Upload button clicked]
        |
        v
  composer._on_upload_button()         (line 101)
        |
        v
  FileDialog.files_selected            (native signal)
        |
        v
  composer._on_files_selected()        (line 111)
        |
        v
  _add_file_from_path() × N            (line 115)
  — reads file via FileAccess
  — validates size (25 MB max)
  — detects MIME type from extension
  — appends to _pending_files array
        |
        v
  _update_attachment_bar()             (line 138)
  — shows filenames + sizes + remove buttons in AttachmentBar
        |
        v
  [User clicks Send / presses Enter]
        |
        v
  composer._on_send()                  (line 42)
  — copies _pending_files to AppState.pending_attachments
  — clears _pending_files
  — emits AppState.message_sent(text)
        |
        v
  message_view._on_message_sent()      (line 265)
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
        |
        v
  message_content.setup() → renders attachments (lines 38-74)
        |
        ├── Image? → _load_image_attachment() → HTTPRequest → TextureRect
        └── File?  → RichTextLabel with [url] BBCode link
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/composer/composer.gd` | Upload button handler (line 101), FileDialog creation (line 102-108), file reading and MIME detection (lines 115-136), pending attachment bar (lines 138-162), send with attachments (lines 42-53) |
| `scenes/messages/composer/composer.tscn` | Composer scene with UploadButton (line 58), AttachmentBar (line 54) |
| `scenes/messages/message_content.gd` | Renders attachments — images inline (lines 46-57), file links (lines 59-74), image download (lines 109-149), size formatting (lines 151-156) |
| `scenes/messages/message_view.gd` | Reads `AppState.pending_attachments` and passes to `Client.send_message_to_channel()` (lines 265-269) |
| `scripts/autoload/app_state.gd` | `pending_attachments: Array` state variable (line 110), `message_sent` signal (line 6), `send_message()` (line 126) |
| `scripts/autoload/client.gd` | `send_message_to_channel()` with attachments parameter (line 447) |
| `scripts/autoload/client_mutations.gd` | `send_message_to_channel()` branches on attachments (lines 62-97): JSON-only vs multipart |
| `scripts/autoload/client_models.gd` | `message_to_dict()` converts `AccordAttachment` to UI dictionary with CDN URLs (lines 280-301) |
| `addons/accordkit/rest/accord_rest.gd` | `make_multipart_request()` sends raw byte body via `request_raw()` (lines 109-160), `_build_headers_for_content_type()` (lines 174-180) |
| `addons/accordkit/rest/endpoints/messages_api.gd` | `create_with_attachments()` builds MultipartForm and calls multipart endpoint (lines 49-64) |
| `addons/accordkit/rest/multipart_form.gd` | `MultipartForm` builder: `add_field()`, `add_json()`, `add_file()`, `build()`, `get_content_type()` |
| `addons/accordkit/models/attachment.gd` | `AccordAttachment` model: id, filename, description, content_type, size, url, width, height |
| `addons/accordkit/models/message.gd` | `AccordMessage.attachments` array (line 19), parsing (lines 65-69) |
| `addons/accordkit/utils/cdn.gd` | `AccordCDN.attachment()` builds CDN URLs (lines 50-57) |

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

The upload button is connected in `_ready()` (line 24): `upload_button.pressed.connect(_on_upload_button)`. The handler (line 101) lazily creates a `FileDialog` with `FILE_MODE_OPEN_FILES` for multi-file selection and `ACCESS_FILESYSTEM` for full system access. The `files_selected` signal is connected to `_on_files_selected()` (line 111).

### File reading and validation (`composer.gd`)

`_add_file_from_path()` (line 115) opens the file with `FileAccess`, reads the entire content into a `PackedByteArray`, and validates against `MAX_FILE_SIZE` (25 MB, line 4). If the file is too large, an error message is shown in `error_label`. The file's MIME type is guessed from its extension via `_guess_content_type()` (line 164), which maps common extensions (png, jpg, gif, webp, mp4, mp3, pdf, etc.) to MIME types.

Each pending file is stored as a dictionary: `{filename, content, content_type, size}`.

### Pending attachment preview (`composer.gd`)

`_update_attachment_bar()` (line 138) clears and rebuilds the `AttachmentBar` HBoxContainer. For each pending file, it creates a Label (filename + formatted size) and a flat "x" Button connected to `_remove_pending_file()` (line 159). The bar is hidden when no files are pending.

### Send flow with attachments

`_on_send()` (line 42) now allows sending when either text or files are present (`text.is_empty() and _pending_files.is_empty()` guard). It copies `_pending_files` into `AppState.pending_attachments` (line 47), clears the local array, then emits `message_sent`. This avoids changing the `message_sent` signal signature, which would require updating all listeners.

`message_view._on_message_sent()` (line 265) reads and clears `AppState.pending_attachments`, passing them to `Client.send_message_to_channel()`.

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

In `setup()` (line 25), after rendering text, it iterates the `attachments` array (lines 38-74):

**Image attachments** (lines 46-57): If `content_type` starts with `"image/"` and URL is non-empty, creates a placeholder `Control` container sized to `min(width, 400)` x `min(height, 300)`, then calls `_load_image_attachment()` asynchronously.

**`_load_image_attachment()`** (lines 109-149): Creates an HTTPRequest child, downloads the image, tries PNG/JPG/WebP decoding in sequence (lines 127-131), scales to fit within max dimensions preserving aspect ratio (lines 135-142), creates a TextureRect with `STRETCH_KEEP_ASPECT`.

**File links** (lines 59-74): Every attachment (including images) gets a RichTextLabel with BBCode: `[color=#00aaff][url=...]filename[/url][/color] (size)`. The `meta_clicked` signal is connected so clicking opens `OS.shell_open()` (line 107).

**File size formatting** (lines 151-156): Displays B, KB, or MB.

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
- [x] Inline image rendering (PNG, JPG, WebP) with aspect-preserving scaling
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
- [x] Server: `POST /channels/{id}/messages/upload` multipart endpoint
- [x] Server: `db/attachments.rs` with insert and batch query
- [x] Server: `storage::save_attachment()` with filename sanitization and size limit
- [x] Server: `messages_to_json()` batch-loads attachments for all list/search responses
- [x] Server: `create_message_multipart()` saves files and inserts attachment rows
- [x] Server: `detect_image_dimensions()` for PNG and JPEG
- [x] Server: attachment file cleanup on message delete
- [ ] Clipboard image paste (Ctrl+V with `DisplayServer.clipboard_get_image()`)
- [ ] Large text paste detection and conversion to `.txt` attachment
- [ ] Drag-and-drop file upload onto composer or message area
- [ ] Upload progress indicator
- [ ] Multiple file attachment count limit in composer UI (server limits to 10)
- [ ] GIF/SVG/BMP image format support in attachment rendering
- [ ] Image attachment click-to-expand (lightbox)
- [ ] Server: image dimension detection for WebP/GIF formats

## Tasks

### FILES-1: No clipboard image paste
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** general
- **Notes:** `composer.gd` `_on_text_input()` (line 55) only handles Enter/Up keys; no Ctrl+V interception for images via `DisplayServer.clipboard_get_image()`

### FILES-2: No large-text-to-file conversion
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** general
- **Notes:** No threshold check on pasted text length; long pastes go directly into the message content field with no option to send as a `.txt` attachment

### FILES-3: No drag-and-drop onto composer
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** general
- **Notes:** Drag-and-drop is only used for channel/category reordering; no file drop target in the composer or message view

### FILES-4: No upload progress indicator
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** ci
- **Notes:** `MultipartForm.build()` returns the complete body at once; no chunked upload or progress callback — large files will appear to hang

### FILES-5: No attachment count limit in composer UI
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** ui
- **Notes:** The server enforces a max of 10 attachments per message (`MAX_ATTACHMENTS` in `messages.rs` line 18), but the composer has no visual limit — the user could queue more than 10 files and only get an error on send

### FILES-6: No image lightbox
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** Clicking an inline image attachment opens the raw URL in the browser (`OS.shell_open`) rather than showing a zoomed view in-app

### FILES-7: Limited image format support
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** `_load_image_attachment()` (lines 127-131) only tries PNG, JPG, WebP; GIF, SVG, and BMP are not handled

### FILES-8: Server image dimension detection limited
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** general
- **Notes:** `detect_image_dimensions()` only handles PNG and JPEG; WebP and GIF dimensions are not detected, so those image types will lack `width`/`height` in attachment data
