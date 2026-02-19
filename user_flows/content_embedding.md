# Content Embedding

Last touched: 2026-02-19

## Overview

Content embedding covers how daccord renders rich previews for images, videos, and links within messages. Image attachments uploaded through the server are displayed inline with aspect-ratio scaling. Server-generated embeds (title/description/footer cards with colored borders) render below message text. URL unfurling, video playback, and YouTube/oEmbed previews are not yet implemented.

## User Steps

### Viewing an image attachment
1. A message arrives containing an image attachment (PNG, JPG, or WebP)
2. The image is fetched from the server CDN via HTTP
3. The image renders inline below the message text, scaled to fit within 400x300 pixels
4. A clickable filename link with file size appears below the image

### Viewing an embed card
1. A message arrives containing one or more embed objects (generated server-side)
2. Each embed renders as a card with a colored left border, title, description, and optional footer
3. Multiple embeds stack vertically below the message text

### Clicking a link
1. The user clicks a `[text](url)` markdown link rendered in the message
2. The URL opens in the system default browser via `OS.shell_open()`
3. No preview or unfurl is generated for the link

## Signal Flow

```
Server sends MESSAGE_CREATE with embeds/attachments
    │
    ▼
Client._on_gateway_message_create()
    │
    ▼
ClientModels.accord_message_to_dict()
    ├── Converts AccordEmbed array → embeds_arr (title, description, color, footer, image, thumbnail)
    └── Converts AccordAttachment array → attachments_arr (id, filename, size, url, content_type, width, height)
    │
    ▼
AppState.messages_updated emitted
    │
    ▼
message_view rebuilds message list
    │
    ▼
message_content.setup(data)
    ├── Attachments: detects image/* content_type → creates Control container → _load_image_attachment()
    ├── Attachments: creates RichTextLabel link for every attachment (filename + size)
    └── Embeds: calls embed.setup() for each embed dict
```

## Key Files

| File | Role |
|------|------|
| `scenes/messages/message_content.gd` | Attachment rendering (image inline + file links) and embed orchestration |
| `scenes/messages/message_content.tscn` | Scene layout: TextContent → Embed → ReactionBar |
| `scenes/messages/embed.gd` | Embed card rendering (title, description, footer, colored border) |
| `scenes/messages/embed.tscn` | PanelContainer with 4px left border, VBox with Title/Description/Footer |
| `scripts/autoload/client_models.gd` | Converts `AccordEmbed` and `AccordAttachment` models to UI dictionaries |
| `scripts/autoload/client_markdown.gd` | Markdown-to-BBCode conversion (links, but no URL unfurling) |
| `addons/accordkit/models/embed.gd` | `AccordEmbed` model: title, type, description, url, color, footer, image, thumbnail, author, fields |
| `addons/accordkit/models/attachment.gd` | `AccordAttachment` model: id, filename, content_type, size, url, width, height |
| `addons/accordkit/utils/cdn.gd` | `AccordCDN.attachment()` builds CDN URLs for file downloads |
| `addons/accordkit/rest/endpoints/messages_api.gd` | `create_with_attachments()` for multipart file upload |

## Implementation Details

### Image Attachment Rendering (`message_content.gd`)

When `setup()` receives a message dictionary, it iterates the `attachments` array (line 39). For each attachment whose `content_type` starts with `"image/"` (line 47), it:

1. Reads `width` and `height` from attachment metadata, defaulting to 400x300 (lines 48-49)
2. Caps dimensions to a hardcoded maximum of 400x300 pixels (lines 50-51)
3. Creates a `Control` container with `custom_minimum_size` set to the capped dimensions (lines 52-53)
4. Inserts the container before the ReactionBar via `move_child()` (line 56)
5. Calls `_load_image_attachment()` asynchronously to fetch and display the image (line 57)

Every attachment (image or not) also gets a clickable filename link showing the file size (lines 59-74). The link uses `[url=...]` BBCode and connects `meta_clicked` to `_on_meta_clicked`, which calls `OS.shell_open()` for HTTP(S) URLs (lines 106-107).

### Image Loading (`message_content.gd`)

`_load_image_attachment()` (lines 109-149) fetches the image via an `HTTPRequest` node:

1. Creates an `HTTPRequest`, sends a GET to the image URL (lines 110-112)
2. Awaits the response; bails on non-200 or request failure (lines 116-124)
3. Tries loading the response body as PNG, then JPG, then WebP (lines 127-132)
4. Scales the image to fit within max dimensions while preserving aspect ratio (lines 135-142)
5. Creates an `ImageTexture` and `TextureRect` with `STRETCH_KEEP_ASPECT` (lines 143-147)
6. Updates the container's `custom_minimum_size` to match the actual image dimensions (line 149)

Supported formats: PNG, JPG, WebP. GIF and other formats silently fail.

### Embed Card Rendering (`embed.gd`)

The `setup()` method (line 13) receives an embed dictionary and:

1. Hides itself if the dictionary is empty (lines 14-16)
2. Sets title, description (RichTextLabel with BBCode), and footer text (lines 19-21)
3. Hides title/footer labels when empty (lines 23-24)
4. Duplicates the panel StyleBoxFlat and overrides the left border color from `data["color"]`, defaulting to blue-purple `Color(0.345, 0.396, 0.949)` (lines 27-30)

The embed scene (`embed.tscn`) is a `PanelContainer` with:
- Background: dark gray `(0.184, 0.192, 0.212)` (line 6)
- Left border: 4px wide (line 7)
- Corner radius: 4px all corners (lines 9-12)
- Content margins: 16px horizontal, 8px vertical (lines 13-16)
- Minimum width: 200px (line 19)

### Multiple Embeds (`message_content.gd`)

Messages can contain multiple embeds (lines 76-91):

1. The first embed uses the static `$Embed` node already in the scene (line 80)
2. Additional embeds dynamically instantiate `EmbedScene` and insert before the ReactionBar (lines 82-87)
3. For backward compatibility, if `embeds` array is empty, falls back to a single `embed` dictionary (lines 88-91)

### Model Conversion (`client_models.gd`)

`accord_message_to_dict()` converts AccordKit models to UI dictionaries:

**Embeds** (lines 322-340): Extracts `title`, `description`, `color` (converted via `Color.hex()`), `footer` text, `image` URL, and `thumbnail` URL from each `AccordEmbed`. The `image` and `thumbnail` URLs are extracted but **not rendered** by the current embed UI.

**Attachments** (lines 342-363): Builds a dictionary with `id`, `filename`, `size`, `url`, `content_type`, `width`, `height`. Prepends the CDN base URL via `AccordCDN.attachment()` if the URL is not already absolute (lines 347-350).

### Markdown Link Handling (`client_markdown.gd`)

`markdown_to_bbcode()` converts `[text](url)` to `[url=...]text[/url]` BBCode (lines 40-55). Dangerous URL schemes (`javascript:`, `data:`, `file:`, `vbscript:`) are blocked and replaced with `#blocked` (lines 49-53). No URL unfurling, OpenGraph metadata fetching, or link preview generation occurs.

### CDN URL Construction (`cdn.gd`)

`AccordCDN.attachment()` (lines 50-57) builds URLs in the format:
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
- [ ] Embed image display (data is extracted but not rendered in embed.gd)
- [ ] Embed thumbnail display (data is extracted but not rendered in embed.gd)
- [ ] Embed author display (name, URL, icon)
- [ ] Embed fields display (name/value pairs, inline layout)
- [ ] Embed URL (clickable title linking to embed.url)
- [ ] URL unfurling / link previews (no OpenGraph/oEmbed fetching)
- [ ] YouTube video embeds
- [ ] Other video host embeds (Vimeo, Twitch, etc.)
- [ ] Video attachment playback (video/* content_type not handled)
- [ ] GIF/animated image support
- [ ] Image lightbox / full-size viewer on click
- [ ] Loading placeholder / skeleton while images fetch
- [ ] Image error state (broken image indicator)
- [ ] Audio attachment playback (audio/* content_type not handled)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Embed image not rendered | High | `client_models.gd` extracts `image` URL (line 335) into the embed dict, but `embed.gd` never reads or displays it. Server-side image embeds silently show no image. |
| Embed thumbnail not rendered | High | `client_models.gd` extracts `thumbnail` URL (line 337) but `embed.gd` ignores it. Thumbnails from link previews won't display. |
| Embed fields not rendered | Medium | `AccordEmbed` model supports `fields` array (line 16 of embed.gd model), but `client_models.gd` doesn't convert fields and `embed.gd` doesn't render them. |
| Embed author not rendered | Medium | `AccordEmbed` model supports `author` (name/url/icon_url) but neither conversion nor rendering exists. |
| Embed URL not clickable | Low | `AccordEmbed.url` is parsed (line 24 of embed.gd model) but never used to make the title a hyperlink. |
| No URL unfurling | High | Pasting a URL in a message produces plain text. No client-side or server-side OpenGraph/oEmbed metadata fetching. This is a prerequisite for YouTube embeds and link previews. |
| No YouTube embed support | High | YouTube links are not detected or given special treatment. No video player component exists. Requires either server-side oEmbed proxying or client-side YouTube URL pattern matching with an embedded video player. |
| No video host embeds | Medium | Vimeo, Twitch, Streamable, and other video hosts are not handled. Depends on the same URL unfurling infrastructure as YouTube. |
| No video attachment playback | Medium | Attachments with `content_type` starting with `video/` are only shown as download links (line 47 checks `image/` only). Godot's `VideoStreamPlayer` could handle MP4/WebM. |
| No GIF support | Medium | `_load_image_attachment()` tries PNG, JPG, WebP only (lines 127-131). GIF files silently fail to render. Godot 4 has limited GIF support; would need a GIF decoder addon or server-side conversion to WebP/APNG. |
| No image lightbox | Low | Clicking an inline image does nothing. Users cannot view full-size images or zoom in. |
| No loading state for images | Low | The container is created at full size (line 53) but appears empty until the HTTP request completes. No spinner or skeleton placeholder is shown. |
| No image error handling | Low | If the image fetch fails (non-200, invalid format), the container remains empty with no visual feedback (lines 123-124, 132-133 silently return). |
| Max image size hardcoded | Low | 400x300 max dimensions are hardcoded (lines 50-51 in message_content.gd). Not configurable or responsive to viewport width. |
| No audio attachment playback | Low | Audio files (MP3, OGG, WAV) only get a download link. An inline audio player could use Godot's `AudioStreamPlayer`. |
