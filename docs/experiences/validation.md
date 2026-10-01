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
| Community server | Full SQLite/PostgreSQL suites, lint and Docker CI passed on the final implementation; PR #90 merged, issue #88 closed |
| Directory to chess/live Pong | Signed fake directory + real HTTP/router/database + two authenticated WebSocket clients passed |
| Flutter Web application | JavaScript release build passed; the app remains a JavaScript artifact even though guests are WASM modules |
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

The blocking Curated directory to multiplayer host CI job builds both server
repositories at immutable commits, publishes the exact reference packages on a
temporary master, then verifies the client SDK and WASM host against the actual
community server. To reproduce with local builds:

```sh
python3 tools/experiences/run_fixture.py \
  --server-bin ../accordserver/target/debug/accordserver \
  --master-bin ../accordmasterserver/target/debug/accordmasterserver \
  -- flutter test integration/experiences_test.dart --reporter expanded
```

The helper creates isolated databases, known test-only signing keys, local
ports and temporary processes, and removes them after the test command exits.
