# Notification and read-state audit

Originally audited 2026-09-07; reconciled with current master on 2026-09-12. Scope: channel and DM unread highlighting, mention counts,
desktop/app badges, local notification banners and sounds, gateway replay,
reconnect hydration, and read acknowledgements between devices.

## Client findings and fixes

| Finding | Resulting change |
| --- | --- |
| Messages arriving in the visible channel skipped local unread state but never acknowledged the new message to the server. Other devices and reconnects consequently showed already-viewed messages as unread. | The gateway acknowledges the actual incoming message ID while the app is focused on that channel. |
| Opening a channel acknowledged before history loaded. Text channels had no subsequent acknowledgement when the newer history became available. | The shared message pane acknowledges loaded history, incoming state changes and app resume. This also covers DMs and voice chat rendered by that pane. |
| Cached history took precedence over newer channel metadata. | Read actions choose the newest position from history, channel metadata and gateway/READY state, using exact snowflake comparison. |
| A selected channel counted as visible while the app was inactive. | Automatic acknowledgement and notification suppression now require resumed app lifecycle state. |
| Acknowledgements from another device unconditionally cleared the entire channel. | Read cursors advance monotonically; older acknowledgements retain newer unread messages and known newer mentions. |
| Gateway replays could increment mention counts and produce alerts repeatedly. | Delivery and read cursors suppress repeated or already-read message events before unread deltas, banners and sounds. Message caches still receive the events. |
| Acknowledgement failures were ignored and requests could overlap. | A per-server, per-channel queue serializes/coalesces acknowledgements, checks HTTP success, and retries failures while the provider is alive, including on READY. |
| Delivered local banners outlived read acknowledgements. Timestamp-derived notification IDs could also collide during bursts. | Notifications have distinct IDs and server/channel/message associations. Local reads, remote reads and reconnect reconciliation dismiss matching banners, including races with asynchronous delivery. |
| The home route could overwrite the visible DM pointer while rebuilding beneath its dialog. | The home route updates visibility only while it is the current route. |
| The global badge looked up raw IDs in settings stored under server-qualified keys. | Global aggregation applies each connection's own mute and channel settings. |
| Channels set to “nothing” suppressed banners and highlighting but could still chime. | Incoming-message sounds honor the same per-channel suppression. |

## Server follow-up

The September 7 read-only inspection of the sibling `accordserver` repository found that
`src/db/read_states.rs::ack_channel` preserves the maximum read cursor but
unconditionally resets `mention_count` to zero. A delayed or partial acknowledgement
can therefore erase the persisted count for newer unread mentions. The client now
preserves newer live mentions locally, but cannot reconstruct a correct count from
an incorrect READY snapshot after restarting.

The server should calculate the remaining mentions after the effective read
cursor atomically with the acknowledgement, and broadcast that effective cursor
and remaining count. The current route in `src/routes/read_states.rs` broadcasts
the submitted cursor and zero. No server files were changed in this client patch.

## Validation and limits

Regression tests cover serialized acknowledgements, failures/reconnect retries,
numeric cursor ordering, duplicate events, delayed remote reads, app
inactivity/resume, history loading, server-specific mute settings, notification
dismissal races, and the existing own-message and DM call behavior. Run
`flutter test` and `scripts/codegen.sh --check` when modifying this flow.

Physical devices and native notification centers were not exercised. Notification
tests use the Android method channel with a mocked platform. Dismissal associations
and pending acknowledgements are held in memory: an app process killed before an
ack succeeds can still leave that position unread on the server, and banners from
a previous process are not tracked by the new process.

Before release, check with two signed-in devices: receive messages while viewing
the channel, leave and return, switch app focus, read on the other device, and
reconnect each device. Confirm that genuinely newer messages remain highlighted,
read messages stay cleared, and old notification banners are dismissed.
