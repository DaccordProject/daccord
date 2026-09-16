# AutoMod in the client

Server protocol: [accordserver `docs/automod.md`](https://github.com/DaccordProject/accordserver/blob/master/docs/automod.md).

## Access

- Instance administrators: **Server administration → AutoMod**.
- Space managers (`manage_space`): **Space settings → AutoMod**, to configure a full override or restore the inherited instance policy.
- `moderate_members` holders open the same space screen to review uploads, without configuration access.

## Policy

Rules run in order: detector categories and thresholds, channel scope, policy-wide role/permission exemptions, evidence retention, and quarantine/reject/flag actions. Timeout is available only for hash or trust rules. Saving replaces the whole policy. Enabling scanning does not install a model; instance health shows detector/video status and queue counts so the operator can finish server setup.

Videos are sampled at five frames (10/30/50/70/90%), taking the highest score per category; content between samples can be missed. Review shows category scores and sample timestamps.

## Review

The Review tab filters pending, quarantined, rejected, published, and removed uploads. Release, quarantine, reject, retry, and removal require a reason. Evidence is fetched through the authenticated private API only (64 MiB in-memory cap, no redirects, no public CDN fallback). Previews are evicted on close; switching accounts disposes the review surface and closes its evidence dialog. Downloaded originals stay on the user's device. Server checks still apply to expired evidence and deleted messages; release cannot restore a deleted message.

## Block files and delete

Offered beside message deletion to members with effective channel `manage_messages`; only instance administrators can choose a global block (including DMs). The user selects files and a reason; the client blocks each attachment **before** deleting the message. A failed block leaves the message; a failed delete keeps successful blocks and reports the partial result. No client download or hashing is needed.

The Blocked files tab lets configurators add SHA-256 digests, inspect reason/actor/timestamp, and remove blocks. Hash blocks work without model scanning; modified copies hash differently.

## Client state

- Pending upload IDs persist per server/account across reconnects (`pending-uploads` box); rejected uploads remain releasable during retention and are reconciled too.
- Gateway withdrawal events remove attachments from caches and viewers.
- Servers without the optional AutoMod endpoints show an update message; chat still works.
- The main composer shows slowmode and upload budgets. Thread replies and forum posts also keep a rejected draft and show the server's 429 retry countdown. No send path auto-resends.
