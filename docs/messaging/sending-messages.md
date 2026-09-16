---
title: Sending Messages
description: Send, reply to, edit, and delete messages.
order: 1
section: messaging
---

# Sending Messages

## Sending

Type in the composer at the bottom of the message area and press **Enter** (or the send button) to send.

Messages support Markdown, including:

- `**bold**`, `*italic*`, `__underline__`, `~~strikethrough~~`
- `` `inline code` `` and fenced code blocks
- `||spoiler||`
- Headings, lists, quotes, and links

Mention people with `@name` and link channels with `#channel`.

## Message Actions

Hover a message to show its action bar, or right-click it (long-press on touch) for the full menu. **Reply** and **Add reaction** are on the action bar; **Edit**, **Delete**, and other actions are in the **⋯** menu.

## Replying

Choose **Reply**. A "Replying to [name]" bar appears above the composer; click its **x** to cancel.

## Editing

Choose **Edit** on your own message. The message becomes editable in place; click **Save** to keep your changes or **Cancel** to discard them. Edited messages show "(edited)".

## Deleting

Choose **Delete** and confirm. Members with the right permissions can also delete other people's messages.

## Drafts

An unsent message is saved when you switch channels and restored when you come back.

## If Sending Fails

If a message can't be sent (for example, you lost your connection), its text and attachments are put back in the composer and the error is shown above it. Nothing is resent automatically.

On Web, pasting uses the browser's normal text input. Native clients also support pasting images and the large-text attachment prompt.

## Link previews

**Show embeds and link previews** in appearance settings hides previews for your
account only; message text and attachments stay visible.

YouTube previews show the title, a 16:9 poster, and an **Open in YouTube** link.
On Web, **Play · load from YouTube** loads the official player; native clients
and narrow columns use the external link. Playback stops when the message
scrolls away, you switch channels, or the app loses focus. Posters require
external-media consent, and nothing is loaded from YouTube until you press Play.

Author/moderator embed suppression needs server support (#352); the client
honors the suppression flag when the server sends it.
