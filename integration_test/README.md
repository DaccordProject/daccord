# UI end-to-end tests

Layer 2 of #217: the **real app shell**, on a **real device**, against a **real
`accordserver`**.

`integration/` (layer 1) proves the caches update. These prove the *screen*
does — the class of bug where the data is right and the UI never shows it: a
list that doesn't rebuild, a route that doesn't resolve, a channel that renders
empty.

```bash
flutter test integration_test/ -d linux                      # whole suite
flutter test integration_test/messaging_ui_test.dart -d linux # one file
xvfb-run -a flutter test integration_test/ -d linux           # headless
```

`flutter test` on its own does **not** pick these up — it only walks `test/`.

## How it works

The server fixture and account harness are shared with layer 1
(`../integration/support/`, documented in `integration/README.md`): same
resolution order for finding a server, same skip-with-a-reason behaviour when
there isn't one, same registration budget.

What's different here is the tree. `harness.scopeFor(account, child: ...)`
wraps a widget in a `ProviderScope` that reports the account as signed in, so
tests pump the app's own `MainWindow` — real router, real theme, real screens —
and navigate with `routerController.go(...)`.

Because these run as a real app, `path_provider` and friends work. The harness
still points Hive at a throwaway directory rather than calling the app's
`setupHive()`, so a test run can't touch your actual profile data.

## Three things that will bite you

- **Pump order.** Attach the event handler to the tree's container *before* the
  gateway connects. The shell hydrates its space and channel lists from the
  READY payload, so a handler attached afterwards misses it and the shell
  renders empty. `pumpApp` cycles the connection for exactly this reason.
- **`pumpAndSettle` doesn't wait for the network.** It returns as soon as
  animations stop, which is long before the server answers. Use `pumpUntilFound`.
- **Message bodies aren't `Text`.** They go through the markdown renderer, so
  assert with `find.text('...', findRichText: true)`.

## Seeded settings

`harness.setupHive()` answers the things a first launch would otherwise put on
screen or on the network: the onboarding tour, the release-notes dialog, the
error-reporting consent prompt, notifications, and `autoUpdateCheck`.

That last one matters more than it looks. With the updater live, the app reaches
the real release endpoint mid-test and starts staging a download; the failure
lands as an unhandled async error *after* the test body finishes, and the runner
attributes it to whichever test is running. It presented as "the first test in
the process fails, later ones pass" and cost a long detour — if you see that
shape again, suspect background work escaping the test body before you suspect
the widget under test.

## CI

Runs as its own non-blocking job (see `ci.yml`) on Linux under `xvfb`, against
the `ghcr.io` server image. Separate from the unit gate so a server-side or
display problem can't wedge merges.
