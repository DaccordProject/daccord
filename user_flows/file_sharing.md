# File Sharing

*Last touched: 2026-02-18 22:15*

## Overview

File sharing covers uploading files as message attachments, pasting images or large text blocks from the clipboard, drag-and-drop file uploads, and rendering received attachments (images inline, other files as download links). The server-side infrastructure (AccordKit models, multipart form builder, CDN URL helper) is largely in place, but the client-side upload path from the composer is not wired up — the upload button exists in the UI but has no click handler.

## User Steps

### Sending a file attachment (intended flow)
1. User clicks the **Upload** button (paperclip icon) in the composer.
2. A file picker dialog opens, allowing the user to choose one or more files.
3. Selected files appear as pending attachments in the composer (thumbnail for images, filename + size for others).
4. User optionally adds message text.
5. User clicks Send or presses Enter.
6. The client encodes files into a multipart/form-data request and sends to `POST /channels/{id}/messages`.
7. The server processes the upload, stores files on the CDN, and broadcasts the message via the gateway.
8. All clients render the attachment — images inline, other files as clickable download links.

### Pasting an image from clipboard (intended flow)
1. User copies an image (screenshot, browser image, etc.) to the system clipboard.
2. User focuses the composer TextEdit and presses Ctrl+V.
3. The client reads the clipboard image via `DisplayServer.clipboard_get_image()`.
4. A preview of the pasted image appears in the composer as a pending attachment.
5. User sends the message; the image is uploaded as an attachment.

### Pasting large text (intended flow)
1. User copies a large block of text (e.g., a log file, code snippet).
2. User pastes into the composer with Ctrl+V.
3. If the text exceeds a threshold (e.g., 2000 characters), the client offers to convert it into a `.txt` file attachment instead of sending as message content.
4. User confirms; the text is wrapped into a file and sent as an attachment.

### Receiving attachments (implemented)
1. A message arrives via the gateway with an `attachments` array.
2. `ClientModels.message_to_dict()` converts each `AccordAttachment` to a UI dictionary with CDN URLs.
3. `message_content.gd` iterates attachments:
   - **Images** (`content_type` starts with `image/`): downloaded via HTTPRequest, displayed inline as a scaled TextureRect (max 400x300).
   - **All files**: rendered as a clickable BBCode link showing filename and human-readable size.
4. Clicking a file link opens it in the system browser via `OS.shell_open()`.

## Signal Flow

```
[Upload button clicked]              (NOT CONNECTED — no handler)
        |
        v
  FileDialog.file_selected
        |
        v
  Read file bytes via FileAccess
        |
        v
  MultipartForm.add_file() + add_json("payload_json", {...})
        |
        v
  AccordRest.make_request("POST", "/channels/{id}/messages", ...)
        |                                    ^
        |                                    | (needs multipart override —
        v                                    |  currently JSON-only)
  RestResult → success/failure
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
  message_content.setup() → renders attachments (lines 35-71)
        |
        ├── Image? → _load_image_attachment() → HTTPRequest → TextureRect
        └── File?  → RichTextLabel with [url] BBCode link
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/composer/composer.gd` | Composer with upload button (line 9), no click handler connected |
| `scenes/messages/composer/composer.tscn` | Composer scene; UploadButton node (line 58) with tooltip "Upload" |
| `scenes/messages/message_content.gd` | Renders attachments — images inline (lines 44-54), file links (lines 56-71), image download (lines 106-146), size formatting (lines 148-153) |
| `addons/accordkit/models/attachment.gd` | `AccordAttachment` model: id, filename, description, content_type, size, url, width, height |
| `addons/accordkit/models/message.gd` | `AccordMessage.attachments` array (line 19), parsing (lines 65-69), serialization (lines 131-135) |
| `addons/accordkit/rest/multipart_form.gd` | `MultipartForm` builder: `add_field()`, `add_json()`, `add_file()`, `build()` |
| `addons/accordkit/rest/accord_rest.gd` | `make_request()` — currently JSON-only (line 56, line 109), no multipart path |
| `addons/accordkit/rest/endpoints/messages_api.gd` | `create()` calls `make_request("POST", ...)` with JSON body (line 39) |
| `addons/accordkit/utils/cdn.gd` | `AccordCDN.attachment()` builds CDN URLs (lines 50-57) |
| `scripts/autoload/client_models.gd` | `message_to_dict()` converts `AccordAttachment` to UI dictionary with CDN URLs (lines 274-295) |
| `scripts/autoload/client_mutations.gd` | `send_message_to_channel()` sends JSON payload only (lines 62-90) |

## Implementation Details

### AccordAttachment model (`addons/accordkit/models/attachment.gd`)

The data model is complete. Fields: `id`, `filename`, `description`, `content_type`, `size`, `url`, `width`, `height`. Parsing via `from_dict()` (line 16) and serialization via `to_dict()` (line 29) handle all fields including nullable `description`, `content_type`, `width`, `height`.

### MultipartForm builder (`addons/accordkit/rest/multipart_form.gd`)

Fully implemented and tested. Generates a random boundary in `_init()` (line 13). Three part types:
- `add_field(name, value)` — plain text (line 17)
- `add_json(name, data)` — JSON with Content-Type header (line 27)
- `add_file(name, filename, content, content_type)` — binary file with filename (line 41)
- `build()` assembles parts with closing boundary (line 62)
- `get_content_type()` returns the full `multipart/form-data; boundary=...` header (line 57)

Unit tests exist at `tests/accordkit/unit/test_multipart_form.gd`.

### AccordRest — no multipart path (`addons/accordkit/rest/accord_rest.gd`)

`make_request()` (line 46) always serializes the body as JSON (line 56) and uses a hardcoded `Content-Type: application/json` header (line 109). There is no code path to accept a `MultipartForm` body, set the multipart content-type header, or send raw `PackedByteArray` bodies. This is the key infrastructure gap — `MultipartForm` exists but nothing in the REST layer uses it.

### Messages API (`addons/accordkit/rest/endpoints/messages_api.gd`)

`create()` (line 38) passes a Dictionary to `make_request("POST", ...)` which JSON-encodes it. To support file uploads, this would need an overload or alternative method that builds a `MultipartForm` with `payload_json` (the message metadata) plus one or more file parts, then calls a multipart-aware request method.

### Composer (`scenes/messages/composer/composer.gd`)

The upload button is declared at line 9 (`@onready var upload_button: Button`) and referenced in the scene at line 58 of the `.tscn` file (44x44 flat button with "Upload" tooltip). It is enabled/disabled with the connection state (line 152). However, **no `.pressed.connect()` call exists** in `_ready()` (lines 18-29) — the button does nothing when clicked.

No clipboard paste handling exists. The `_on_text_input()` handler (line 46) only checks for Enter and Up arrow keys. There is no interception of Ctrl+V for image paste via `DisplayServer.clipboard_get_image()`.

### Attachment rendering (`scenes/messages/message_content.gd`)

This is the most complete part of the flow. In `setup()` (line 22), after rendering text content, it iterates the `attachments` array (lines 35-71):

**Image attachments** (lines 44-54): If `content_type` starts with `"image/"` and URL is non-empty, creates a placeholder `Control` container sized to `min(width, 400)` x `min(height, 300)`, then calls `_load_image_attachment()` asynchronously.

**`_load_image_attachment()`** (lines 106-146): Creates an HTTPRequest child, downloads the image, tries PNG/JPG/WebP decoding in sequence (lines 124-128), scales to fit within max dimensions preserving aspect ratio (lines 132-139), creates a TextureRect with `STRETCH_KEEP_ASPECT`.

**File links** (lines 56-71): Every attachment (including images) gets a RichTextLabel with BBCode: `[color=#00aaff][url=...]filename[/url][/color] (size)`. The `meta_clicked` signal is connected so clicking opens `OS.shell_open()` (line 104).

**File size formatting** (lines 148-153): Displays B, KB, or MB.

### CDN URL construction (`addons/accordkit/utils/cdn.gd`)

`AccordCDN.attachment()` (line 50) builds `{cdn_url}/attachments/{channel_id}/{attachment_id}/{filename}`. Used by `ClientModels.message_to_dict()` (line 280) when the attachment URL doesn't already start with `http`.

### ClientModels attachment conversion (`scripts/autoload/client_models.gd`)

`message_to_dict()` converts each `AccordAttachment` to a dictionary (lines 274-295) with keys: `id`, `filename`, `size`, `url`, and conditionally `content_type`, `width`, `height`. The URL is resolved through `AccordCDN.attachment()` if it's a relative path.

### Existing upload patterns (emoji and soundboard)

The codebase has two working upload flows that use base64 data URIs rather than multipart:
- **Emoji upload** (`scenes/admin/emoji_management_dialog.gd`): Opens a FileDialog for PNG/GIF, reads the file, encodes as `data:image/png;base64,...`, sends via JSON to `POST /spaces/{id}/emojis`.
- **Soundboard upload** (`scenes/admin/soundboard_management_dialog.gd`): Same pattern for OGG/MP3/WAV, sends to `POST /spaces/{id}/soundboard`.

These demonstrate a working pattern, but message attachments would benefit from the multipart approach (already built in `MultipartForm`) since files can be much larger and the server likely expects multipart for message attachments.

## Implementation Status

- [x] `AccordAttachment` model with full field set and serialization
- [x] `MultipartForm` builder for constructing multipart/form-data bodies
- [x] `AccordCDN.attachment()` for building CDN download URLs
- [x] `ClientModels.message_to_dict()` converts attachments with CDN URL resolution
- [x] Inline image rendering (PNG, JPG, WebP) with aspect-preserving scaling
- [x] File download links with filename and human-readable size
- [x] Clickable links open in system browser via `OS.shell_open()`
- [x] Upload button exists in composer UI with tooltip and enable/disable logic
- [ ] Upload button click handler (no `.pressed.connect()` in composer)
- [ ] FileDialog for selecting files to attach
- [ ] Pending attachment preview in composer before sending
- [ ] Multipart request path in `AccordRest` (currently JSON-only)
- [ ] `MessagesApi.create()` overload for file attachments
- [ ] `ClientMutations.send_message_to_channel()` support for attachments
- [ ] Clipboard image paste (Ctrl+V with `DisplayServer.clipboard_get_image()`)
- [ ] Large text paste detection and conversion to `.txt` attachment
- [ ] Drag-and-drop file upload onto composer or message area
- [ ] Upload progress indicator
- [ ] File size limit validation (client-side)
- [ ] Multiple file attachment support in a single message
- [ ] GIF/SVG/BMP image format support in attachment rendering
- [ ] Image attachment click-to-expand (lightbox)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Upload button has no click handler | High | `composer.gd` line 9 declares the button, `_ready()` (lines 18-29) never connects `.pressed` — the button is completely non-functional |
| `AccordRest.make_request()` is JSON-only | High | `accord_rest.gd` line 56 always `JSON.stringify(body)`, line 109 hardcodes `Content-Type: application/json` — no path for `MultipartForm` or raw byte bodies |
| `send_message_to_channel()` has no attachment parameter | High | `client_mutations.gd` line 74 builds `{"content": content}` only — no way to pass file data from the composer |
| No clipboard paste handling in composer | Medium | `composer.gd` `_on_text_input()` (line 46) only handles Enter/Up keys; no Ctrl+V interception for images via `DisplayServer.clipboard_get_image()` |
| No large-text-to-file conversion | Medium | No threshold check on pasted text length; long pastes go directly into the message content field with no option to send as a `.txt` attachment |
| No drag-and-drop onto composer | Medium | Drag-and-drop is only used for channel/category reordering (`category_item.gd` lines 176-244, `channel_item.gd` lines 148-213); no file drop target in the composer or message view |
| No upload progress indicator | Medium | `MultipartForm.build()` returns the complete body at once; no chunked upload or progress callback — large files will appear to hang |
| No pending attachment preview | Low | Composer has no UI area to show thumbnails/filenames of files queued for upload before sending |
| No client-side file size validation | Low | No maximum file size check before attempting upload; server rejection would be the only guard |
| No image lightbox | Low | Clicking an inline image attachment opens the raw URL in the browser (`OS.shell_open`) rather than showing a zoomed view in-app |
| Limited image format support | Low | `_load_image_attachment()` (lines 124-128) only tries PNG, JPG, WebP; GIF, SVG, and BMP are not handled |
