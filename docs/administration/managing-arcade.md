---
title: Managing Arcade
description: Enable reviewed games, organize the Arcade channel, and manage your community's lobbies.
order: 4
section: administration
---

# Managing Arcade

Arcade gives your space a channel for multiplayer games. Your server operator
must enable experiences and configure a trusted game directory before space
managers can add games.

## Add games to your space

1. Open **Space Settings → Arcade** with an account that has **Manage Space**.
2. Find a reviewed game available for your platform and choose **Enable**.
3. Open the **Arcade** channel in the channel list.
4. Choose **Create lobby**, pick a game, and choose an open or invite-only lobby.

The first installed game creates the Arcade channel. Each space has one Arcade
channel; installing additional games uses the same channel. Move it between
categories or reorder it alongside ordinary channels. You can also rename it.
The space header stays above the channel list.

Lobbies show the host's name and the players so friends can find the right
game. Invite-only lobbies are visible only to members allowed to access them.
Players join and mark themselves ready; the host starts once both are ready.

## Activity count and notifications

The number next to Arcade counts visible, active lobbies and running games.
Finished games do not count. Muting the Arcade channel or setting its
notifications to **Nothing** hides the number. Unmuting restores the count.

## Idle games and cleanup

The lobby list and game screen show an idle countdown. A game is removed after
seven days without player activity. Joining as a player, ready/start changes,
and valid gameplay actions refresh the countdown. Watching, reopening the
screen, reconnecting, and automatic simulation ticks do not keep an unused
game alive.

Cleanup removes the idle session, while installed games and the Arcade channel
remain available. Members can create a new lobby whenever they want to play
again. Other finished results have a bounded 30-day history. Games may also
end earlier because of a configured turn timeout or a Pong disconnect forfeit.

## Updates, disabling, and removal

Space managers explicitly choose which reviewed version to enable. Updating,
rolling back, disabling, or removing a game stops its active sessions. A
rollback requires an older version that is still approved. Turning off the
Arcade switch stops the space's games.

If you see **experiences are disabled by this server's operator**, ask your
operator to configure experiences and trusted directory keys. An unavailable
game can also indicate an unsupported platform, directory outage, or withdrawn
approval.

## Create a custom extension

Developers can package custom Chess or Pong presentation for the space, or
implement a new authority with coordinated server and client changes. Follow
[Creating Arcade Extensions](../developer/creating-arcade-extensions.md) for a
working example, testing, review, and private-directory setup.
