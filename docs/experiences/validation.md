# Validation evidence

This records completed checks, not intended platform support. Physical-device
checks remain release gates for the overall plugin-system issues.

| Gate | Evidence |
|---|---|
| Dart VM bounded runtime | 8 tests passed: reference games, malformed modules, denied instructions, output/fuel/depth limits, exact i32 overflow and grant revocation |
| Browser bounded runtime | The same 8 tests passed in Chromium headless under both Dart JavaScript and Dart WASM compilers |
| Signature/provenance | Flutter package test passed: exact payload, pinned identity, signature/key tampering, revocation and unsupported platform |
| Turn notifications | Two Flutter tests passed: server isolation, revisions/dismissal, cleanup and bounded state |
| Responsive/keyboard canvas | Actual chess WASM frame tested at mobile/desktop widths; spectator controls tested |
| Widget host lifecycle | Covered-route shutdown, revalidation on return, account switch and stale package response tests passed |
| Curated master directory | Full tests, contract tests and Docker CI passed; master PR #2 merged |
| Community server | Full SQLite/PostgreSQL suites, lint and Docker CI passed on the final implementation; PRs #90/#91 merged, issue #88 closed; special moves and draw rules also pass |
| Directory to chess/live Pong | Real master + community server + client SDK/signature/guest host test passed, including three fresh runs with the final chess engine; the private master CI stack gate also passed; server integration covers authenticated sockets and reconnect |
| Flutter Web application | Both JavaScript and WASM release compilations passed; all 7 Arcade widget/signature/alert tests also pass in Chromium in both Flutter modes; published Web artifacts remain JavaScript |
| Desktop/mobile smoke builds | Android, Linux and Windows passed; Apple jobs use the release Xcode selection and a scoped AVFoundation header workaround |
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

The Curated directory to multiplayer host workflow runs in the private master
repository, whose token can read that source. It builds immutable community and
client revisions, publishes the exact reference packages on a temporary master,
then verifies the client SDK and WASM host against the actual community server. To reproduce with local builds:

```sh
python3 tools/experiences/run_fixture.py \
  --server-bin ../accordserver/target/debug/accordserver \
  --master-bin ../accordmasterserver/target/debug/accordmasterserver \
  -- flutter test integration/experiences_test.dart --reporter expanded
```

The helper creates isolated databases, known test-only signing keys, local
ports and temporary processes, and removes them after the test command exits.

## Native device host checks

Run the same signed-package, canvas, input, alert and lifecycle tests on an
actual Flutter device (these use an isolated mock transport):

```sh
flutter test integration_test/arcade_host_test.dart -d linux
flutter test integration_test/arcade_host_test.dart -d <physical-device-id>
```

A passing simulator or unsigned build must be recorded separately from a
physical iOS run. Record commit, device/OS, build mode and measured startup,
render/input responsiveness and cleanup behavior. For the real-time gate, use
two clients against the reviewed directory/community fixture: join Pong, move
both paddles, disconnect/reconnect, cover and restore the page, resign and
then disable the game. Record RTT, time from input to displayed snapshot and
frame timing on desktop, mobile and both Web modes. The server has a 50 ms
snapshot cadence and the host coalesces inputs at 20 Hz; the target end-to-end
input budget in the authoring contract still requires those measurements.
