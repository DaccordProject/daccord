# Validation evidence

This records completed checks, not intended platform support. Physical iOS
validation remains an open release gate because no device is available.

| Gate | Evidence |
|---|---|
| Dart VM bounded runtime | 8 tests passed: reference games, malformed modules, denied instructions, output/fuel/depth limits, exact i32 overflow and grant revocation |
| Browser bounded runtime | The same 8 tests passed in Chromium headless under both Dart JavaScript and Dart WASM compilers |
| Signature/provenance | Flutter package test passed: exact payload, pinned identity, signature/key tampering, revocation and unsupported platform |
| Turn notifications | Two Flutter tests passed: server isolation, revisions/dismissal, cleanup and bounded state |
| Responsive/keyboard canvas | Actual chess WASM frame tested at mobile/desktop widths; spectator controls tested |
| Widget host lifecycle | Covered-route shutdown, revalidation on return, account switch and stale package response tests passed |
| Curated master directory | Full tests, contract tests and Docker CI passed; master PR #2 merged |
| Community server | Full SQLite/PostgreSQL suites, lint and Docker CI passed; PRs #90/#91/#92 merged, issue #88 closed; special chess rules and five repeated PostgreSQL live-session contention runs pass |
| Directory to chess/live Pong | Real master + community server + client SDK/signature/guest host test passed, including three fresh runs with the final chess engine; the private master CI stack gate also passed; server integration covers authenticated sockets and reconnect |
| Flutter Web application | Both JavaScript and WASM release compilations passed; all 7 Arcade widget/signature/alert tests also pass in Chromium in both Flutter modes; published Web artifacts remain JavaScript |
| Desktop/mobile smoke builds | Web JavaScript, Android, Linux, Windows, macOS and unsigned iOS builds passed; Apple jobs use the release Xcode selection and a scoped AVFoundation header workaround |
| Linux application | All 7 signed-package, canvas, input, alert and lifecycle host checks passed as a native Linux application, alongside app-shell, render, two-client and actual Pong checks |
| Android emulation | Real Pong input, 250 ms budget and lifecycle checks pass on API 35 x64 in profile mode |
| iOS physical device | Open by user request; no device is available |
| macOS application | All 7 Arcade host checks, a real secure-credential round trip and actual Pong checks pass on macOS 15.7.9 ARM64 |
| Windows application | All 7 Arcade host checks and actual Pong checks pass on the Windows 2022 runner |

Run `dart test` and `dart test -p chrome` in `packages/experience_runtime`,
`flutter test test/features/experiences` from the client root, and
`cargo test --test experiences` in the coordinated community server. The
reference package generator must leave tracked packages unchanged.

Do not mark client issues #360 or #365 complete without physical iOS validation.
Issue #397 is complete with the recorded desktop, Android emulator and browser
application runs below. A unit suite or a build alone does not satisfy these
gates. Operators keep experiences off by default until keys are provisioned and
these gates are satisfied for their supported clients.

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
input budget is measured in the automated local-fixture runs below. Physical
iOS validation must repeat the device checks.

Final client validation is recorded in [client CI run 36853448421](https://github.com/DaccordProject/daccord/actions/runs/36853448421).
The native UI job explicitly runs `integration_test/arcade_host_test.dart`;
the browser jobs run all 7 feature checks in both Flutter compiler modes.
[Coordinated stack run 36853534240](https://github.com/DaccordProject/accordmasterserver/actions/runs/36853534240)
passed against client `ae84e0884528c7fd7c7aebcffdd339a0424b8c6d` and community
server `001c215653ad3718c48730dfa53251bcf433d20b`.
All six smoke-build jobs passed in [platform build run 36852480998](https://github.com/DaccordProject/daccord/actions/runs/36852480998).
That earlier run's browser harness and transient Maven failures were corrected
and passed in the final client CI; the individual platform build results are
the compilation evidence. The live application checks below supplement these
builds. Physical iOS remains unvalidated.

## Live Pong UI and input latency

The coordinated manual workflow also runs the real game screen on Linux,
macOS, Windows, Android emulation and both Flutter browser compiler modes. It renders the
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

### Recorded application results

The following runs used Flutter `3.48.0-0.5.pre` on 2026-10-01. Each passing
Pong run rendered the reviewed guest, delivered a host paddle tap to the peer,
measured five peer inputs to the next Flutter frame, and completed route
pause/resume, peer disconnect/reconnect and owner disable. The reported p95 is
the largest of those five samples. These are local-fixture measurements. Desktop
and browser runs use debug/test mode; Android uses optimized profile mode. They do not establish a WAN guarantee
or physical-device performance.

| Application target | Input-to-frame p95 | Evidence |
|---|---|---|
| Linux, Ubuntu 24.04.5 / Xvfb | 113 ms | [Passing application job](https://github.com/DaccordProject/accordmasterserver/actions/runs/36882718762/job/110438278087) |
| Browser JavaScript, Chromium / Ubuntu | 154 ms | [Passing browser job](https://github.com/DaccordProject/accordmasterserver/actions/runs/36882718702/job/110438270960) |
| Browser WASM, Chromium / Ubuntu | 66 ms | [Passing browser job](https://github.com/DaccordProject/accordmasterserver/actions/runs/36882718702/job/110438271209) |
| macOS 15.7.9, ARM64 / Xcode 26.3 | 74 ms | [Passing native host, credential and game run](https://github.com/DaccordProject/accordmasterserver/actions/runs/36869105937) |
| Windows Server 2022, x64 | 154 ms | [Passing native host and game run](https://github.com/DaccordProject/accordmasterserver/actions/runs/36870533014) |
| Android API 35 x64, 720x1280 / 240 dpi, profile | 178 ms | [Passing emulator game run](https://github.com/DaccordProject/accordmasterserver/actions/runs/36884898002) |
| Physical iPhone / iPad | Unvalidated | No device is available; #360 and #365 remain open |

The community server revision was
`a00751ba02aed7ded0246bc7b1e43f3362616b75`, merged in
[PR #92](https://github.com/DaccordProject/accordserver/pull/92). Linux, browser and
Android runs used client `e496ce178f1005eb06e1b66f7f1e012ef77739a6`. macOS used
`6bab215f073381cc989d42c72051861a894fb987`; Windows used
`ce85d461f846a159fc0bd6049cf8f24cb44f6558`. The same gameplay and
lifecycle checks run across these revisions. Later changes fix native test
harnesses, launcher resolution and macOS development signing/storage, then add
per-input diagnostics and the profile driver without relaxing the 250 ms budget.

[Client PR #405](https://github.com/DaccordProject/daccord/pull/405) is merged;
[final client CI](https://github.com/DaccordProject/daccord/actions/runs/36870500418)
passes full beta/stable suites, SDK, protocol, both browser hosts and native
Linux UI/render/two-client checks. The
[final server CI](https://github.com/DaccordProject/accordserver/actions/runs/36862167679)
passes SQLite, PostgreSQL, lint and Docker, including five additional fresh
PostgreSQL experience-test repetitions.

[Client PR #406](https://github.com/DaccordProject/daccord/pull/406) adds the
fixture-scoped ADB reverse mapping and profile driver. Its
[full client CI](https://github.com/DaccordProject/daccord/actions/runs/36881565333)
passes. The latest Linux/browser results repeat the complete shared game test
after adding latency diagnostics.

Android's first debug run rendered real Pong and delivered inputs but failed
the budget at 584 ms. The first profile run also failed at 424 ms, while route
pause/resume, peer reconnect and disable passed. These failed runs remain
recorded: [debug](https://github.com/DaccordProject/accordmasterserver/actions/runs/36876815561),
[profile](https://github.com/DaccordProject/accordmasterserver/actions/runs/36881638154).
The coordinator now builds the fixture-specific APK, stops Gradle and launches
that binary without rebuilding. It uses a 720x1280 / 240 dpi viewport to bound
software-rendering load on the two-core runner; it retains all five input
samples and the original budget.

The final Android run used master coordinator
`008d7d05fc4991579f04b0056cbb12c637a423bd`, a two-core Google APIs emulator
with SwiftShader, and the same community-server/client revisions above. It
reported five inputs in order: `[178, 132, 62, 137, 96]` ms. The first input is
included; no samples were discarded. Route pause/resume, peer disconnect/
reconnect and owner disable all passed. The complete run, including directory
contract tests and Docker, is green.
