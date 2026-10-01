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
| Desktop/mobile smoke builds | Web JavaScript, Android, Linux, Windows, macOS and unsigned iOS builds passed; Apple jobs use the release Xcode selection and a scoped AVFoundation header workaround |
| Linux application | All 7 signed-package, canvas, input, alert and lifecycle host checks passed as a native Linux application, alongside the existing app-shell, render and two-client checks |
| Android device | Pending physical-device run |
| iOS physical device | Requires a physical device and macOS signing environment |
| macOS / Windows application | Release builds passed; interactive application and latency matrix still pending |

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

Final client validation is recorded in [client CI run 36853448421](https://github.com/DaccordProject/daccord/actions/runs/36853448421).
The native UI job explicitly runs `integration_test/arcade_host_test.dart`;
the browser jobs run all 7 feature checks in both Flutter compiler modes.
[Coordinated stack run 36853534240](https://github.com/DaccordProject/accordmasterserver/actions/runs/36853534240)
passed against client `ae84e0884528c7fd7c7aebcffdd339a0424b8c6d` and community
server `001c215653ad3718c48730dfa53251bcf433d20b`.
All six smoke-build jobs passed in [platform build run 36852480998](https://github.com/DaccordProject/daccord/actions/runs/36852480998).
That earlier run's browser harness and transient Maven failures were corrected
and passed in the final client CI; the individual platform build results are
the compilation evidence. These results do not complete the physical-device
or end-to-end Pong latency gates.

## Live Pong UI and input latency

The coordinated manual workflow also runs the real game screen on Linux,
Android emulation and both Flutter browser compiler modes. It renders the
reviewed Pong guest, drives the host paddle control, measures peer input to the
next Flutter frame, covers/returns to the route, disconnects/reconnects the peer
and disables the installed game. The reference target is p95 <= 250 ms on the
local fixture; this does not assert a latency bound for arbitrary WAN links.

```sh
python3 tools/experiences/run_fixture.py \
  --server-bin ../accordserver/target/debug/accordserver \
  --master-bin ../accordmasterserver/target/debug/accordmasterserver \
  -- flutter test integration_test/pong_session_test.dart -d linux \
     --dart-define=ACCORD_EXPERIENCE_TEST_URL={server_url}
```

For an Android emulator, pass `--android-device emulator-5554` to the fixture
helper, select `-d emulator-5554` and pass `--flavor github`. The helper uses
ADB reverse to keep the fixture on device loopback, preserving the SDK's HTTPS
requirement for remote servers, and removes its port mapping during cleanup.
Use `flutter drive --profile --driver test_driver/experiences.dart
--target integration_test/pong_session_test.dart` for the Android latency gate.
Profile mode measures optimized application code without debug/JIT checks;
emulator results establish the automated fixture gate, not physical-device
performance. The test logs inputs in order and measures the first input too,
without discarding slow samples. Lifecycle checks run before the latency
assertion so a budget failure also reports whether revocation works.
The helper substitutes the temporary server URL into the Dart define; the
new test skips without that define so ordinary UI suites never use an
unprovisioned directory. Physical iOS validation remains open by user request.
