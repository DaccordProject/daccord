---
title: Becoming an Admin
description: Create a space you control, or become the administrator of a server you host.
order: 0
section: administration
---

# Becoming an Admin

Daccord has two kinds of admin:

- **Space owner.** Whoever creates a space owns it and has full control:
  channels, roles, emoji, invites and moderation. Owners can share that power
  by giving other members roles. Most communities only need this.
- **Server administrator.** The person running an Accord server can manage the
  whole server: every space (including the default **General** space), every
  account, reports and server settings. This is set up by whoever hosts the
  server, on the computer it runs on.

Registering an account never makes you either. In particular, the first account
on a new server is an ordinary member.

## Why can't I change the General space?

When a server starts for the first time it creates a space called **General**
and adds every new account to it. General belongs to a hidden **System**
account, not to you, so ordinary members can chat in it but can't change its
settings. To customise a space, either [create your own](#create-your-own-space)
or [become the server administrator](#become-the-server-administrator).

## Create your own space

Any signed-in account can create a space and becomes its owner. This needs
Daccord 0.2.29 or later.

1. Click the **+** (**Add a server**) button at the bottom of the space list and
   open the **Create** tab. If you aren't in any spaces yet, you can also choose
   **Create a space** on the "No spaces yet" screen.
2. Enter a name and choose **Create**. Daccord opens your new space.
3. Right-click the space icon and choose **Space settings** to set its icon,
   channels, roles and emoji. See [Managing Your Space](managing-your-space.md).
4. Right-click the space icon and choose **Invite people** to make a link for
   your friends. See [Invites](invites.md).

The space is created on the server you're currently using. Guest sessions can't
create spaces.

## Become the server administrator

You need access to the computer that runs the server. Administrator accounts are
created there with a one-off command, which adds a new account and exits. It
doesn't change your server, your spaces or your existing accounts. Follow the
steps for how you host:

- **Accord desktop app:** see
  [Creating your administrator account](../self-hosting/desktop-app.md#creating-your-administrator-account).
- **Docker or a server deployment:** see
  [Creating your administrator account](../self-hosting/deploying-a-server.md#creating-your-administrator-account).

Then:

1. In Daccord, choose **Settings → Log out**, then sign in to your server with
   the administrator username and password you just created.
2. Open **Settings → Server administration**. From here you can manage every
   space, including General.
3. To use your everyday account instead, open the **Users** tab, find that
   account, open its **⋮** menu and choose **Make admin**. Then log out and sign
   back in with your everyday account.

If someone else makes you an administrator while you're signed in, restart
Daccord. Version 0.2.29 and later pick up the change when they reconnect; on
older versions, log out and sign back in.

You can give someone else server administration the same way. If you only want
to share control of one space, give them a role in that space instead.

### Editing the database by hand

Use the command above rather than editing the database. If you have already
edited it, check that:

- the server was stopped while you edited it;
- `is_admin` is set to the number `1`, not the text `true`;
- the change was saved (in DB Browser for SQLite, choose **Write Changes**);
- you edited the database the server actually uses. For the desktop app that is
  `accord.db` in its data folder. For Docker it is inside the server's volume,
  not a copy on your computer.

Then start the server again, and log out of Daccord and sign back in.
