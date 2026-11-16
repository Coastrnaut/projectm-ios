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
- **Keep person-steps out of the unattended suite** (owner ruling): a case that triggers a permission prompt moves to
  an owner session.

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
