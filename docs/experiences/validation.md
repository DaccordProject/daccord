# Validation evidence

This records completed checks, not intended platform support. Physical-device
checks remain release gates for the overall plugin-system issues.

| Gate | Evidence |
|---|---|
| Dart VM bounded runtime | 8 tests passed: reference games, malformed modules, denied instructions, output/fuel/depth limits, exact i32 overflow and grant revocation |
| Browser bounded runtime | The same 8 tests passed in Chromium headless (Dart compiled to JavaScript) |
| Signature/provenance | Flutter package test passed: exact payload, pinned identity, signature/key tampering, revocation and unsupported platform |
| Turn notifications | Two Flutter tests passed: server isolation, revisions/dismissal, cleanup and bounded state |
| Responsive/keyboard canvas | Actual chess WASM frame tested at mobile/desktop widths; spectator controls tested |
| Curated master directory | Full tests, contract tests and Docker CI passed; master PR #2 merged |
| Community server | Full SQLite/PostgreSQL suites, lint and Docker CI passed on commit 602a202; expanded lifecycle tests are gated on the follow-up commit |
| Directory to chess/live Pong | Signed fake directory + real HTTP/router/database + two authenticated WebSocket clients passed |
| Flutter JavaScript / WASM builds | Pending |
| Linux application | Pending |
| Android device | Pending physical-device run |
| iOS physical device | Requires a physical device and macOS signing environment |
| macOS / Windows application | Pending platform build evidence |

Run `dart test` and `dart test -p chrome` in `packages/experience_runtime`,
`flutter test test/features/experiences` from the client root, and
`cargo test --test experiences` in the coordinated community server. The
reference package generator must leave tracked packages unchanged.

Do not mark client issues #360, #365 or #397 complete based on a native unit
suite or a build alone: their device, lifecycle and portability criteria still
need recorded application runs. Operators keep experiences off by default until
keys are provisioned and these gates are satisfied for their supported clients.
