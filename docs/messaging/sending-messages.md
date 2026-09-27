---
title: Sending Messages
description: Send, reply to, edit, and delete messages.
order: 1
section: messaging
---

# Sending Messages

## Sending

Type your message in the composer at the bottom of the message area and press **Enter** to send. In the desktop apps (Windows, macOS and Linux), press **Shift+Enter** to insert a new line without sending. On mobile, the keyboard's **Send** key sends the message.

daccord supports basic Markdown formatting in messages:

- `**bold**` for **bold**
- `*italic*` for *italic*
- `` `code` `` for `inline code`
- ``` ```code block``` ``` for code blocks

## Replying

To reply to a specific message:

1. Hover over the message and click the **Reply** button in the floating action bar, or right-click and select **Reply**.
2. A reply bar appears above the composer showing "Replying to [name]".
3. Type your reply and send as usual.
4. Click the **x** on the reply bar to cancel.

## Editing

You can edit your own messages:

1. Hover over your message and click the **Edit** button, or right-click and select **Edit**.
2. The message text becomes editable inline.
3. Press **Enter** to save your changes.
4. Press **Escape** to cancel and discard changes.

You can also press the **Up arrow** key in an empty composer to quickly edit your last sent message.

Edited messages display an "(edited)" indicator.

## Deleting

To delete your own message:

1. Hover over the message and click the **Delete** button, or right-click and select **Delete**.
2. Confirm the deletion.

Admins may also be able to delete other users' messages depending on their permissions.

## Drafts

If you switch to a different channel before sending, your unfinished message is automatically saved as a draft. When you return to that channel, the draft is restored so you can continue where you left off.

## Sending While Disconnected

If you lose your connection, you can still type and send messages. They are queued locally and sent automatically once the connection is restored. A "Message queued" notice appears below the composer to let you know.

## Typing Indicator

When you're typing, other users in the channel see a typing indicator below the message list showing your name.

On Web, keyboard and browser-menu text paste use the browser's normal editor
input. Native clients also support clipboard images and the large-text attachment
prompt.

## Link previews

**Show embeds and link previews** in appearance settings controls previews only
for your account; hiding them leaves the message text and attachments visible.
YouTube previews retain the title, 16:9 poster and **Open in YouTube** link. Web
can load the official player after you select **Play · load from YouTube**;
native clients and narrow message columns use the external link. Playback stops
when its message leaves view, the channel changes or the app loses focus. A
player error returns to the poster with the external link.

External posters require the existing media consent. Starting the player also
contacts YouTube's official player/API hosts; no player is loaded merely by
opening message history. Player behavior follows the
[YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference).

Author/moderator suppression, angle-bracket link exclusion and asynchronous
unfurl permission/federation behavior still require server support (#352).
The client respects a suppression flag when supplied by the server.
