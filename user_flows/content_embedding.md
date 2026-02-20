# Content Embedding

Last touched: 2026-02-19

## Overview

Content embedding covers how daccord renders rich previews for images, videos, audio, and links within messages. Image attachments uploaded through the server are displayed inline with aspect-ratio scaling, a loading placeholder, error state, and a clickable lightbox for full-size viewing. Server-generated embeds render below message text as cards with colored borders supporting title, description, footer, author, fields, images, and thumbnails. URL unfurling is handled server-side via OpenGraph metadata fetching. Video attachments show a play-button placeholder that opens in the browser. Audio attachments render an inline player with play/pause and progress. GIF attachments that Godot can't decode show a "Click to view" fallback.

## User Steps

### Viewing an image attachment
1. A message arrives containing an image attachment (PNG, JPG, or WebP)
2. A dark "Loading..." placeholder appears at the expected image dimensions
3. The image is fetched from the server CDN via HTTP
4. The image renders inline below the message text, scaled to fit within 400x300 pixels
5. A clickable filename link with file size appears below the image
6. If loading fails, a "Failed to load image" error state replaces the placeholder
7. Clicking the image opens a full-screen lightbox overlay; press Escape or click the backdrop to close

### Viewing a video attachment
1. A message arrives containing a video attachment (video/* content_type)
2. A dark 16:9 placeholder appears with a centered play triangle and filename
3. Clicking the placeholder opens the video URL in the system browser

### Listening to an audio attachment
1. A message arrives containing an audio attachment (audio/* content_type)
2. An inline audio player appears with play/pause button, progress slider, and filename
3. Clicking play downloads the audio, then begins playback with Godot's AudioStreamPlayer
4. Clicking again pauses; the slider shows progress and the time label shows elapsed time

### Viewing a GIF attachment
1. A message arrives containing a GIF attachment (image/gif)
2. Since Godot can't decode animated GIFs, a "GIF - Click to view" fallback appears
3. Clicking opens the GIF URL in the system browser

### Viewing an embed card
1. A message arrives containing one or more embed objects (generated server-side)
2. Each embed renders as a card with a colored left border
3. If an author is present, an author row shows the icon (loaded via HTTP) and name (clickable if URL provided)
4. If a title is present, it renders as bold text (clickable if embed URL provided)
5. Description renders with markdown-to-BBCode conversion
6. Fields render as name/value pairs; consecutive inline fields group into rows (max 3 per row)
7. If an image URL is present, it loads inline below the fields (max 400x300)
8. If a thumbnail URL is present, it loads as an 80x80 image to the right of the main content
9. Footer text renders at the bottom in small gray text
10. Multiple embeds stack vertically below the message text

### URL unfurling (link previews)
1. A user sends a message containing one or more URLs
2. The server detects URLs in the message content (max 5 per message)
3. For each URL, the server fetches the page and parses OpenGraph meta tags (og:title, og:description, og:image, og:site_name)
4. The server generates embed objects from the metadata and updates the message via a MESSAGE_UPDATE gateway event
5. The client receives the update and renders the generated embeds as link preview cards

### Clicking a link
1. The user clicks a `[text](url)` markdown link rendered in the message
2. The URL opens in the system default browser via `OS.shell_open()`

## Signal Flow

```
Server sends MESSAGE_CREATE with embeds/attachments
    │
    ▼
Client._on_gateway_message_create()
    │
    ▼
ClientModels.message_to_dict()
    ├── Converts AccordEmbed array → embeds_arr (title, description, color, footer, image,
    │   thumbnail, author, fields, url, type)
    └── Converts AccordAttachment array → attachments_arr (id, filename, size, url,
        content_type, width, height)
    │
    ▼
AppState.messages_updated emitted
    │
    ▼
message_view rebuilds message list
    │
    ▼
message_content.setup(data)
    ├── Image attachments: creates container → _add_loading_placeholder() →
    │   _load_image_attachment() → _apply_image_texture() with lightbox click
    ├── Video attachments: _create_video_placeholder() with click-to-open
    ├── Audio attachments: _create_audio_player() with play/pause/progress
    ├── GIF fallback: _show_gif_fallback() with click-to-open
    ├── All attachments: creates RichTextLabel link (filename + size)
    └── Embeds: calls embed.setup() for each embed dict

embed.setup(data)
    ├── Author: shows AuthorRow with icon + clickable name
    ├── Title: RichTextLabel with optional [url] BBCode wrapping
    ├── Description: markdown_to_bbcode conversion
    ├── Fields: VBoxContainer with inline field grouping (HBoxContainer rows)
    ├── Image: loads via _load_remote_image() (max 400x300)
    ├── Thumbnail: loads via _load_remote_image() (80x80, right side)
    ├── Footer: small gray Label
    └── Border color: StyleBoxFlat border_color override

URL Unfurling (server-side):
    User sends message with URLs
        │
        ▼
    Server create_message() → spawns tokio::spawn(unfurl task)
        │
        ▼
    unfurl::extract_urls() finds URLs (max 5)
        │
        ▼
    unfurl::unfurl_url() fetches each URL, parses OpenGraph
        │
        ▼
    Server PATCH message with generated embeds
        │
        ▼
    Gateway broadcasts message.update event
        │
        ▼
    Client receives MESSAGE_UPDATE → re-renders embeds
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/message_content.gd` | Attachment rendering (image/video/audio/GIF + loading/error states), lightbox click, embed orchestration |
| `scenes/messages/message_content.tscn` | Scene layout: TextContent → Embed → ReactionBar |
| `scenes/messages/embed.gd` | Full embed card rendering: author, title, description, fields, image, thumbnail, footer, border color, type handling |
| `scenes/messages/embed.tscn` | PanelContainer with HBox(VBox + Thumbnail) layout, all embed nodes |
| `scenes/messages/image_lightbox.gd` | Full-screen image viewer overlay |
| `scenes/messages/image_lightbox.tscn` | Lightbox scene: dark backdrop + centered image + close button |
| `scripts/autoload/client_models.gd` | Converts `AccordEmbed` and `AccordAttachment` models to UI dictionaries (including author, fields, url, type) |
| `scripts/autoload/app_state.gd` | Signal bus: `image_lightbox_requested` signal for lightbox |
| `scenes/main/main_window.gd` | Connects lightbox signal, instantiates lightbox overlay |
| `scripts/autoload/client_markdown.gd` | Markdown-to-BBCode conversion (links, but no URL unfurling) |
| `addons/accordkit/models/embed.gd` | `AccordEmbed` model: title, type, description, url, color, footer, image, thumbnail, author, fields |
| `addons/accordkit/models/attachment.gd` | `AccordAttachment` model: id, filename, content_type, size, url, width, height |
| `addons/accordkit/utils/cdn.gd` | `AccordCDN.attachment()` builds CDN URLs for file downloads |
| `addons/accordkit/rest/endpoints/messages_api.gd` | `create_with_attachments()` for multipart file upload |
| `../accordserver/src/unfurl.rs` | URL unfurling: extract_urls(), unfurl_url(), OpenGraph parsing |
| `../accordserver/src/routes/messages.rs` | create_message() spawns unfurl task for URL detection |

## Implementation Details

### Image Attachment Rendering (`message_content.gd`)

When `setup()` receives a message dictionary, it iterates the `attachments` array. For each attachment whose `content_type` starts with `"image/"`:

1. Reads `width` and `height` from attachment metadata, defaulting to 400x300
2. Caps dimensions to a hardcoded maximum of 400x300 pixels
3. Creates a `Control` container with `custom_minimum_size` set to the capped dimensions
4. Adds a dark `ColorRect` loading placeholder with "Loading..." label via `_add_loading_placeholder()`
5. Calls `_load_image_attachment()` asynchronously to fetch and display the image

On successful load, `_apply_image_texture()` removes the placeholder, creates a `TextureRect`, and connects a click handler that emits `AppState.image_lightbox_requested`. On failure, `_show_image_error()` replaces the placeholder with a red "Failed to load image" indicator.

### Video Attachment Handling (`message_content.gd`)

For `video/*` content types, `_create_video_placeholder()` creates a dark 400x225 container with a centered play triangle and filename. Clicking opens the URL in the browser via `OS.shell_open()`.

### Audio Attachment Handling (`message_content.gd`)

For `audio/*` content types, `_create_audio_player()` creates an inline `HBoxContainer` with play/pause button, progress slider, time label, and filename. Audio is downloaded on first play, loaded as OGG or MP3, and played via `AudioStreamPlayer`.

### GIF Fallback (`message_content.gd`)

When `_load_image_attachment()` fails to decode an image and the content_type is `image/gif`, `_show_gif_fallback()` shows a dark container with "GIF - Click to view" text. Clicking opens the URL in the browser.

### Image Lightbox (`image_lightbox.gd`)

`AppState.image_lightbox_requested` signal is emitted when clicking an inline image. `main_window.gd` connects this signal and instantiates `image_lightbox.tscn` -- a full-screen dark overlay with the image scaled to fit 85% viewport width / 75% viewport height. Closes on backdrop click or Escape key.

### Image Loading (`message_content.gd`)

`_load_image_attachment()` fetches the image via an `HTTPRequest` node:

1. Checks the static LRU cache first (shared between message_content and embed)
2. Creates an `HTTPRequest`, sends a GET to the image URL
3. Awaits the response; on failure shows error state via `_show_image_error()`
4. Tries loading the response body as PNG, then JPG, then WebP, then BMP
5. If all fail and content_type is `image/gif`, shows GIF fallback
6. Scales the image to fit within max dimensions while preserving aspect ratio
7. Creates an `ImageTexture`, caches it, and calls `_apply_image_texture()`

### Embed Card Rendering (`embed.gd`)

The `setup()` method receives an embed dictionary and renders:

1. **Author row**: If `data["author"]` exists with a non-empty name, shows icon (loaded via HTTP) and name (as clickable BBCode link if URL provided)
2. **Title**: RichTextLabel with `[url]` BBCode wrapping if `data["url"]` exists
3. **Description**: Rendered via `ClientModels.markdown_to_bbcode()`
4. **Fields**: `_render_fields()` groups consecutive inline fields into HBoxContainer rows (max 3 per row). Each field has a bold name Label and a RichTextLabel value.
5. **Image**: Loaded via `_load_remote_image()` (max 400x300). For `"image"` embed type, hides title/description/footer.
6. **Thumbnail**: 80x80 image to the right of the main content column
7. **Footer**: Small gray Label
8. **Border color**: Duplicates the panel StyleBoxFlat and sets border_color
9. **Video type**: Shows thumbnail with play button overlay; click opens embed URL

The embed scene layout is `PanelContainer > HBox(VBox + Thumbnail)`:
- VBox contains: AuthorRow, Title, Description, FieldsContainer, Image, Footer
- Thumbnail sits to the right of the VBox

### Model Conversion (`client_models.gd`)

`message_to_dict()` converts AccordKit models to UI dictionaries:

**Embeds**: Extracts `title`, `description`, `color` (converted via `Color.hex()`), `footer` text, `image` URL, `thumbnail` URL, `author` (name/url/icon_url), `fields` (name/value/inline arrays), `url`, and `type` from each `AccordEmbed`.

**Attachments**: Builds a dictionary with `id`, `filename`, `size`, `url`, `content_type`, `width`, `height`. Prepends the CDN base URL via `AccordCDN.attachment()` if the URL is not already absolute.

### URL Unfurling (`../accordserver/src/unfurl.rs`)

Server-side URL unfurling:

1. `extract_urls()` scans message content for HTTP(S) URLs (max 5)
2. `unfurl_url()` fetches each URL with a 5-second timeout
3. `parse_opengraph()` extracts `og:title`, `og:description`, `og:image`, `og:site_name`, `og:type` meta tags
4. Falls back to `<title>` tag if no `og:title`
5. Generates `Embed` structs with `embed_type` set to `"video"` or `"link"`
6. `create_message()` in `routes/messages.rs` spawns a tokio task to unfurl URLs after message creation
7. If embeds are generated, the message is PATCHed and a `message.update` gateway event is broadcast

### Markdown Link Handling (`client_markdown.gd`)

`markdown_to_bbcode()` converts `[text](url)` to `[url=...]text[/url]` BBCode. Dangerous URL schemes (`javascript:`, `data:`, `file:`, `vbscript:`) are blocked and replaced with `#blocked`.

### CDN URL Construction (`cdn.gd`)

`AccordCDN.attachment()` builds URLs in the format:
```
{cdn_base}/attachments/{channel_id}/{attachment_id}/{filename}
```

## Implementation Status

- [x] Image attachments render inline (PNG, JPG, WebP)
- [x] Image aspect-ratio scaling to 400x300 max
- [x] File download links for all attachments (clickable filename + size)
- [x] Embed cards with title, description, footer, and colored border
- [x] Multiple embeds per message
- [x] CDN URL construction for attachments
- [x] Multipart upload endpoint for sending attachments
- [x] Markdown links rendered as clickable BBCode URLs
- [x] Dangerous URL scheme blocking (javascript:, data:, file:, vbscript:)
- [x] Embed data model with builder pattern (AccordEmbed)
- [x] Embed image display (loaded via HTTP, max 400x300)
- [x] Embed thumbnail display (80x80, right side of card)
- [x] Embed author display (name, URL, icon)
- [x] Embed fields display (name/value pairs, inline layout)
- [x] Embed URL (clickable title linking to embed.url)
- [x] URL unfurling / link previews (server-side OpenGraph fetching)
- [ ] YouTube video embeds (requires oEmbed provider integration)
- [ ] Other video host embeds (Vimeo, Twitch -- requires oEmbed)
- [x] Video attachment placeholder (play button, opens in browser)
- [x] GIF fallback display (click to view in browser)
- [x] Image lightbox / full-size viewer on click
- [x] Loading placeholder while images fetch
- [x] Image error state (red "Failed to load image" indicator)
- [x] Audio attachment inline player (play/pause, progress slider)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No YouTube embed support | Medium | YouTube links get basic OpenGraph unfurling but not the rich video player experience. Would need oEmbed provider list and specialized rendering. |
| No video host embeds | Medium | Vimeo, Twitch, Streamable need oEmbed integration for rich previews beyond basic OpenGraph. |
| Max image size hardcoded | Low | 400x300 max dimensions are hardcoded. Not configurable or responsive to viewport width. |
| Audio format support limited | Low | Only OGG and MP3 are attempted. WAV and other formats fall back to download link. |
| GIF not rendered inline | Low | Godot 4 has limited GIF support; would need a GIF decoder addon or server-side conversion to WebP/APNG for inline animation. |
