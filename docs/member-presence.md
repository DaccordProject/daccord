# Member roster presence

The roster loads every member page using the server's `after` cursor. Servers
that omit cursor metadata are supported by advancing after a full 100-member
page. A repeated or malformed cursor fails the load instead of silently
presenting a partial roster as complete. Pages keep embedded user objects;
older servers' missing profiles use the bounded shared user-resolution queue.

Snapshot loads have generations and record live member/profile changes while
in flight. A superseded load cannot overwrite the latest roster. Live joins,
updates, and leaves survive the snapshot, and delayed profile resolution only
enriches the same member record if it still exists. Fresh READY after reconnect
reloads open rosters; successful RESUME retains normal event replay behavior.

Online, Idle, and Do Not Disturb are visible statuses. Offline, Invisible, and
unknown statuses enter the Offline group and use muted rows. Counts come from
the complete roster and the same presence cache used to group rows, including
the existing eight-second offline grace. Space-summary counts cannot override
current rows.

Opening or refreshing a roster requests
`GET /api/v1/spaces/{space_id}/presences`. The SDK parses the snapshot into typed
presences. Snapshot merging is scoped to returned users and preserves gateway
writes received during the request, including offline transitions still
waiting for grace. Learning a home domain rekeys pending transitions without
restarting or losing their deadlines. Other spaces' presences are retained.
Older servers without the endpoint continue to use READY and live updates.

Presence remains per server and uses qualified user IDs. A message does not
force its author online: an explicit Invisible choice must stay private.
The matching accordserver update supplies private-safe snapshots and signed,
expiring presence exchange between trusted user-home servers.

Regression coverage includes members beyond page one, older cursorless
servers, cursor failures, snapshot/live-event races, removed/replaced profiles,
reconnect recovery, scoped presence refresh, Invisible grouping, counts,
pending offline grace, and federation ID isolation.
