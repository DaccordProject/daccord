---
title: Adding a Server
description: Connect to a daccord server to start chatting.
order: 2
section: getting-started
---

# Adding a Server

To use daccord, you need to connect to at least one server. A server is a community hosted by someone running accordserver.

## How to Add a Server

1. Click the **+** button at the bottom of the space bar (the icon strip on the left side of the window).
2. The Add Server dialog opens.
3. Enter the server URL you were given. This is usually something like `chat.example.com`.
4. Click **Connect**.

## Server URL Format

The simplest URL is just a hostname like `chat.example.com`. You can also include:

- A port number: `chat.example.com:8443`
- A specific space: `chat.example.com#my-space` (defaults to "general" if omitted)
- A protocol: `https://chat.example.com` (HTTPS is used by default when no scheme is given)

> **Connecting to a local or self-hosted server?** Add the `http://` prefix, e.g. `http://localhost:39099` or `http://192.168.1.50:39099`. Self-hosted servers serve plain HTTP on the local network, and without the prefix the client assumes `https://` and the connection fails with a "Broken pipe" error.
- A pre-filled token: `chat.example.com?token=yourtoken` (logs you in automatically)
- An invite code: `chat.example.com?invite=yourcode` (joins the space using the invite)

If you received a link starting with `daccord://`, opening it in an installed
client preserves its destination: connect links select their space/channel
after sign-in, and navigation links select the connected server, space, and
channel before opening a linked thread or message.

Automatic `daccord://` registration is included in the Android, iOS, and macOS
apps, the Windows installer, and the Linux `.deb` package. Portable Windows and
Linux archives do not register handlers with the operating system; paste the
link into **Add a Server** instead. Browsers do not handle this custom scheme
inside the web build, so use a normal server URL there.

## What Happens Next

- If the URL includes a `?token=` parameter, you'll be connected and signed in immediately.
- If it includes a `?invite=` parameter, the invite is accepted during connection.
- If neither is present, an authentication dialog appears where you can [sign in or create an account](creating-an-account.md).
- Once connected, the server's space icon appears in the space bar and you can start browsing channels.

## Multiple Servers

You can connect to as many servers as you like. Each one appears as a separate icon in the space bar. Click an icon to switch between servers.

## Removing a Server

Right-click a space icon in the space bar and select **Remove Server** to disconnect from that server.
