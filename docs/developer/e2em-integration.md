---
title: E2EM integration
description: Local outgoing text assessment, setup, policy composition, and remaining integration work.
order: 40
section: developer
---

# E2EM integration

This is the first implementation slice of #414.

The desktop client can assess outgoing text with the installed E2EM runtime.
Enable it in **Settings → App → E2EM → Personal content rules** on desktop,
or the E2EM section of the narrow settings layout. It is off on existing profiles
until enabled. Personal category selection, custom rules, sensitivity, and
warning/hold behaviour are saved with the profile and included in settings backups.
Runtime credentials stay in E2EM's installer-managed storage.

## Local setup

Install E2EM and its model, then use **Connect Daccord to E2EM** to open the
runtime's setup screen. Approve **Connect app** for `daccord`, return to Daccord,
and choose **Check connection and rules**. On Unix, the equivalent is:

```sh
e2emd --setup --setup-app daccord
```

The application never copies another app's credentials or grants itself access.
If setup cannot be opened automatically, use the installed E2EM setup application
and connect `daccord` there. The provider validates the policy configuration;
execution coverage is checked separately for every message.

The Dart package is pinned to upstream revision
`46e1b9c4b533e91cbf84fa50eae981e050bc15bd` in `sdk/dart`. This SDK supports
authenticated desktop IPC on Linux, macOS, and Windows. Mobile uses an explicit
unsupported adapter; web excludes the native SDK with a conditional import.
Saved enabled checks hold text sends on unsupported devices until the user
revises their own preference or support becomes available.

## Send boundary

Authenticated Accord clients install `MessagesApi.sendGuard`, covering message
creation, editing, thread/forum/MCP callers, and multipart attachment captions.
The API detaches the caller's JSON payload before awaiting the guard. The guard
sees an immutable snapshot of final transformed text, before encryption or upload.
The composer hands off that snapshot and accepts subsequent input as a new draft.

A complete, current `allow` can proceed. `warn` needs confirmation showing the
exact checked draft. `review`, incomplete coverage, timeout, cancellation,
unsupported rules, and malformed responses hold the operation. The API rechecks
settings/session validity after asynchronous encryption and immediately before
the network write. Warning confirmation never retries a network write.
Normal composer failure handling restores held text and attachments.

The runtime connection is reused, closed with its provider, and disconnected on
assessment failures. A subsequent explicit user action may reconnect; an error
never automatically reassesses and sends. Message content and runtime credentials
are not logged by this integration. Outgoing embeds are held while checks are
enabled because assessing only `content` would omit their additional text.

## Policies and remaining scope

`composeE2emPolicy` retains personal and space requirements as separate rules
with source namespaces, thresholds, and actions. Supplying a mandatory space
layer forces platform authority and forbids user overrides, even if personal
checks are off. Exceeding the provider's rule limit fails rather than dropping
requirements. The current runtime rejects platform authority, so this composition
is tested preparation for the space API; it is not connected to an invented
server field or presented as working enforcement.

This slice does not assess incoming content, files, images, audio/video, or fetched
link destinations, and does not supply conversation history to the model. Longer
messages can therefore be held for incomplete model coverage. The remaining #414
work includes server-authorised versioned space policies and federation, runtime
platform authority, incoming presentation/notification gates, contextual history,
and mobile/browser adapters. Model accuracy and language coverage remain separate
from successful configuration validation; no safe-space guarantee is implied.

## Validation

```sh
flutter test --no-pub test/features/e2em test/features/settings
cd packages/accordkit
dart test test/message_send_check_test.dart test/accord_client_test.dart
```

For a read-only check against a locally installed and enrolled runtime:

```sh
dart run tool/e2em_smoke.dart
```

An optional argument chooses an already enrolled app for development diagnostics
(for example `my-app`). It does not enrol an app or print message content or secrets.

The first slice passed 141 focused Flutter tests and 12 AccordKit tests. The local
runtime smoke check and web debug build also passed. Analysis of changed code is
clean; full-project analysis still reports six existing style notices elsewhere.
The Linux native build requires the repository's pinned Flutter 3.48 toolchain:
the locally installed 3.44.1 lacks `fl_dart_project_set_enable_impeller`, already
used in the unchanged Linux runner.
