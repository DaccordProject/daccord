# AutoMod in the client

The server's AutoMod protocol is documented in
[DaccordProject/accordserver](https://github.com/DaccordProject/accordserver/blob/master/docs/automod.md).

Instance administrators open **Admin panel → AutoMod**. Space managers open
**Space settings → AutoMod** to configure a complete override or restore the
inherited instance policy. Members with `moderate_members` can open the same
space screen to review uploads without gaining configuration access.

Rules run in order. Configure explicit detector categories and thresholds,
channel scope, policy-wide role/permission exemptions, evidence retention, and
quarantine/reject/flag actions. Timeout is available only for hash or trust
rules. Saving replaces the full policy. Enabling scanning does not install a
model: instance health shows detector/video status and queue counts so the
operator can complete server setup.

Videos stay ordinary uploads. The server samples five frames at 10%, 30%, 50%,
70%, and 90% and applies the highest score per category. This does not inspect
every frame. The review screen displays available category scores and sample
timestamps.

The Review tab filters pending, quarantined, rejected, published, and removed
uploads. Release, quarantine, reject, retry, and removal require a reason.
Evidence is downloaded through the authenticated private API, with a 64 MiB
in-memory limit and no redirect following or public CDN fallback. Image previews
are evicted when closed; switching accounts disposes the review surface and
closes its evidence dialog. Downloaded originals remain on the user's device.
Expired evidence and deleted messages remain subject to server checks; release
cannot restore a deleted message.

**Block files and delete** is available beside message deletion to channel
message managers; only instance administrators can select a global block,
including DMs. Select files and enter a reason. The client blocks each selected
attachment before deleting the message. If a block fails, the message stays; if
deletion fails, successful blocks remain and the UI reports that partial result.
No client download or hashing is necessary. The Blocked files tab also allows
configurators to add known SHA-256 digests, inspect reasons/actors/timestamps,
and remove blocks. Exact hash blocks operate independently of model scanning;
modified copies can have different hashes.

Pending uploads remain associated with their server/account across reconnects.
Rejected uploads can still be released during retention and are reconciled too.
Gateway withdrawal events remove attachments from caches and viewers. Older
servers without the optional AutoMod endpoints show an update message while
ordinary chat remains usable.

The main composer shows configured slowmode and upload budgets. Thread replies
and forum posts also preserve a rejected draft and show the server's 429 retry
countdown; none of these send paths automatically resend a failed message.
