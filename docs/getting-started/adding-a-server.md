---
title: Adding a Server
description: Connect to a daccord server to start chatting.
order: 2
section: getting-started
---

# Adding a Server

A server is a community host running accordserver. You need at least one.

## How to Add a Server

1. Click the **+** button at the end of the space list in the space bar (the icon strip on the left).
2. In **Add a Server**, stay on **Enter URL** (or use **Browse** to pick a public server).
3. Enter the server URL, e.g. `chat.example.com`, and click **Connect**.
4. [Sign in or register](creating-an-account.md) when prompted.

## Server URL Format

A bare hostname like `chat.example.com` uses HTTPS. You can also add:

- A port: `chat.example.com:8443`
- A scheme: `https://chat.example.com`
- A space to open: `chat.example.com#my-space`
- A token, to sign in directly: `chat.example.com?token=yourtoken`
- An invite code, redeemed after connecting: `chat.example.com?invite=yourcode`

> **Local or self-hosted server?** Include `http://`, e.g. `http://localhost:39099` or `http://192.168.1.50:39099`. Without it the client tries HTTPS against a plain-HTTP server and fails with a "Broken pipe" error.

## daccord:// Links

Opening a `daccord://` link in an installed client connects to the server and, after sign-in, selects the linked space, channel, thread, or message.

The Android, iOS, and macOS apps, the Windows installer, and the Linux `.deb` register these links. The portable Windows and Linux archives don't, and browsers can't open them in the web build; paste the link into **Add a Server** instead (or use a normal server URL on the web).

## Removing a Server

Right-click a server's icon in the space bar and choose **Remove server**.

## Joining with a saved account

Discovery, pasted server/invite URLs, and `daccord://connect` or `daccord://invite`
links first look for a saved account on the target server (even one not yet
connected), reconnect it, join the space, and open it. The active account wins if
several match. You're only asked to sign in when no saved account matches, and
invite details survive the login.

Host case, default ports, and trailing slashes are normalized; HTTP vs HTTPS,
non-default ports, and server paths are treated as different servers.
