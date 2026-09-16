---
title: Voice and Video
description: Join voice channels for real-time audio and video conversations.
order: 1
section: voice-and-video
---

# Voice and Video

## Joining a Voice Channel

Click a **voice channel** (speaker icon) in the channel list. A **voice bar** appears at the bottom of the channel list with the channel name and a green status dot once connected.

In the participant list, a green ring marks whoever is speaking, and badges show who is muted (M), deafened (D), on camera (V), or sharing their screen (S).

## Voice Controls

- **Mute** -- turn your microphone on or off
- **Deafen** -- stop hearing incoming audio (your microphone is not muted)
- **Camera** -- turn your camera on or off
- **Screen share** -- share a screen or window (not available on the web)
- **Soundboard** -- play clips into the channel, if your role allows it
- **Voice settings** -- open voice and video settings
- **Disconnect** -- leave the channel

## Screen Sharing

On desktop, clicking **Screen share** opens a picker for a screen or window; on mobile, your device's own capture prompt appears. Click the button again to stop.

## Voice Settings

Open from the voice bar gear or **Settings → Voice & Video → Voice & video settings** to choose devices and audio options, including the idle (AFK) timeout.

The **Output device** picker appears on desktop and Android only. iOS routes call audio itself (use Control Centre, AirPlay, or a headset), and browsers don't allow the choice.

### Relay-only connections

**Relay-only voice** in **Voice & Video** settings (off by default) forces voice,
video, and screen sharing through a TURN relay. Rejoin a call to apply it. It can
add latency and needs the server's LiveKit deployment to provide TURN; if the
relay is unreachable the call fails with an error rather than connecting directly.
See [network privacy](../privacy-network.md).
