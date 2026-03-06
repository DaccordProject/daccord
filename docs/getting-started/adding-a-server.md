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
- A protocol: `https://chat.example.com` (HTTPS is used by default)

If you received an invite link starting with `daccord://`, clicking it will open daccord and fill in the server details automatically.

## What Happens Next

- If the URL includes a token, you'll be connected immediately.
- If not, an authentication dialog appears where you can [sign in or create an account](creating-an-account.md).
- Once connected, the server's space icon appears in the space bar and you can start browsing channels.

## Multiple Servers

You can connect to as many servers as you like. Each one appears as a separate icon in the space bar. Click an icon to switch between servers.

## Removing a Server

Right-click a space icon in the space bar and select **Remove Server** to disconnect from that server.
