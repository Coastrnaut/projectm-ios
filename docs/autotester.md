# Automated device testing: how it works here and what we learned

Maintained file (owner rule 13): update it whenever device automation changes or a lesson is learned. Notes for
this repository's future work and for steering other iOS repositories. They come from the QA-011 final
device stage (2026-11-15), when the hands-on owner sessions were turned into automated tests on real devices
(D1 iPhone 15, D2 iPad Pro M5, D3 iPad A16). Simulator results are never device evidence here; everything below
runs on hardware.

## The pieces

| Piece | Where | What it does |
|---|---|---|
| Matrix runner | `scripts/run_device_matrix.py` | Per device: OS build, app build and commit, signing (certificate type and team only), every scripted case, artifacts with SHA-256, one signed run record (`docs/test-reports/qa-011/runs/<device>/<run>/record.json`). `--dry-run` writes nothing; `--simulator` rehearses (never evidence). |
| In-app automation | `Apps/projectM-iOS/Automation/AutomationRunner.swift` | `PROJECTM_AUTORUN=<mode>`: measurement modes (perf001, perf012, sc009 …) write a JSON report to Documents and exit. Compiled only under `DEBUG || PROJECTM_AUTOMATION`. |
| Device test host | `DeviceTests.yml` (XcodeGen, includes `project.yml`) | App-hosted test bundles that compile package test folders, so package suites run on a device; the `DeviceAcceptance` scheme holds the on-device UI tests. The main project and scheme are unchanged. |
| On-device UI tests | `Apps/projectM-iOS/DeviceUITests/` | The owner sessions' steps as XCUITest on the device: launch with settings, play music, read the performance overlay, take and measure screenshots. One `DEVICE-ACCEPT {json}` line per measurement. |
| Music fixture | `scripts/make_music_fixture.py` | A deterministic, generated 60 s stereo track (120 BPM drums, bass, chords, quiet intro, loud chorus, breakdown). No licence. Copied into the app's Documents before a run. |
| Acceptance record | `scripts/device_acceptance_report.py` | Turns a run's log into `docs/test-reports/qa-011/acceptance/<device>-<session>.json` and `.md` (every measurement, every test, the log's hash). |
| Inventory and checklist | `scripts/qa011_inventory.py` | Every open `{device}`/`{owner}` task, classified (scripted, person, owner-only) and batched into owner sessions. |
| Release manifest | `scripts/release_manifest.py` | One commit's evidence: feature evidence, hashed reports, verified device records, gaps. |

## Running it (D1 example)

```bash
python3 scripts/make_music_fixture.py                               # Build/fixtures/music-fixture.m4a
xcodegen generate --spec DeviceTests.yml
xcodebuild build-for-testing -project ProjectM-DeviceTests.xcodeproj -scheme DeviceAcceptance \
  -destination 'platform=iOS,id=<hardware UDID>' -derivedDataPath Build/device-acceptance -allowProvisioningUpdates
xcrun devicectl device install app --device <devicectl id> Build/device-acceptance/Build/Products/Debug-iphoneos/projectM-iOS.app
python3 scripts/install_test_fixtures.py --device all              # copies it onto D1-D3 (or by hand:)
xcrun devicectl device copy to --device <devicectl id> --domain-type appDataContainer \
  --domain-identifier org.projectmios.ProjectMiOS --source Build/fixtures/music-fixture.m4a \
  --destination Documents/music-fixture.m4a
xcodebuild test-without-building -project ProjectM-DeviceTests.xcodeproj -scheme DeviceAcceptance \
  -destination 'platform=iOS,id=<hardware UDID>' -derivedDataPath Build/device-acceptance \
  -resultBundlePath Build/device-acceptance/<name>.xcresult -only-testing:projectM-iOSDeviceUITests/<Class> \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 900 > <log> 2>&1
python3 scripts/device_acceptance_report.py --log <log> --device D1 --session B01
```

The hardware UDID (`hardwareProperties.udid`) is what `xcodebuild -destination` needs; `devicectl` takes its own
identifier. Both come from `xcrun devicectl list devices --json-output <file>`.

## Human testing group (tests that can prompt)

Owner rule 14 (2026-11-16): any test that can raise a prompt needing a person runs in this group, together, with the
owner present and told first; never in an automated batch. Automated batches assume these were answered.

| Test | Prompts | Notes |
|---|---|---|
| `PermissionPrimerDeviceTests.testA_Microphone` | Microphone | launch with `-autostart microphone` |
| `PermissionPrimerDeviceTests.testB_Camera` | Camera | chooses Camera in Settings (the camera never starts at launch) |
| `PermissionPrimerDeviceTests.testC_LocalNetwork` | Local Network | OSC on; check it really asks (see the camera lesson) |
| Pickers, purchase and share sheets, Siri, calls, AirPlay, headphones | system UI | listed in the person-only section |

Run once per device after a fresh install (a reinstall over the app keeps the answers):

```bash
xcodebuild test-without-building -xctestrun <copy>/…xctestrun -destination platform=iOS,id=<UDID> \
  -only-testing:projectM-iOSDeviceUITests/PermissionPrimerDeviceTests
```

The camera B06 tests stopped on D1 at the camera prompt mid-run (2026-11-16) because the first primer set Camera at
launch and so never asked; the prompt then appeared inside the automated batch. That is what this group prevents.

## Lessons learned

### Devices and connections

- **Wireless works.** Once a device is paired with "Connect via network", `devicectl` and `xcodebuild` install, launch,
  copy and run UI tests over Wi-Fi. A cable is needed only for power on long runs (a charger does as well) and for
  Airplane Mode steps. Check `xcrun devicectl device info details --device <id>`: `tunnelState: connected`.
- **A locked device stops everything.** `xcodebuild` fails with "Unlock <name> to Continue"; `devicectl` launches fail
  with "Locked". Ask once for Auto-Lock **Never** per device for the session. `xcrun devicectl device info lockState`
  reports `passcodeRequired`.
- **"Timed out while enabling automation mode"** (XCTFuture 1000) stopped D1's UI tests four times in a row on
  2026-11-15 although the device was connected, unlocked (`lockState`: `passcodeRequired` false) and showed no prompt.
  Waking the device did not clear it, and `devicectl device process terminate` cannot stop the device's
  `testmanagerd` (a protected system process). Package test bundles (no UI automation) are not affected. What is
  left is a person at the device: Settings › Developer › turn "Enable UI Automation" off and on, or restart the
  device and unlock it. Don't loop retries; one retry, then ask, and run non-UI work meanwhile.
- **The automation-mode timeout cleared with the Developer toggle** (2026-11-15): on D1, turning "Enable UI
  Automation" off and on fixed it at once; D2 showed the same timeout until the owner signed it in, then ran.
- **A test that crashes the app on purpose** (PERF-010 "Crash now"): XCTest records "<bundle> crashed" as an issue
  asynchronously, often after the relaunch, so `XCTExpectFailure` around the tap misses it. Override
  `record(_:)` in that test class and drop only that issue while a flag is set (B03RecoveryDeviceTests).
- **Long Settings lists in a sheet:** a swipe down at the top of the list dismisses the sheet. To get back to the
  top from a deep section (`-uitestSettingsSection storage`), tap the status bar (normalized y 0.01), then fall
  back to slow swipes on the list, guarded by the navigation bar still existing. `app.debugDescription.prefix(n)`
  shows the views under a sheet first, so a truncated dump can hide the sheet.
- **Parallel devices from one build:** copy `Build/<derived>/Build/Products` to a per-device folder and run
  `xcodebuild test-without-building -xctestrun <copy>/…xctestrun`, so rebuilding for one device never disturbs
  another device's run.
- **Simulator UI tests on a device:** the DeviceAcceptance scheme also hosts `projectM-iOSUITests`, so an existing
  simulator test can run on D1-D3 (`-only-testing:projectM-iOSUITests/<Class>`). Most run as written; the ones that
  failed (2026-11-15) failed for screen size, not app faults. A lazy list builds rows only near the screen (Photo below
  the fold on the iPhone), and on a 13-inch iPad Settings is a 400 pt side panel that a window-wide drag does not
  scroll. Swipe the list itself (`app.collectionViews.firstMatch.swipeUp(velocity: .slow)`) until the element exists
  and is hittable; never swipe down at the top of a sheet.
- **Each device needs its own UI-automation reset:** D1, D2 and D3 each showed the automation-mode timeout on their
  first UI test run of the day; the Developer toggle (D1) or signing the device in (D2) cleared it.
- **After closing or annotating any QA-011 task, run `python3 scripts/qa011_inventory.py`** and commit the regenerated
  `device-inventory.json` and `owner-checklist.md` with it; CI's script tests fail on a stale inventory (run
  43799100657, 2026-11-15). Docs-only `[skip ci]` pushes hide this until the next code push.
- **Motion checks need several samples:** one pair of screenshots 1 s apart lands in a quiet passage of the music
  often enough to fail (D1, 2026-11-15: 0.002, then 0.022, then 0.003 over 15 s with music verified active).
  Take three pairs a few seconds apart and assert on the largest. A live status comes from the performance
  overlay's label, not `announcementProbe` (which keeps the last announcement).
- **Typed settings must survive lazily created settings objects:** `-uitestResetNotice` made ten settings types clear
  their keys in their own init, and several are created lazily, after `-uitestDefaults` wrote the typed values. A
  Draft or Portrait recording asked for by a device test silently came out at Standard and Match screen, and a loose
  check (portrait = taller than wide) passed on an iPad whose screen is already 3:4. Resets now go through
  `UserDefaults.removeForUITestReset`, which keeps typed keys. Assert values that prove the setting applied (Draft
  is H.264 at a 1280 long side; Portrait is 9:16), never a shape the default could also have.
- **Test-only defaults keys stay inside `#if DEBUG`:** the privacy key scan (`test_every_stored_defaults_key_is_allowed`)
  treats any defaults key named outside DEBUG code as stored by the shipping app (CI run 43804165117).
- **Thresholds per kind of visual:** a line visual (oscilloscope) covers about 1 % of the screen, so "draws" uses
  `minimumDraw: 0.005` there; filled visuals keep 0.02.
- **Device audits find what the simulator does not:** on D1 the Dynamic Type audit flagged two `Label`s that wrapped
  under their icon at AX3/AX5 ("Lock scene", "Import Folder or Archive…"; fixed with `IconTitleRow`), and its contrast
  audit (iOS 27.0.1) flagged accent-coloured list buttons measured at 5.8:1 that pass on the 27.2 simulator. Triage
  each device failure (app finding, environment, harness) before changing code; a read-only agent can do it from the
  log and the result bundle's screenshots.
- **Pin the appearance in audits that measure colour:** D1's Appearance is Automatic, so at night (D1 at 23:57) the app
  ran in dark mode while the same tests had run in light mode hours earlier. Contrast results then change with the
  time of day. Accessibility suites should pin light or dark per run, or report which one ran.
- **Opening Settings at a section beats flinging:** `-uitestSettingsSection <id>` (storage, text) turned 125 s
  timeouts into 10 s passes on D1 and D2 for Storage, Licenses and the Text rows.
- **Permission prompts stay a person's tap, once per device:** `PermissionPrimerDeviceTests` makes iOS show the
  microphone, camera and Local Network prompts one after another and waits (up to 180 s each) for a person to answer;
  it never taps them. Trigger each one the way a user does: the camera never starts at launch (CAM-001-R11), so a
  launch argument asked nothing and the primer wrongly reported "already answered" on D1; the prompt then appeared
  mid-test and covered the app for every later test. The primer now chooses Camera in Settings. A granted permission survives reinstalling the same app, so the camera, microphone
  and OSC device tests run unattended afterwards.
- **Every device needs the fixtures:** D3 stayed on "Choose source" in every test (the app said the fixture could
  not be found) because the music fixture had been copied onto D1 and D2 only. `scripts/install_test_fixtures.py
  --device all` copies it; the tests now fail with that instruction when the app lands on the source chooser.
- **Task notes start with " — ":** `qa011_inventory.py` reads a task's devices from its text before the first " — ";
  a note appended without it that names D2 or D3 widens the task's device list (2026-11-16: three D1 tasks gained D3).
- **Test media persists in the app between launches:** imported tracks stay in the audio library, so "play the first
  imported track" played the left-only fixture in the inverted-phase test once both had been imported on D1 (r 0, no
  warning). The import hook now plays the track this launch imported (by file name).
- **GPU benches on the devices (B13):** `MaterialFrameCostBench` (SHD-001), `LayerStackFrameCostBench` (CMP-002, CMP-001)
  and `ProjectMStackFrameCostBench` (projectM at the bottom) run in the Release `DeviceTests` bundles, gated by
  `SHD001_BENCH`, `CMP002_BENCH`, `CMP001_BENCH` (set them as `TEST_RUNNER_<NAME>=1` on the xcodebuild command), and
  print `BENCH-RESULT {json}` lines (GPU and wall median and p95 over 600 frames at the native screen size). Release
  device-test builds need `ENABLE_TESTABILITY=YES` (the matrix passes it); without it every `@testable import` fails
  to resolve. projectM draws in ANGLE's own command buffers, so its GPU figure omits that draw: use the wall time.
- **The Mac's Local Network privacy blocks some senders:** the OSC driver's Python socket got "No route to host" to the
  iPhone while `ping`, `/usr/bin/nc`, Perl and Ruby reached it; macOS grants Local Network access per program. Rather
  than change a Mac privacy setting, `scripts/osc_device_driver.py` hands each datagram to a system Perl process.
  Python's resolver also missed `<name>.local`; the driver falls back to `dscacheutil`.
- **Run the script tests before any push that closes tasks:** closing CMP-001-T20 left the matrix case it drove on no
  device and failed CI (run 43918880546) after a `[skip ci]`-free push of docs; cases now keep D1 (or their default
  devices) once their tasks close. UDP over Wi-Fi also loses single datagrams (the first to a host, or one at the end
  of a flood): the OSC driver sends closing values three times.
- **Tap a SwiftUI Toggle at its switch, not its centre:** `app.switches["id"].tap()` in a Settings list hit the row's
  label on D1 and the switch never changed (OSC-007's after-Stop check, 2026-11-18). Tap
  `coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))` and check `value` changed. Rows shown only while a
  setting is on (OSC's Test value) vanish with it: turn the setting back on before reading them.
- **Pass each `-only-testing:` as its own argument:** two filters quoted into one shell argument ran zero tests and
  still printed `** TEST EXECUTE SUCCEEDED **`; check "Executed N tests" with N > 0.
- **Instruments from the command line:** `xcrun xctrace record --template <name> --device <UDID> --time-limit 60s
  --output x.trace --launch -- <bundle id> <launch arguments>` launches the installed Debug app with test hooks. Never
  wrap it in a short `timeout`: saving a 60 s Allocations trace takes minutes (6.7 GB), and a killed save leaves an
  unreadable trace. `xctrace export --toc` lists the tables; Metal System Trace exports `metal-gpu-intervals` and
  `metal-current-allocated-size`, but Allocations exports no allocation table, so memory growth is checked with the
  DEBUG `memoryProbe` (`footprintMB=<n>` each second with `-uitestDiagnostics`) instead.
- **Recording diagnosis hooks (DEBUG):** `recordingFacts` reports `busy=` (gate full), `notReady=` (the writer refused)
  and `rateSkipped=` besides written and dropped slots; `-uitestRecordingNoAudio` records without an audio track;
  `-uitestAutoRecordSeconds <n>` starts a recording 4 s after launch and stops it n s later, so `xctrace --launch` can
  trace one without taps. `xctrace --attach` could not find the app on D3 by pid or name (2026-11-18): launch it
  through xctrace instead.
- **Run devices one at a time when the owner asks**, and never start a device the owner has not prepared (Auto-Lock,
  unlocked). Report each device idle at once with what passed, what did not and why (owner rule 11).

### Xcode and the device test host

- **Package tests cannot run on a device by themselves**: "Tool-hosted testing is unavailable on device destinations".
  Compile the package test folders into test bundles hosted in the signed app (`DeviceTests.yml`). Avoid
  `Bundle.module` in tests; this repository has none, which made it possible.
- **Tests that read the source tree through `#filePath` fail on a device.** Bundle the folders they read as folder
  resources and fall back to the bundle when the source path is missing (`GoldenPaths.packageRoot`,
  `SceneMigrationMatrixSupport.legacyDirectory`). A file kept as identical copies in several packages must stay
  identical: a meta-test checks it (CI caught a one-copy edit).
- **Release builds of test bundles compile only DEBUG-free tests.** Any test using a `#if DEBUG` member must itself be
  `#if DEBUG` (fault injection, fence holding); build every bundle in Release once on the Mac before a device run.
- **Linking in the device project differs from SwiftPM.** A test bundle needs each package it imports as a direct
  dependency (FlashSafety, ANGLE's EGL frameworks with `embed: false`). Declaring a package at project level can change
  how the app links it: add it to the app target too (`DeviceTests.yml` merges a dependency into `projectM-iOS`).
- **An app target that compiles a whole folder picks up new test folders**: exclude them (`DeviceUITests/**`).
- **An unfiltered test case on a device ran every bundle in the scheme.** Map each case to its own bundle.
- **Parse the run total**: XCTest prints "Executed 134 tests, with 3 tests skipped and 0 failures"; the last
  "Executed" line can be a sub-suite.

### Making the tests measure the right thing

- **Check the screenshots before trusting a pass.** The first B01 run "passed" frame-rate checks while the
  screenshots showed the visuals reacting to silence and the effects off. Look at one screenshot per test kind.
- **The bundled reference track is a test signal, not music** (tones with an 8 s silent gap). Visuals that follow
  music barely move on it. Generate a music fixture and play it (`-uitestImportAudio <file in Documents>` plus
  `-uitestPlayImported YES`); assert "Active audio" before measuring.
- **Launch arguments arrive as strings.** `-key value` reaches settings that read `bool(forKey:)`/`integer(forKey:)`,
  but not settings that read `object(forKey:) as? NSNumber`. Pass typed values through a DEBUG hook
  (`-uitestDefaults <json>`) that writes them before any setting is read and removes the previous launch's keys.
  Settings kept as Codable JSON data (MED-011's clock) take `{"key": {"$json": <value>}}`, which the hook stores as
  JSON data. The DEBUG `recordingFacts` probe also reports `bytes=<n>`, the recorded file's size (-1 when gone).
- **Seed media in the app, not through a picker.** `-uitestSeedVideo hd30` (1920 × 1080, 30 fps, 30 s) and
  `-uitestSeedVideo long120` (640 × 360, 2 min) write flat-grey H.264 clips in the app and import them through the
  normal store (`UITestVideoFixture`, DEBUG), so no fixture file is installed (MED-005-T20, `B13MediaDeviceTests`).
  The DEBUG probe `videoReverseMemory` reads `peak=<bytes> budget=<bytes>` (the reverse cache's peak accounted bytes
  and the device class budget); `memoryProbe` gives the process footprint each second.
- **Package suites with a device host belong in the matrix.** PRE-012's worst-case preset shapes at the static limits
  (and twice them) run as `xctest-pre012-limits` (ANGLEDeviceTests, `PresetTrialRunnerTests`), not as UI tests.
- **Saved state overrides settings at launch.** The app restores the last committed scene (SCN-002), whose effect
  values replaced the test's settings. Start every test clean (`-uitestResetNotice` clears settings, media and the
  committed scene) and then apply the test's settings.
- **Prove the setting took effect.** For each effect, compare the picture with the effect off; a pass on frame rate
  alone proves nothing if the effect never turned on. Use a test image with detail (the `pattern` photo fixture:
  colour and grey bars crossed with a checkerboard); a flat colour hides blur, mosaic and hue.
- **Measure still-picture checks away from moving things.** The performance overlay's counters change every second
  and the photo visual draws a music-reactive spectrum: measure shimmer, grain and crawl in a corner region.
- **Mind sampling and alignment.** Sampling every 8th pixel missed 1-pixel scanlines (aliasing); sample every pixel
  for thin features. 8 px mosaic blocks aligned with an 8 px checkerboard change it very little; pick thresholds per
  case. Read the spec's geometry before choosing a region (a vignette's clear core reached past the corner region).
- **Controls shown after launch cover the picture for 5 s.** Wait them out (a frame-rate sample does) before a
  screenshot.
- **Few samples make a percentile meaningless.** The 5th percentile of 10 one-second windows is the worst second
  (a cold shader cache after a fresh install). Use 60 windows or more; record first-launch costs separately.

### Policy and evidence

- **Record decisions with their evidence** (ADR-0124: budgets corrected from the first device measurements; never
  loosened just to turn a failure green). A real app problem stays a failure until fixed (PERF-013's audio age).
- **Records are public**: keep only the certificate type and team ID in signing facts, write repository-relative
  paths, and verify no personal data before pushing.
- **Simulator rehearsals are never evidence** and stay gitignored; device records carry their own SHA-256 and a
  verifier; uncommitted artifacts such as xcresults drift and are not checked.
- **Everything that raises a prompt is human testing, never automated testing** (owner ruling, restated
  2026-11-16 after an unattended run on D1 stopped at a camera permission prompt): every test that can show a system
  prompt or alert that waits for a person — camera, microphone, Local Network, photo library, location, notifications,
  UI-automation consent — is grouped together in the human test session and never runs in an unattended device or
  simulator run. Today that group is `PermissionPrimerDeviceTests` (camera, microphone and Local Network prompts) and
  any B06 camera case that can reach the camera prompt on a device where it was never answered; unattended runs
  exclude them with `-skip-testing` and start only after the person session has answered every prompt on that device.
  A new test that can prompt goes into this group, and the unattended suite asserts that no prompt appears.

## What still needs a person

Headphones and Bluetooth routes, real phone and FaceTime calls, Airplane Mode, a real face or hands in front of the
camera, a USB MIDI device's own transport, real projectors and curved screens, a 240 fps camera, and the iOS prompts
that guard UI automation and permissions. Stand-ins that are automatable: a CoreMIDI virtual source for a controller,
the Mac sending OSC over Wi-Fi for a LAN controller, Siri for an interruption, AirPlay to the Mac for an external
display (needs AirPlay Receiver turned on by the owner), `xctrace` for Instruments.

## For another repository

1. Put measurement modes in the app behind a compile-time flag, writing JSON reports and exiting.
2. Give UI tests typed settings, a clean start, fixtures for media and audio, and an overlay or probe that exposes
   the numbers you assert.
3. Host package tests in the app for device runs; keep test code free of `Bundle.module`, guard DEBUG-only members.
4. Write a run record per device with hashes; keep it free of personal data; verify before committing.
5. Classify every hands-on task (scripted, stand-in, person) and batch the person-steps into a few sessions.
