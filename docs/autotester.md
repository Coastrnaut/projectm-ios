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
| System UI driver | `Apps/projectM-iOS/DeviceUITests/SystemUI.swift` | iOS's own UI from a device test (Batch 1; read-only for other batches): springboard alerts (`answerAlert`), Control Center (`openControlCenter`, `controlCenterPrivacyUser`, `statusIndicatorDotVisible`), the app switcher (`openAppSwitcher`, `returnFromAppSwitcher`, `forceQuitFromSwitcher`), the app's Settings page (`setAppPermission(.camera/.microphone/.localNetwork/.photos, on:)`), `toggleAccessibility(.reduceMotion/.increaseContrast/.grayscale/.differentiateWithoutColor/.smartInvert/.lowPower, on:)`, `startClockTimer(seconds:)`, `siriInterruption()`, `filesPick`/`filesSave`, `photosPick`, `shareSheet`, `cameraApp(photo:)`/`cameraApp(record:)`, `MacDriver.request`, `auditIssues`. Every setter is undone by `restore()` in tearDown unless `keep: true`. No Airplane Mode or Wi-Fi helper (cable steps not required, owner ruling 2026-11-18). |
| Prompt flow | `Apps/projectM-iOS/DeviceUITests/PromptFlowDeviceTests.swift` | The self-answering prompt batch (owner rule 14 as amended 2026-11-18), see below. |
| System tests | `B14SystemDeviceTests` (ACC-001, ACC-003, ACC-008), `B02…testPERF011SwitcherCardAndControlCenter`, `B03…testSCN002ForceQuitFromSwitcher` | Unattended tests that drive Settings, the switcher and Control Center; no prompts. |
| Mac driver | `scripts/mac_device_driver.py`, `scripts/mac_driver/` | `follow`: answers `MAC-DO {json}` lines in an xcodebuild log with an action module (`audio.play/tone/stop` via `afplay`, `memory.warning` via `devicectl … sendMemoryWarning`, `device.crashlogs`; later batches add xctrace, osc, midi, peer); logs `MAC-DONE <id>`. `prompt-flow`: uninstall, install, fixtures, then the prompt flow alone. |
| Media fixtures | `scripts/make_media_fixtures.py`, `scripts/fixtures/make_media.swift` | Build/fixtures/media: HEIC with GPS, 60 MP PNG/HEIC, a 45 MB JPEG, transparent PNG, 200-frame GIF, H.264 1080p, HEVC 4K60, HEVC 360p 10 min, HDR HEVC (HLG, 10-bit), WAV/AIFF/AAC/M4A AAC/ALAC, 10 MB and 60-min M4A, a damaged M4A, a PDF named .mp3, a JPEG named .milk, a 524,288-byte preset, a strobing preset, a 120 BPM click track (about 40 s on the Mac Studio). No MP3 (no encoder on the Mac). |
| Photo library seed | `Apps/projectM-iOS/Debug/UITestPhotoLibrarySeed.swift` | DEBUG `-uitestSeedPhotoLibrary <name,…>`: adds Documents fixtures to Photos (add-only), probe `photoLibrarySeed` ("status=… added=… missing=… failed=… done=1"). |
| Files sharing (Debug host) | `DeviceTests.yml` (post-build script) | The Debug device-test app gets `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`, so Documents shows in Files › On My iPhone/iPad › projectM for the real document picker. The shipping Info.plist is unchanged. |
| Music fixture | `scripts/make_music_fixture.py` | A deterministic, generated 60 s stereo track (120 BPM drums, bass, chords, quiet intro, loud chorus, breakdown). No licence. Copied into the app's Documents before a run. |
| Acceptance record | `scripts/device_acceptance_report.py` | Turns a run's log into `docs/test-reports/qa-011/acceptance/<device>-<session>.json` and `.md` (every measurement, every test, the log's hash). |
| Inventory and checklist | `scripts/qa011_inventory.py` | Every open `{device}`/`{owner}` task, classified (scripted, person, owner-only) and batched into owner sessions. |
| Release manifest | `scripts/release_manifest.py` | One commit's evidence: feature evidence, hashed reports, verified device records, gaps. |
| Instruments helper | `scripts/mac_driver/xctrace.py` | `xctrace record`/`export` commands, the TOC and table XML parser (`ref`/`id` values, sentinels), signpost events and markers, the PERF-004, PERF-011 and per-minute energy verdicts. Used by the matrix's `xctrace` cases. |
| Device goldens import | `scripts/import_device_goldens.py` | The `projectM-iOS.deviceGolden` attachments of a `RECORD_DEVICE_GOLDENS=1` run → `Packages/RenderGoldens/Goldens/<ios-device-model>/` (PNGs, canonical manifest). |
| OSC driver | `scripts/osc_device_driver.py` | Follows a run's log, answers `OSC-READY <scenario>` by sending OSC through the system Perl; `--listen-port` receives the app's Send OSC; `--device` copies an OSC routes export off the device and checks it. |
| MIDI driver | `scripts/mac_driver/midi.py` + `scripts/fixtures/midi_session.swift` | The Mac's CoreMIDI network session to the device; answers `MIDI-READY <scenario>` with CC, notes, programs, 14-bit pairs and clock; counts MIDI feedback. Needs the network-MIDI DEBUG exemption (see Batch 8). |
| Two-device runner | `scripts/mac_driver/peer.py` | Runs one test on D1 and one on D2 from per-device product copies; starts the acting role on the waiting role's `PEER-READY` line; pairs `PEER-STEP`/`PEER-SEEN` times. |
| Device facts | `scripts/mac_driver/devices.py` | D1-D3 by product type, Bonjour names, `dscacheutil` resolution, the Mac's own address, Documents copies. |
| Audio probes (DEBUG) | `Apps/projectM-iOS/Debug/UITestAudioProbes.swift`, CaptureKit `PlaybackDebugProbe`, AudioCore `NoiseGateDebugProbe` | QA-011 audio (B05): generated fixtures (`-uitestSeedAudio`), what the playback tap delivered (`-uitestPlaybackProbe`), the audio-session notifications (`-uitestSessionLog`), the noise gate's transitions (`-uitestGateProbe`), import times and announcements (`importProbe`), and a panel for seeks, queue edits, repeat and shuffle (`-uitestAudioPanel`). See "Audio device tests" below. |
| Audio device-test helpers | `Apps/projectM-iOS/DeviceUITests/AudioProbeSupport.swift` | Probe parsing, `launchPlayback`, real interruptions through `SystemUI` with the AUD-014 policy check, `MAC-DO` requests to the Mac driver. |
| Real-backend contract bundle | `Packages/CaptureKit/Tests/CaptureKitDeviceTests` (`CaptureKitDeviceTests` in `DeviceTests.yml`) | QA-007-T23: no sink write after stop and the session-event mapping with AVAudioEngine and the microphone (skips the microphone unless already granted). |
| MP3 fixtures | `scripts/make_music_fixture.py --mp3 cbr\|vbr` | AUD-002-T25: the music fixture as MP3 from `lame` (owner approved 2026-11-18): 192 kbit/s CBR, and `-V 2` VBR with an ID3v2 tag and cover art. `install_test_fixtures.py` makes and copies both. |

## Audio device tests (QA-011 Batch 3)

- **Time-code ramps instead of listening.** `-uitestSeedAudio ramps` writes 32-bit float WAVs whose channel 0 is a slow
  ramp: `0.03 + 0.05 k + 0.02 t / D` names the track `k` and the position `t` (channel 1 is a quiet tone with a kick, so
  the status reads "Active audio"). The In-App Playback tap records the first and last sample and the peak of every
  delivered buffer (`PlaybackDebugProbe`, atomics and a preallocated ring, only with `-uitestPlaybackProbe`); the app
  reads them back as `playbackProbe`: `staleSeeks` (first buffer after a seek more than 0.25 s off its target), `disc`
  and `rewinds` (jumps no cut explains: a gap or a repeated fragment), `wraps` (loops), `changes` (`a>b`, `!` when a
  track change cut in away from an end), `silentBuffers`/`maxSilentMs` (gaps), `cutJumpMs` (a resume continues where it
  held). This answers "is there audio from before a seek" on hardware with numbers, not by ear.
- **Other seeds:** `containers` (AAC M4A, ADTS `.aac`, ALAC M4A, WAV, AIFF via AVAudioFile), `broken` (truncated M4A,
  a PDF named `.mp3`), `large` (10.6 MB WAV), `long` (60-minute AAC; the first run writes it, about a minute or two),
  `original` (for the Files-picker import), `bigpreset` (a 524,288-byte preset; `-uitestImportPreset` now also takes a
  Documents-relative path). `-uitestDeleteDocument <name>` removes the picked original before a relaunch.
- **Real interruptions:** `SystemUI.startClockTimer` and `SystemUI.siriInterruption` (Batch 1); `sessionLog` shows
  whether iOS delivered the end and `shouldResume`, and `realInterruption(...)` checks the AUD-014 policy for what
  arrived. A lost output route stays synthetic (`session:routeLost`), headphones and calls stay with a person.
- **Microphone tests use the Mac's speaker:** the test prints `MAC-DO {"module":"audio","action":"play",
  "fixture":"music-fixture.m4a","seconds":N,"loop":true,...}` (and `"action":"stop"`); `scripts/mac_device_driver.py`
  plays it with `afplay` next to the device. Keep the device within about 30 cm of the Mac and the Mac's volume up.
  The tests wait on the gate or level probes, never on the Mac's log.
- **Which batch:** the microphone tests need the permission already granted; the Files-picker (AUD-001-T23,
  AUD-002-T25, AUD-002-T27) and Siri tests drive system UI and run in the prompt-flow batch (owner rule 14 as amended),
  never inside an unattended batch.

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

Media fixtures and the Mac driver (QA-011 Batch 1):

```bash
python3 scripts/make_media_fixtures.py [--list] [--only <name> …]        # Build/fixtures/media
python3 scripts/install_test_fixtures.py --device D1 --media             # music + media into Documents
python3 scripts/mac_device_driver.py follow --log <xcodebuild log> --device D1 &   # beside any run that prints MAC-DO
python3 scripts/mac_device_driver.py prompt-flow --device D1 [--osc-host <name>.local] [--dry-run]
```

Every unattended UI test run passes `-skip-testing:projectM-iOSDeviceUITests/PromptFlowDeviceTests` (and
`PermissionPrimerDeviceTests`), each as its own argument.

The hardware UDID (`hardwareProperties.udid`) is what `xcodebuild -destination` needs; `devicectl` takes its own
identifier. Both come from `xcrun devicectl list devices --json-output <file>`.

## Owner rulings for the device stage

- **2026-11-18: no AirPlay, no USB-cable steps.** AirPlay tests are not required (external-output checks use the DEBUG
  fake display `-uitestExternalDisplay`; a wired display or projector stays hardware). Steps that need the device on the
  USB cable with wireless off (Airplane Mode, Wi-Fi outage, offline launches) are not required. Tasks keep their
  checkbox with "⛔ not required (owner ruling 2026-11-18)" on those parts.
- **2026-11-18: MP3 fixtures** are made on the Mac with Homebrew `lame` (owner approved the install).

## Matrix cases added 2026-11-18 (QA-011 Batch 2)

| Case | Tasks | What it asserts |
|---|---|---|
| `autorun-perf001-glow` | part of PERF-003-T15 | perf001 on the circular spectrum with the glow on (`PROJECTM_VISUAL`, `PROJECTM_GLOW`); the export has `frameTimings.effectQuality` |
| `autorun-pre005` | part of PRE-005-T17 | 200 real thumbnails (evenly spaced) scored; percentiles and class counts for the threshold choice |
| `autorun-sc009` | AUD-014-T32 (D1, D3) | the lifecycle scripts' end states; on demand, needs the microphone answered (see below) |
| `rendererlab-flashcost` | part of FX-019-T22 | RendererLab `RL_MODE=flashcost`: strobe pass cost ≤ 2 ms per frame on every starter preset (builds RendererLab into `Build/rendererlab` when missing) |
| `xctrace-perf004` | PERF-004-T16 | Logging template: "PERF-004 texture allocation" signposts only before start + 5 s and within 3 s of each rotation (perf004 rotates at 10 s and back at 20 s) |
| `xctrace-perf011` | part of PERF-011-T21 | Metal System Trace + os_signpost; the Mac opens Settings at 15 s and relaunches the app at 35 s: no frames (and no GPU intervals of the app) from 10 s after backgrounding, a lower footprint, the first frame within 2 s of the return |
| `xctrace-perf008` | part of PERF-008-T16 | on demand (about 12 min): Power Profiler 5 min Standard then 5 min Battery saver; fps and frame time per minute from the app, energy per minute from any power table the trace exports |
| `xctest-goldens-record` | part of QA-003-T17 | on demand: records this model's goldens and imports them; commit them, rebuild, then `xctest-goldens` compares |

```bash
python3 scripts/run_device_matrix.py --device D1                         # includes perf001-glow, pre005, flashcost, perf004, perf011
python3 scripts/run_device_matrix.py --device D1 --only xctrace-perf008  # on demand
python3 scripts/run_device_matrix.py --device D1 --only xctest-goldens-record   # once; then add Goldens/ios-device-iphone15-4
python3 scripts/run_device_matrix.py --device D1 --only autorun-sc009 --no-install   # after the prompt-flow batch, D1 then D3
```

- **On-demand cases** (`onDemand`) never run in a plain matrix run, only when named with `--only`: long benches,
  recording goldens, and cases that raise a prompt.
- **A prompting case refuses to run after the run's own fresh install** (`prompts`): the uninstall reset its answers,
  so it would raise the prompt mid-batch (rule 14). Run the prompt-flow batch first, then the case with `--no-install`
  (installing over the app keeps the answers).
- **Instruments through `xctrace --env`**: AutomationRunner modes run inside the trace
  (`--env PROJECTM_AUTORUN=perf004 --launch -- <bundle>`), so the measurement build (Release + `PROJECTM_AUTOMATION`)
  is traced without DEBUG hooks. The modes emit Points of Interest markers (`QA-011 start`, `rotate`, `rotate back`,
  `background`, `foreground`) so trace times line up with the run; add `--instrument os_signpost` to templates that
  lack it (Metal System Trace, Power Profiler). `xctrace record --show-recording-options` lists a template's
  configurable instruments.
- **Backgrounding from the Mac**: `devicectl device process launch <id> com.apple.Preferences` sends the app away; a
  launch of the running app without `--terminate-existing` brings it back. The app holds a background task while
  away so its sampler can read footprint and frame counts (perf011). Not yet run on a device: check the first run.
- **Device goldens are per model** (`ios-device-iphone15-4`), outside `GoldenPlatformClass` (every generator suite
  iterates those classes and would demand goldens for them). The test bundle is read-only, so recording attaches JSON
  per capture and the Mac writes the folder.
- **A watchdog thread for scripts that can stall**: sc009's partial report names the phase it stalled in and how long
  the main thread has been silent; a main-actor watchdog would stall with it.

## Human testing group (tests that can prompt)

Owner rule 14 (2026-11-16): any test that can raise a prompt needing a person runs in this group, together, with the
owner present and told first; never in an automated batch. Automated batches assume these were answered.

Amended 2026-11-18 (owner: "automate everything … find a way to automate it"): prompting tests answer the prompt
themselves (springboard alert buttons, Settings toggles) in a separate prompt-flow batch that runs alone, after a
reinstall, and never inside another batch. `PermissionPrimerDeviceTests` (waits for a person) stays for runs with the
owner present; the automated prompt flow replaces it otherwise.

### The prompt-flow batch (automated, runs alone)

`python3 scripts/mac_device_driver.py prompt-flow --device D1` uninstalls the app (so iOS forgets every answer),
installs the built Debug app, copies the music and media fixtures, then runs only `PromptFlowDeviceTests` with the
Mac driver following the log (`--osc-host <name>.local` also starts `osc_device_driver.py`). The tests run in name
order and depend on the fresh install; each answers iOS's real prompt itself through springboard, Don't Allow first,
then grants in Settings, so the device ends with camera, microphone, Local Network and Photos (add only) granted for
the unattended batches. Never part of another batch; nothing waits for a person.

| Test | Prompts it answers | Closes |
|---|---|---|
| `testA_UIX001FreshInstallOffline` | none may appear (asserted at each of the five steps) | UIX-001-T14 (audits; Airplane Mode not required, owner ruling 2026-11-18) |
| `testB_UIX015CameraExplainerThenPrompt` | camera: Don't Allow | UIX-015-T14 (camera) |
| `testC_UIX015LocalNetworkExplainerThenPrompt` | Local Network: Don't Allow | UIX-015-T14 (Local Network), OSC-001-T26 (prompt on first enable) |
| `testD_FILE013DeniedPermissions` | microphone: Don't Allow; camera, Local Network off in Settings | FILE-013-T11 (Screen Time stays a person's) |
| `testE_CAM001DenyThenRevokeWhileBackgrounded` | none (Settings: allow, then revoke in the background; `device.crashlogs` on the Mac) | CAM-001-T25 |
| `testF_REC011SaveToPhotosAllowThenDeny` | Photos add-only: Allow; then Photos None in Settings | REC-011-T16 |
| `testZ_GrantEverythingForUnattendedRuns` | none (every permission on in Settings; OSC 0.42 with the OSC driver; `-uitestSeedPhotoLibrary`) | grants for later batches |

Untried on a device when written (2026-11-18): Settings rows are found by their visible labels (Apps › projectM,
Accessibility › Motion …) and the switcher and Control Center by coordinates in portrait; check the first run's
screenshots and fix SystemUI.swift (not the tests) where iOS 26 or 27 differs.

### Tests that wait for a person

| Test | Prompts | Notes |
|---|---|---|
| `PermissionPrimerDeviceTests.testA_Microphone` | Microphone | launch with `-autostart microphone` |
| `PermissionPrimerDeviceTests.testB_Camera` | Camera | chooses Camera in Settings (the camera never starts at launch) |
| `PermissionPrimerDeviceTests.testC_LocalNetwork` | Local Network | OSC on; check it really asks (see the camera lesson) |
| Purchase sheets, calls, headphones | system UI | listed in the person-only section (pickers, share sheets and Siri: SystemUI helpers; AirPlay and cable steps: not required, owner ruling 2026-11-18) |

Run once per device after a fresh install (a reinstall over the app keeps the answers):

```bash
xcodebuild test-without-building -xctestrun <copy>/…xctestrun -destination platform=iOS,id=<UDID> \
  -only-testing:projectM-iOSDeviceUITests/PermissionPrimerDeviceTests
```

The camera B06 tests stopped on D1 at the camera prompt mid-run (2026-11-16) because the first primer set Camera at
launch and so never asked; the prompt then appeared inside the automated batch. That is what this group prevents.

## Control surfaces and two devices (QA-011 Batch 8, 2026-11-18)

Tests: `B09OSCDeviceTests` (single device, Mac as controller), `B09OSCPeerDeviceTests` (two devices),
`B10MIDIDeviceTests` (Mac as MIDI controller), `B11OutputDeviceTests` (the DEBUG fake external display). Shared steps
are in `ControlSurfaceSupport.swift`; system UI goes through Batch 1's `SystemUI.swift` (one bridge section). Values
the Mac knows reach a test as `TEST_RUNNER_<NAME>=<value>` on the xcodebuild command (`MAC_IP`, `PEER_IP`,
`MIDI_SOURCE`); a missing one skips with the reason. AirPlay to the Mac and USB-cable steps (Airplane Mode, Wi-Fi
outages) are not required (owner ruling 2026-11-18).

```bash
# Single device, OSC (D1): start the driver, then the tests (each -only-testing is its own argument).
python3 scripts/osc_device_driver.py --log Build/b09-D1.log --host iPhone77.local --listen-port 9100 --device D1 &
xcodebuild test-without-building -xctestrun <copy>/…xctestrun -destination platform=iOS,id=<D1 UDID> \
  -only-testing:projectM-iOSDeviceUITests/B09OSCDeviceTests -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 300 TEST_RUNNER_MAC_IP=<Mac LAN address> > Build/b09-D1.log 2>&1
# MIDI (D1): python3 scripts/mac_driver/midi.py --log Build/b10-D1.log --host iPhone77.local & then B10MIDIDeviceTests.
# Fake external display (D1; UIX-008 on D2, D3): -only-testing:projectM-iOSDeviceUITests/B11OutputDeviceTests.
# Two devices (D1 + D2 on the Mac's Wi-Fi):
python3 scripts/mac_driver/peer.py osc008|osc011|osc012|midi012 --products Build/device-acceptance/Build/Products
```

- **The Mac receives OSC through Perl too:** the Send OSC check (`--listen-port`) binds a UDP socket in the system Perl,
  like the sender, because Local Network privacy refuses the command-line Python (not yet confirmed for receiving).
- **Log lag decides the design:** a device test never waits on the Mac's timing. It prints `<KIND>-READY`, then waits
  up to 25-30 s for the effect it can see (a glow value, a cue, a badge). Senders repeat (OSC three times, cue steps
  every 3-4 s) so a late start on the Mac still lands inside the window.
- **Two devices from one build:** `peer.py` copies the products per device (`Build/peer/<D>/Products`) and starts the
  waiting role first (receiver, announcer, follower), the acting role on its `PEER-READY` line. Latency across devices
  uses the two device clocks (NTP); `PEER-LATENCY` reports median and max without correcting the offset.
- **Network MIDI is excluded by the app's own policy:** the app drops network-attributed MIDI endpoints (MIDI-001-R2,
  R14; ADR-0038) and both compliance scans reject `MIDINetwork*`, DEBUG included. `B10MIDIDeviceTests` skips until a
  DEBUG exemption is approved (proposal in the Batch 8 report); the Mac helper also refuses to enable the Mac's own
  session (Audio MIDI Setup › Network, the owner's setting) and only adds and removes its connection.
- **Readouts limit what a test can prove:** MOD-002's glow readout has two decimals, so MIDI-005's "> 1,000 steps"
  shows as at most ~100 distinct readings; a finer probe is needed for the full criterion.
- **Simulator classes cover device-only reruns:** SHOW-007/008/009 and SHOW-012's row label run as
  `projectM-iOSUITests/ShowTimelineUITests`, `ShowKeyframeUITests`, `ShowKeyframeEasingUITests`, `CueNoteUITests` on
  the device through the DeviceAcceptance scheme.

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
  and `rateSkipped=` besides written and dropped slots; `videoRecordingProbe` ends with `offGrid=<n>`, the frames whose
  presentation time is off the recording's 1/fps grid; `-uitestRecordingNoAudio` records without an audio track;
  `-uitestAutoRecordSeconds <n>` starts a recording 4 s after launch and stops it n s later, so `xctrace --launch` can
  trace one without taps. `xctrace --attach` could not find the app on D3 by pid or name (2026-11-18): launch it
  through xctrace instead.
- **Visual, show and accessibility probes (QA-011 Batch 7, DEBUG, `-uitestVisualProbes`;
  `Apps/projectM-iOS/Debug/UITestVisualProbes.swift`):** a 30 Hz main-actor sampler publishes near-transparent texts in
  the visualizer layer: `flashGuardProbe` (the strobe envelope's gain on the visual shown: projectM's
  `ANGLERenderer.debugFlashProbe` reads it back every sixth frame, which costs a few fps, so compare frame rates with the
  probe on in both runs; native generators' `lastGain`; the Photo compositor's `lastFlashGain`; below 0.98 = clamped,
  `recent*` = the last 3 s), `tunnelSpeedProbe`, `sectionChangeProbe` (playback positions of section-change fires;
  `-uitestBindGlowToSectionChange` binds it to the glow), `pipelineArchiveProbe` (PERF-009 hits and misses),
  `hapticProbe` (pulse host times), `presetFlashProbe` (current preset, may flash), `compareProbe` (the last comparison's
  frames per second and worst thermal state, kept after Close), `renderFaultEventsProbe`, and `announcementsProbe` (the
  announcer's spoken list, so "announced once" is countable). Probes in the visualizer layer cannot be read while a sheet
  covers it: tests close Settings or the browser first and read the kept values. Elsewhere: `particleBoundsProbe` in the
  Particle emitter editor (outside the box, newest spawns inside the path); `-uitestImportPreset fixture:strobe` writes
  ACC-002's strobing preset in the app (relative values are taken from Documents), so no file is copied for FX-019;
  `-uitestAccessibilityActions` also adds `colorSamplingLayer.uitestEscape` (VoiceOver's escape) and the split editor
  divider's increment/decrement probes. `TEST_RUNNER_ACC006_LANDSCAPE=1` runs DynamicTypeInspectorUITests in landscape.
  XCUITest on iOS cannot make two-finger swipes or three-finger taps (only taps, two-finger taps, pinch, rotate).
- **UI test runs must not record the screen as video:** Xcode's default `PreferredScreenCaptureFormat =
  screenRecording` encodes the device screen for the whole UI test on the hardware video encoder. Any test that
  measures the app's own recording (or other encoder work) then competes with it: on D3 (A16) a 60 fps recording
  wrote ~21 fps and dropped 66 % of its slots, on D1 15 %, while D2 (M5) hid it. The DeviceAcceptance scheme sets
  `preferredScreenCaptureFormat: screenshots` (`DeviceTests.yml`); check the `.xctestrun` says `screenshots` before
  trusting a recording measurement. Found by running the same encoder probe inside the app with and without XCUITest
  (`devicectl device process launch ... -- <arguments>`: put the app's arguments after `--`).
- **"Idle" in a sample can be a blocked main thread** (sc009 stall on the simulator, 2026-11-15; read from the code
  2026-11-18, not reproduced): the UI stayed at "In-App Playback · Interrupted" and the script never reached its next
  step, although it only sleeps between notifications. The step after "interruption began" is "interruption ended,
  resume"; the policy then resumes In-App Playback, and `AVInAppPlaybackBackend.resume()` calls
  `AVAudioSession.setActive(true)` and `AVAudioEngine.start()` synchronously on the main actor. With the simulator's
  audio server failing (-10879 on every engine start), such a call can wait in `mach_msg` for good, which looks idle
  in a sample. A main-actor timer would stall too, so sc009's watchdog runs on its own queue and reports
  `mainThreadSilentSeconds`; a simulator rehearsal also samples the app after 80 % of the wait.
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
  Amended 2026-11-18: the group is automated as the prompt-flow batch (`PromptFlowDeviceTests`, run alone after a
  fresh install by `mac_device_driver.py prompt-flow`); a new prompting test goes there.

## What still needs a person

Headphones and Bluetooth routes, real phone and FaceTime calls, Airplane Mode and Wi-Fi off (they need the USB cable:
not required, owner ruling 2026-11-18), a real face or hands in front of the
camera, a USB MIDI device's own transport, real projectors and curved screens, a 240 fps camera, and the iOS prompts
that guard UI automation and permissions. Stand-ins that are automatable: a CoreMIDI virtual source for a controller,
the Mac sending OSC over Wi-Fi for a LAN controller, Siri and a Clock timer for an interruption (SystemUI), Settings
toggles for permissions and accessibility settings (SystemUI), `xctrace` for Instruments. AirPlay steps are not
required (owner ruling 2026-11-18).

## For another repository

1. Put measurement modes in the app behind a compile-time flag, writing JSON reports and exiting.
2. Give UI tests typed settings, a clean start, fixtures for media and audio, and an overlay or probe that exposes
   the numbers you assert.
3. Host package tests in the app for device runs; keep test code free of `Bundle.module`, guard DEBUG-only members.
4. Write a run record per device with hashes; keep it free of personal data; verify before committing.
5. Classify every hands-on task (scripted, stand-in, person) and batch the person-steps into a few sessions.
