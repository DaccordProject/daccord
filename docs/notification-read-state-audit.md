# Notification and read-state behavior

Covers channel/DM unread state, mention counts, badges, local notifications,
gateway replay, and cross-device read acknowledgements.

## Client guarantees

- The visible channel acknowledges incoming messages, loaded history, and app
  resume — only while the app lifecycle is resumed and the route is current.
- Read actions use the newest position from history, channel metadata, and
  gateway/READY state (exact snowflake comparison).
- Read cursors are monotonic: an older remote ack keeps newer unreads and mentions.
- Delivery/read cursors suppress replayed or already-read events before unread
  deltas, banners, and sounds (message caches still receive them).
- Acks are serialized/coalesced per server+channel, check HTTP success, and
  retry while the provider is alive, including on READY.
- Notifications have unique IDs tied to server/channel/message; local reads,
  remote reads, and reconnects dismiss matching banners.
- Global badges and sounds apply each connection's own mute/channel settings.

## Known limits

- Server bug (`accordserver` `src/db/read_states.rs::ack_channel`): an ack
  resets `mention_count` to zero instead of counting mentions after the cursor,
  and the route broadcasts the submitted cursor with zero. The client preserves
  live mentions but can't fix a wrong READY snapshot after restart.
- Pending acks and dismissal associations are in memory: a process killed before
  an ack succeeds leaves that position unread, and banners from a previous
  process aren't tracked.
- Native notification centers are untested (tests mock the Android channel).
  Before release, verify manually with two signed-in devices: read on one,
  switch focus, reconnect both.
