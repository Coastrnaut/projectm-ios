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
| Camera probes | `Apps/projectM-iOS/Debug/UITestCameraDeviceProbes.swift` | DEBUG `-uitestCameraDeviceProbes` (Batch 4): `cameraDeviceState` (capture sessions running, starts, stops, `stopsAway`; exposure, white balance; the motion sensor), `cameraOrientationGrid` + `cameraOrientationGridRefresh` (12 × 16 luma grids of the newest saved frame and recording, with `files=<frames>/<recordings>`; it also refreshes by itself when a new file appears; the buttons sit top-leading), `cameraFocusCentreAction` (the "Focus at centre" custom action). `-uitestBindGlowToMotion` binds glow to Tilt forward and Shake. |
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
| Recording checks | `scripts/recording_frame_check.py`, `scripts/fixtures/recording_inspect.swift` | Batch 6: reads `RECORDING-CHECK` lines from a run's log, copies each recording or still off the device and checks atoms, codec, `sips`, Vision OCR, centre correlation, click/flash alignment and QA-008's validator; `Build/recording-checks/<device>/report.json`. |
| Device files | `scripts/mac_driver/files.py` | `files.pull` copies the newest Documents file by prefix/suffix to `Build/device-files/<D>/` and checks a ZIP's entries and manifest (`present`/`absent`); `files.push` copies one pulled from another device into this device's Documents (Batch 5: PRE-014, FILE-001). |
| Media probes | `Apps/projectM-iOS/Debug/UITestMediaDeviceProbes.swift` | DEBUG, with `-uitestDiagnostics`: `videoFrameRate` ("fps=<x> late=<n> taken=<n> dropped=<n>": the clip's distinct pictures per second) and `photoStoredMetadata` ("gps=<none\|present> exif=… size=WxH bytes=n" of the stored copy). `-uitestSeedVideo uhd60` / `long600` import the Documents HEVC fixtures (4K60 10 s, 360p 10 min). |
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

**After the grants (QA-011 2026-11-19).** Tests that need a grant only the prompt flow gives are listed in
`AFTER_GRANTS` (`scripts/mac_device_driver.py`). In an ordinary batch on an install without the grant they
`XCTSkip` with the instruction (an environment precondition, not a result); `prompt-flow` runs them in a second
xcodebuild run right after `PromptFlowDeviceTests` (XCTest orders classes by name, so `B08…` cannot share the prompt
flow's run and come after `testZ`). A skip is therefore always followed by a run with the grant. Today:
`B08RecordingDeviceTests/testREC004MicrophoneRecordingHasAnAudioTrackOnlyWithTheSetting` (microphone). Add a test
there when it needs camera, microphone, Local Network or Photos and skip it the same way.

Untried on a device when written (2026-11-18): Settings rows are found by their visible labels (Apps › projectM,
Accessibility › Motion …) and the switcher and Control Center by coordinates in portrait; check the first run's
screenshots and fix SystemUI.swift (not the tests) where iOS 26 or 27 differs.

First run on D2 (iPadOS 27.2) and D3 (iPadOS 26.5), 2026-11-19:

- **iPadOS 27.2 lists each prompt button twice, nested** (`kTCCServiceCamera-deny-button` inside itself), so
  `alert.buttons["Don’t Allow"].tap()` failed with "Multiple matching elements found". `SystemUI.alertButton` picks one.
  A prompt left open by a failed test is then answered by XCTest's default interruption handler with **Allow** at the
  next test's first tap (D2: the camera was granted that way), so a prompt-answering failure spoils the tests after it.
- **The iPad split editor hides the top row under the bar:** `-uitestSettingsSection osc` puts the OSC switch under
  the navigation bar's scroll-edge area, where taps land on the bar ("Not hittable: Switch {{727, 126}, …}"). The test
  drags the list down until the switch is clear of the bar and asserts that the switch changed.
- **A plain UDP listener does not make iOS ask for Local Network:** with OSC turned on, D2 and D3 showed no prompt and
  the receiver reported "Listening", so Local Network never appeared on the app's Settings page (testZ) and no denial
  notice could show (testD). Fixed in the app by ADR-0125 (one short Bonjour browse on start while the answer is
  unknown makes iOS ask); testC also prints `OSC-READY test` (the Mac sends with `--osc-host`) and names the cause.
- **iPadOS 26.5 audits what the tutorial covers:** the accessibility audit reported the source chooser behind the
  opaque tutorial although RootView hides it from accessibility; testA logs issues of covered (not hittable) elements
  without counting them, and waits 0.8 s before each audit (a just-tapped Next/Play button "failed" contrast).

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

## Camera (QA-011 Batch 4, 2026-11-18)

Tests: `B06CameraDeviceTests` (its Batch 4 extension: CAM-002-T21/T22, CAM-004-T08, CAM-005-T14, FX-009-T18,
REC-003-T23 Camera, CAM-007-T15's Fit bars) and `B06CameraSystemDeviceTests` (CAM-001-T24/T26/T27, CAM-002-T21's
indicator, CAM-012-T13, CAM-013-T17/T18, CAM-006-T09, CAM-011-T15). Camera access must be granted first
(`PromptFlowDeviceTests` testZ); no Batch 4 test meets a prompt. They launch with `-uitestCameraDeviceProbes`.

```bash
xcodebuild test-without-building -xctestrun <copy>/…xctestrun -destination platform=iOS,id=<D1 UDID> \
  -only-testing:projectM-iOSDeviceUITests/B06CameraDeviceTests \
  -only-testing:projectM-iOSDeviceUITests/B06CameraSystemDeviceTests \
  -skip-testing:projectM-iOSDeviceUITests/PromptFlowDeviceTests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 300 > Build/b06-D1.log 2>&1
```

- **Session state, not the indicator, is asserted for "the camera stopped":** AVFoundation's start and stop
  notifications, counted in the app. A backgrounded app cannot be read by XCUITest, so stops posted between
  resign-active and become-active are counted (`stopsAway`) and read on return; the motion sensor the same way.
- **The system indicator:** Control Center's header naming the app *and* "camera" is asserted while the camera runs
  and must not read as in use after it stops ("recently" counts as not in use). SystemUI's
  `controlCenterPrivacyUser()` matches the app's name alone, which Now Playing shows too while music plays, so the
  camera tests use their own match. The green dot in a screenshot is reported, never asserted, until D1 shows that a
  screenshot contains it. Check both on D1 first.
- **Mirror and orientation from grids:** a 12 × 16 luma grid of the screenshot is correlated with its own mirror
  image and with the app's grid of the saved frame or the recording's middle frame (top two rows, the bottom row and
  the spectrum's centre disc masked). It needs a left-right asymmetric scene in front of the camera; with a symmetric
  one (asymmetry < 0.15) the test skips and says so.
- **Interruptions without a person:** the Camera app launched for 4 s (no photo is taken, nothing is added to Photos)
  takes the camera; Siri (typed, must be on) interrupts without the background (white balance stays locked). Split
  View on D2, a FaceTime call and Retry's back-off under a persisting interruption stay a person's.
- **Revocation (CAM-013-T17):** the camera switch turned off in Settings while the app is in the background; iOS ends
  the app; the next start shows the denied notice; the test and `SystemUI.restore()` turn it back on.
## Recording and share (QA-011 Batch 6, 2026-11-18)

Tests: `B08RecordingDeviceTests` (recordings read back in the app and, through the Mac, in the file) and
`B08ShareDeviceTests` (the Files exporter and mover, the share sheet, the Files app, the Recordings library), with
`RecordingCheckSupport.swift`. A test that leaves a file for the Mac prints one `RECORDING-CHECK {json}` line (folder in
the app's container, name prefix, the "yyyy-MM-dd at HH.mm.ss" stamp it must not be older than, the checks). After
the run `scripts/recording_frame_check.py` copies each file off the device and checks it with a compiled Swift helper
(`scripts/fixtures/recording_inspect.swift`: AVFoundation tracks and frames, Vision OCR) and Python (MP4 atoms, `sips`,
correlation, onsets). Nothing waits on the Mac during the run.

| Test | Tasks | What it asserts (app / Mac) |
|---|---|---|
| `B08RecordingDeviceTests.testREC014…` | REC-014-T15 | planned shape / the file's frame correlates (r ≥ 0.8) with the centre crop of a screenshot taken while recording |
| `testREC008TimedStopTenSeconds` | REC-008-T14 | 10 s, 300 slots, **300 frames written**; the failure names busy, notReady, rateSkipped |
| `testREC016ThirtySecond…` | REC-016-T13, QA-008-T10 | 30 s with audio, CPU idle vs recording (`cpuProbe`) / `moov`, no `moof`; `testExternalRecording` on the same file |
| `testREC009StatusLinesAreNotInTheFile` | REC-009-T11 | status lines with a real low free-storage reading (ballast) / OCR finds none of their words in the frames |
| `testREC015RealDiskGuardStopsTheRecording` | REC-015-T17 | the real guard stops with "Recording stopped because storage is almost full.", the offered file reads back |
| `testREC007CountdownStartsAfterOne…` | REC-007-T13 | recording ≥ 2.9 s after Record, "Recording in 3", "2", "1" once each; Cancel: no probe, no file / no file |
| `testREC004ClickAndFlashAlignInTheFile` | REC-004-T19 | click fixture on Beat Rings, audio track / clicks vs luma flashes, median ≤ 40 ms |
| `testREC004MicrophoneRecording…` | REC-004-T19 | audio track only with "Include microphone audio" / with the Mac driver's 1 kHz tone, audio not silent |
| `testMED011RecordingContainsTheClock` | MED-011-T13 | / OCR reads the device's HH:mm in ≥ 2 frames |
| `testMED012CountdownFinishesOnce…` | MED-012-T14 | 00:00 once and held, finished=1, "Countdown finished" once / OCR reads the countdown, last frame 00:00 |
| `B08ShareDeviceTests.testREC001PNGAndHEIFToOnMyDevice` | REC-001-T19 | "Frame saved." for PNG and HEIF / `sips` reads png and heic |
| `testREC003SaveToOnMyDeviceAndPlayInFiles` | REC-003-T25 | "Recording saved.", Files › On My iPad › projectM opens it in Quick Look / hvc1 with audio |
| `testREC012ShareSheetForAFrameAndARecording` | REC-012-T13 | AirDrop, Save to Files (Messages on the iPhone); no Save Image/Video, Assign to Contact; cancel keeps the panel; Messages compose cancelled; iPad popover; "Shared." / both files read |
| `testREC010RecordKeepPlayShareRenameDelete` | REC-010-T13 | Keep, play (picture changes), Save to Files, rename, delete / the renamed file is gone from the library folder |

```bash
python3 scripts/install_test_fixtures.py --device D1 --media        # click-120bpm.m4a for REC-004
python3 scripts/mac_device_driver.py follow --log Build/b08-D1.log --device D1 &   # the Microphone test's tone
xcodebuild test-without-building -xctestrun <copy>/…xctestrun -destination platform=iOS,id=<D1 UDID> \
  -only-testing:projectM-iOSDeviceUITests/B08RecordingDeviceTests -only-testing:projectM-iOSDeviceUITests/B08ShareDeviceTests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 300 TEST_RUNNER_MAC_DRIVER=1 > Build/b08-D1.log 2>&1
python3 scripts/recording_frame_check.py run --log Build/b08-D1.log --device D1    # Build/recording-checks/D1/report.json
```

Devices: D1 for all; D3 for REC-001, REC-003-T25 and MED-011; D2 for REC-014 (Portrait) and REC-012's popover.

- **Disk ballast (DEBUG):** `-uitestDiskBallast <freeMB>` fills one file in Caches until the free storage the guard
  reads (`volumeAvailableCapacityForImportantUsage`) is about that much; `-uitestDiskBallastGrowMBps <n>` grows it while
  a recording file exists, so the real guard stops within seconds. It never leaves less than 200 MB of real free space,
  every DEBUG launch deletes an old ballast, and the ballast tests relaunch the app once in tearDown. Probe
  `diskBallast`; state `capped` (purgeable space keeps the reading high) skips REC-015 with the readings. iOS may show
  "Storage Almost Full": the test dismisses only alerts that mention storage. First device run (QA-011 pass 3, D3,
  43 GB free): one extension of the whole gap never returned within 300 s and the probe stayed "state=filling
  ballastMB=0". The fill now grows in 1 GB steps with a progress line after each and ends `state=slow` after 360 s;
  the tests wait 390 s, print the progress every 30 s, and REC-015 skips on `slow` with the readings.
- **CPU (DEBUG):** `cpuProbe` reads "cpuSeconds=<user+system> uptime=<s>" each second (`getrusage`); a test takes
  Δcpu/Δuptime (100 % = one core).
- **Files in tmp survive, offered ones do not:** a launch deletes `<tmp>/Recordings` (REC-003-R13), so every file the
  Mac reads is in a `-uitestRecordingDirectory` folder (`tmp/QA011-…`), in Documents (Files saves), or the library.
- **Still a person's:** an AirDrop transfer (a receiver accepts), iCloud Drive destinations (iCloud signed in), the
  countdown with VoiceOver on, System/App Capture video only (the system picker), and the microphone prompt itself
  (answered by the prompt flow first; a prompt here fails the test and is left alone).
## Media layers, files and presets (QA-011 Batch 5, 2026-11-18)

Tests: `B07MediaDeviceTests` (photo, video, loop, speed, slideshow, Ken Burns, GIF, text, logo, real camera media),
`B07FilesDeviceTests` (collections, preset import and export, thumbnails, scene archives, Storage, Clear Caches) and
four more in `B13MediaDeviceTests` (4K60 and 10-minute playback, 3 minutes of 4K thermal, a real memory warning). The
real Files and Photos pickers and the share sheet go through `SystemUI` (`filesPick`, `filesSave`, `photosPick`,
`shareSheet`); Photos picks use `-uitestSeedPhotoLibrary` (add-only, granted by the prompt-flow batch; a seed that would
prompt fails instead of waiting). Not yet run on a device when written: check the first run's screenshots.

| Test | Tasks | Devices | Needs |
|---|---|---|---|
| `B07MediaDeviceTests/testMED001PhotosPickerNoPrompt` | MED-001-T22 | D1, D3 | Photos add-only granted |
| `…/testMED001FilesPickRelaunchRemove` | MED-001-T23 (iCloud Drive part: person) | D1, D3 | media fixtures |
| `…/testMED001HEICLocationPanoramaLarge` | MED-001-T24 | D1, D3 | media fixtures |
| `…/testMED014RealCameraMediaPanoramaAndHDR` | MED-014-T23 (ProRAW: owner's file) | D1, D3 | Camera app (no prompt of this app) |
| `…/testMED002PhotosAndFilesVideoPicks` | MED-002-T26 | D1, D3 | Camera app |
| `…/testMED003LoopRegion` | MED-003-T20 | D1 | media fixtures |
| `…/testMED004SpeedRates` | MED-004-T22 | D1 | media fixtures |
| `…/testMED006SlideshowFromPhotosAndFiles` | MED-006-T22 | D1 | Photos add-only granted |
| `…/testMED007KenBurns` | MED-007-T16 | D1 | media fixtures |
| `…/testMED008LargeGIF` | MED-008-T12 | D1 | Photos add-only granted |
| `…/testMED009LargestTypeRTLEmoji` | MED-009-T23 (real Arabic/Hebrew keyboards: person) | D1, D3 | none |
| `…/testMED010LogoCorners` | MED-010-T25 | D1 | Photos add-only granted |
| `B07FilesDeviceTests/testPRE007_A_SeedCreateAndReorder`, then install over, then `…_B_CollectionsSurviveInstallOver` | PRE-007-T23 (VoiceOver speech: person) | D1, D2, D3 | the Mac installs between A and B |
| `…/testPRE012ImportThroughFilesPicker` | PRE-012-T31 (VoiceOver listening: person) | D1, D2, D3 | media fixtures |
| `…/testPRE014ExportZipToFiles` | PRE-014-T25 | D1, D3 | Mac driver (`files.pull` checks the ZIP) |
| `…/testPRE001FPSWhileThumbnailsGenerate` | PRE-001-T14 | D1 | none (`-uitestMemoryPressure` frame counter) |
| `…/testFILE001_A_ExportSceneArchive` (D1), then `…_B_ImportSceneArchive` (D3) | FILE-001-T19 (offline: not required) | D1 → D3 | Mac driver (`files.pull` on D1, `files.push` on D3) |
| `…/testFILE009StorageValuesWithRealMedia` | FILE-009-T12 | D1 | media fixtures |
| `…/testFILE010ClearCaches` | FILE-010-T11 | D1 | media fixtures |
| `B13MediaDeviceTests/testMED002UHD60PlaysAtItsRateWithFlatMemory`, `…/testMED002TenMinuteClipPlaysAtItsRateWithFlatMemory` | MED-002-T27 | D1, D3 | media fixtures (else generated clips) |
| `B13MediaDeviceTests/testMED002ThreeMinutes4KThermal` | MED-002-T28 | D1, D3 | allowance 300 s |
| `B13MediaDeviceTests/testPERF006RealMemoryWarning` | PERF-006-T17 | D1, D3 | Mac driver (`memory.warning`) |

```bash
python3 scripts/make_media_fixtures.py && python3 scripts/install_test_fixtures.py --device D1 --media
python3 scripts/mac_device_driver.py follow --log Build/b07-D1.log --device D1 &        # for the Mac-driven tests
xcodebuild test-without-building … -destination platform=iOS,id=<D1 UDID> TEST_RUNNER_MAC_DRIVER=1 \
  -only-testing:projectM-iOSDeviceUITests/B07MediaDeviceTests -only-testing:projectM-iOSDeviceUITests/B07FilesDeviceTests/testPRE012ImportThroughFilesPicker \
  -skip-testing:projectM-iOSDeviceUITests/PromptFlowDeviceTests -test-timeouts-enabled YES -default-test-execution-time-allowance 300 > Build/b07-D1.log 2>&1
# PRE-007: run …/testPRE007_A_SeedCreateAndReorder, then
xcrun devicectl device install app --device <id> Build/device-acceptance/Build/Products/Debug-iphoneos/projectM-iOS.app
# then …/testPRE007_B_CollectionsSurviveInstallOver (a separate invocation; do not reset in between).
# FILE-001: …/testFILE001_A_ExportSceneArchive on D1 (driver --device D1), then …/testFILE001_B_ImportSceneArchive on D3
# (driver --device D3: it pushes Build/device-files/D1/<newest .pmscene>).
# Mac cross-checks: devicectl device info files --device <id> --domain-type appDataContainer \
#   --domain-identifier org.projectmios.ProjectMiOS [--subdirectory Library/Caches] --json-output f   (FILE-009, FILE-010)
```

- **Fixtures added for Batch 5** (`make_media_fixtures.py`): `slide-1.png` … `slide-5.png` (640 × 480 checkerboards in
  five colours: slide order and Ken Burns movement), `logo-white-disc.png` (white disc, anti-aliased alpha edge: the
  dark-fringe check), `preset-small.milk` (a second valid import).
- **Results only the Mac sees:** `files.pull`'s `MAC-DONE <id> ok|FAIL …` line in the driver's log is PRE-014's ZIP
  evidence; keep the driver log with the test log.
- **Probes, not looks:** frame rates of a clip come from `videoFrameRate`, loop joints from `videoLoopStats`
  (gap 0 = no joint late by a picture), slides from `slideshowProbe`, Ken Burns and GIF motion from screenshots away
  from the centred spectrum (`stillRegion`), the logo edge from step-2 screenshot pixels around the corner.
- **The browser sheet can hide the visualizer from XCUITest's tree** (untested on a device): PRE-001 counts presented frames (`visualFrames`) before
  and after a browser-open window instead of reading the overlay behind the sheet.

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
  `minimumDraw: 0.005` there; filled visuals keep 0.02. The Lissajous and the Radial Waveform are line visuals too
  (2026-11-18: the radial ring covers 1.0-1.1 % on D1-D3).
- **The performance overlay is part of every screenshot** (full run, 2026-11-18): its text is about 1-2 % non-black
  on D1 and changes every second, so whole-screen "draws" and "moves" figures carry it. D1 passed VIS-005 "draws" and
  VIS-016 "calmer" on the overlay's text alone; triage a screen-statistic failure with the overlay's box left out
  before reading anything into the visual.
- **Sampling steps alias with the effect's grid:** screenshots are sampled every 8th pixel, and an 8 px square mosaic
  shows each block's centre pixel, the very pixel the 1/8 nearest-neighbour scale reads: FX-012's 8 px change read 0.0
  on D2 and D3. Sample with a step coprime to the effect's period (3 for FX-012, 1 for 1 px scanlines).
- **Screen change saturates for fast small objects:** once every star moves further than its own size between two
  screenshots, half speed changes the picture as much as full speed. Measure speed from the simulation
  (`starfieldProbe`: respawns per step), not from screenshot pairs.
- **Reduce Motion also turns on Reduce flashing** unless the test sets `settings.reduceFlashing`: its stricter
  composite envelope scales the whole frame by a few percent as the spectrum flashes (FX-017's "still" Photo pair
  differed by a uniform 3-5 % gain). Pin Reduce flashing when a check is about something else.
- **"Controls exist" can be a fade-out:** CAM-007 on D1 found the controls existing 8 s after Settings closed, skipped
  the tap that shows them, and Save Frame was gone a moment later. Wait for them to hide, then show them fresh.
- **iPad Settings side panel and the status-bar tap:** the panel sits at the trailing edge (D2 x 632-1032), so a
  status-bar tap at the window's centre scrolls nothing (PERF-010 on D2, D3). Tap above the panel (`list.frame.midX`);
  the panel is not a sheet, so fast fallback swipes are safe there.
- **An unexplained main-thread stall after a return from the background** (VIS-001-T36, D2 only, 2026-11-18): XCTest
  waited 60 s for idle after `activate()` and every query then failed with "main thread busy for 30 s"; the overlay's
  frame counter in the screenshot taken minutes later stood at about the frame count of the moment the app left, and
  the attached spindumps held "No samples". D1, D3 and PERF-011 on D2 passed the same return. Not reproduced; on a
  repeat, take a sysdiagnose on the device during the stall (the main thread's stack is the evidence).
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
  `ANGLERenderer.debugFlashProbe` reads it back every seventh frame, which costs a few fps, so compare frame rates with the
  probe on in both runs; native generators' `lastGain`; the Photo compositor's `lastFlashGain`; below 0.98 = clamped,
  `recent*` = the last 3 s), `tunnelSpeedProbe`, `sectionChangeProbe` (playback positions of section-change fires;
  `-uitestBindGlowToSectionChange` binds it to the glow), `pipelineArchiveProbe` (PERF-009 hits and misses),
  `hapticProbe` (pulse host times), `presetFlashProbe` (current preset, may flash), `compareProbe` (the last comparison's
  frames per second and worst thermal state, kept after Close), `renderFaultEventsProbe`, `starfieldProbe` (the
  starfield simulation's steps, near-plane respawns and Reduce Motion; VIS-016-T13), and `announcementsProbe` (the
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
- **Skips must reach xcodebuild as separate arguments (2026-11-18, again):** a run built its `-skip-testing:` list in a
  zsh variable; zsh does not split an unquoted `$VAR`, so the whole list was one argument, every "skipped" class ran
  (the prompt-flow and permission primers included) and xcodebuild reported nothing wrong. Use
  `scripts/run_device_ui_tests.sh <d1|d2|d3> <name> only:<id> skip:<id> …` (bash arrays; `MAC_DRIVER=1` starts the Mac
  driver on the log), and check the log's command line before trusting a run.
- **iPad and iPadOS lessons from the first D2/D3 run (2026-11-18):** the Files picker never lists the presenting app's
  own folder (On My iPad › projectM is absent even with file sharing on): open the picker in the app's Documents with
  DEBUG `-uitestPickerInDocuments` and tap the file. Controls that are fading out still "exist": wait for them to hide,
  then show them fresh. iPadOS 26's status-bar band swallows taps on top-edge DEBUG panels. The Camera app asks for
  location on its first launch (a person's prompt; the test skips with its text). The iPad Control Center privacy pill
  reads "projectM Controls" with a camera icon and no "camera" text. Siri off is recorded as an issue ("Unable to
  activate Siri…", or on iPadOS 26.5 after 60 s "Timed out waiting for Siri to activate"), not thrown: tests swallow
  exactly those issues and skip the Siri step, and later Siri steps in the run skip at once
  (`SiriAvailability.knownUnavailable`). A ringing Clock timer keeps its interruption (no `ended`) and its "Timer"
  banner covers the top centre until someone stops it: the interruption helper stops it after `began`. An interrupted
  AVCaptureSession posts a stop without a matching start on resume, so start/stop counts do not say it runs. A result
  bundle from an interrupted run has no Info.plist; its screenshots are zstd blobs under `Data/`.
- **Pickers on the iPads, pass 3 (2026-11-19), corrects the lesson above:** On My iPad › projectM *is* listed (D3
  browsed to it and showed every fixture); the files were "missing" because a Files grid cell is labelled
  "<stem>, <extension>, <date>, <size>" (identifier "<stem>, <extension>"), never the file name, and most fixtures sit
  below the first screen of a 4-wide grid. `SystemUI.fileItem`/`findFile` match that label and scroll "File View";
  a failed pick cancels the picker so later steps do not fail behind it ("<control> is reachable in Settings"). The
  Photos picker's first images are its "Private Access" header icon and a dimming overlay: pick the grid's
  "PXGGridLayout-Info" images (labels "Photo, November 18, 6:51 PM"), newest by that date. iPadOS 26 lists menu
  choices and the Files tab bar's Browse twice (a button inside a button): use `firstMatch`. A SwiftUI alert's
  TextField has no accessibility identifier: query `alerts[<title>].textFields`. Reading `.value` of an element that
  does not exist records a failure at once, so a `wait { el.value == x }` never retries: check `exists` first.
  Twelve slow swipes do not reach Storage at the end of the iPad Settings panel: follow with full-speed swipes.
  `-uitestDefaults` keys now survive a plain relaunch (no `-uitestDefaults`, no `-uitestResetNotice`); before, the
  relaunch removed them and the visual fell back to projectM.
- **Pickers on the iPads, pass 4 (2026-11-19):**
  - Tap a Files cell only once its scroll has stopped. A full-speed swipe of "File View" decelerates for 2 s or more,
    and a tap on a moving grid only stops it: nothing was picked, no Open came, the picker stayed up (D2, iPadOS 27.2;
    "No photo"/"No video"). `SystemUI.findFile` now waits until the cell's frame holds still (`settle`), and
    `tapFile` taps again when the picker is still up 4 s later.
  - The Photos picker's grid images ("PXGGridLayout-Info") exist but are never hittable on iPadOS 26.5 (another
    process's view): pick by frame inside the window and tap by coordinate ("the Photos picker shows no items", D3).
  - A one-item Photos picker closes on the tap, so do not look for its Add/Done: the "Done" found was the app's own
    Settings Done, which closed the panel (D2). Tap Add/Done only for several items, never the Settings bar's Done.
  - The library seed dates each fixture now, one second apart (`PHAssetCreationRequest.creationDate`). Undated, Photos
    dated a PNG or GIF by the file (installed the day before), so "newest" was an older slide, not the GIF just
    seeded (MED-008, D2). Picker labels carry minutes only: ties follow the grid's own direction.
  - A notice row added below the Photo buttons is under the fold, and a SwiftUI List builds no off-screen rows: drag
    the list before concluding the notice never came (MED-001-T24 "40 MB notice", D3). Same for a summary row after a
    relaunch: scroll to it first (MED-006).
  - An ACC-005 slider row is an adjustable element, not an XCUIElement slider: `app.sliders[id]` never matches. Find it
    by identifier and drag its line (`dragRowSlider`), as UITestSliders does (MED-006 stayed at the default 5 s).
  - A test whose Photos seed did not add every fixture (prompt still up, fixtures missing) stops at once
    (`waitLibrarySeed` returns false): run `mac_device_driver.py prompt-flow` first on a fresh install.
- **Camera and media tests on the iPads, pass 4 (2026-11-19):**
  - XCUITest cannot read the iPad's Control Center camera pill ("kAXErrorServerNotFound" for the remote element):
    `SystemUI.controlCenterGreenPillVisible` counts system-green rows in the screenshot's top right instead (camera
    in use: 31-53 rows; recently used, grey pill: 0; pass at 8).
  - After a return from the background, wait for "Active audio" in the performance overlay before any pixel check: D2
    drew its first frame about 1 s later than D3 (CAM-011).
  - A `keep: true` permission change must drop earlier restore steps for that permission; otherwise teardown queries a
    backgrounded Settings app and times out (CAM-013).
  - A synthesized tap on a DEBUG probe button was lost on the device every time (CAM-005): trigger the probe with a
    Darwin notification posted by the test (`CFNotificationCenterGetDarwinNotifyCenter`), and keep the tap as a fallback.
  - Closing Settings leaves the controls up for 5 s, covering the iPad's corners and the middle: hide them
    (`B07Case.hideControlsForShot()`) before measuring a screenshot, and leave out the Emergency Blackout button.
  - Seed the media a feature test needs (`-uitestSeedVideo`, `-uitestSeedPhoto`, `-uitestSeedLogo`) instead of picking
    it, so a picker failure fails only the picker tests.
- **"Main thread busy for 30 s" is a deadlock until shown otherwise (2026-11-19):**
  - XCTest attaches a `Spindump_*.txt` to a test that fails this way: export it with
    `xcrun xcresulttool export attachments --path <bundle> --test-id <id> --output-path <dir>`; it names the blocking stack.
  - The attached spindump can be empty ("No samples", D3 pass 5): then the SIGABRT crash report below is the only
    source of the stacks.
  - A Time Profiler trace shows nothing for a blocked thread (it samples only running threads): in the D2 trace the main
    and render threads had no samples for 120 s. To get every thread's stack, send the stuck app SIGABRT
    (`devicectl device process signal --pid <pid> --signal SIGABRT`) and copy its crash report from `systemCrashLogs`.
  - Never wait on the main thread for work that may need the GPU across a background transition: a backgrounded app's
    command buffers do not complete, so `waitUntilCompleted` (inside ANGLE) never returns.
  - A lifecycle gate cannot catch a wait that begins while the app is only inactive (it must keep drawing then). Read
    the frames under the wait before choosing a fix: the AUD-016 stalls on D2 and D3 waited inside ANGLE's emulation
    of `GL_TRIANGLE_FAN`, so the fix removed fans and line loops from the engine (projectM patch 5) instead of gating
    more lifecycle states.
- **A probe that decodes positions from sample values must skip trailing zeros**: a track's last tap buffer ends in
  silence, which decoded as "no position" and hid the track change (AUD-003).
- **Killing the app mid-test leaves its system state behind (2026-11-19).** A SIGABRT sent to get a stalled app's
  stacks ended AUD-016 before its restore, so the 5 s Clock timer it had started rang on D2 over and over until the
  owner stopped it. `startClockTimer` now stops a ringing timer first; after any forced kill, check for and stop
  leftover timers, Control Center, Settings toggles and Files pickers before the next batch.
- **Run devices one at a time when the owner asks**, and never start a device the owner has not prepared (Auto-Lock,
  unlocked). Report each device idle at once with what passed, what did not and why (owner rule 11).
- **Batch 7 on D1-D3 (2026-11-18), what the first run taught:**
  - An ACC-005 slider row reports `isHittable` false even fully on screen: reveal by frames (as UITestWaits), or every
    slider reveal fails and drags the list away, taking lazily built rows (and the probes in them) off the tree.
  - A probe sampled every Nth frame aliases with a strobe whose period divides N: every sixth frame always read the
    unclamped phase of the 2-frame strobe fixture. Sample at a period coprime to the strobes you test (7).
  - An accessibility element's frame can be the whole row (an image centred in a full-width frame): measure inside the
    content, or the background's edges dominate (SHD-006's Laplacian).
  - Find where the content is before comparing pictures: the spectrum waterfall fills from the top over 60 s, so the
    middle band was black; the performance overlay covered the drawn part on D1 and D3, and its text gave the
    kaleidoscope's "seam". Leave `overlayBox()` out or turn the overlay off for picture statistics.
  - Test the fixture's real structure, not its label: the music fixture's quiet-to-loud step is at 10 s (drums enter),
    the "chorus" at 20 s is only +5 dB, so ANL-015 correctly fires once at about 12 s.
  - Seeded shows start with cue 1 active but no running playhead: seek (scrub) before measuring the timeline, and tap a
    tempo before turning on bar-synced rotation (a scripted estimate has no beat phase).

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
- **`-only-testing` takes the target's BlueprintName, not its Swift module name** (`projectM-iOSDeviceUITests/B05…`,
  not `projectM_iOSDeviceUITests/…`; `plutil -p <xctestrun> | grep BlueprintName`). With the module name xcodebuild
  stops at once: "isn't a member of the specified test plan or scheme".
- **The Mac's `/bin/bash` is 3.2**: no `mapfile`, and `"${args[@]}"` of an empty array fails under `set -u`. Read
  filter files with `while IFS= read -r`, and expand with `${args[@]+"${args[@]}"}` (`run_device_ui_tests.sh`).
- **"Timed out while enabling automation mode"** (D2, 2026-11-19, unlocked, after a lost connection mid-run): the
  runner cannot turn on UI automation; retrying does not help. Cause found later that day: a rebuilt (newly signed)
  test runner makes iPadOS ask for the passcode before it allows UI automation, and the runner gives up after about
  60 s if nobody answers. Toggling Enable UI Automation, killing leftover processes or restarting testmanagerd did
  not help. After every rebuild of the device tests, start the run while the owner is at the devices and have them
  enter the passcode at the prompt; batch rebuilds so this happens once per session.
- **Siri can leave the device unable to start UI tests.** On D3 (2026-11-19) `siriService.activate` brought Siri up but
  its window "has not loaded accessibility"; the runner then exited and every later launch, on that run and the next,
  failed with "Timed out while enabling automation mode" (D2 showed the same after its lost connection). Siri steps
  now run only when asked for (`SIRI=1 scripts/run_device_ui_tests.sh …`, in their own batch, last); every other run
  skips them at once with `SiriAvailability.skipReason`.
- **GitHub skips a push whose head commit message contains the literal `[skip ci]` anywhere**, even quoted inside a
  sentence. A follow-up commit that "undoes" a wrong skip must not mention the marker (2026-11-19).
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
- **Invisible elements still take the accessibility hit test.** `isHittable` asks the accessibility tree what lies at
  the element's centre. At AX5 the performance overlay and a DEBUG probe text (opacity 0.01) grew over the transport,
  which was drawn whole, and every button read "not hittable" (AUD-006-T41, D1-D3). DEBUG probes keep one text size
  (`.dynamicTypeSize(.large)`); a test of a control's layout at AX5 runs without the overlay.
- **A probe's delivered positions lag the audio by up to one tap block** (100 ms): compare a resume with the held,
  shown position, not with the last delivered sample (AUD-006-T39).
- **Compare two runs over the same part of the fixture.** The music fixture has a quiet intro, a verse and a loud
  chorus; each launch leaves playback at a slightly different point, so two 10 s windows taken "after launch" can
  set one section against another (AUD-008-T13 on D3, pass 3). Sample by the track position (`-uitestPlaybackProbe`
  `pos`) and compare per-second bins both runs hold. And check the measurement's form: the band levels are decibels
  over a fixed floor, so a gain adds to them; a relative margin was the wrong rule.
- **Wait for the state the fixture can reach.** A click or pulse fixture is mostly silence, so it reads "Audio
  received — silent" while it plays (FR-011); `launch(..., playing:)` names the states that count as playing.
- **Read a probe before the step that removes it.** The recording status lines exist only while recording; reading
  one after Stop fails the query ("No matches found"). Keep the copy taken while it showed.
- **Name the precondition before recording.** A file without its expected audio track says nothing about why; the
  DEBUG `recordingAudioDecision` probe reads the decision the next recording gets (source, setting, microphone
  permission), and the test fails on the named cause first.
- **Few samples make a percentile meaningless.** The 5th percentile of 10 one-second windows is the worst second
  (a cold shader cache after a fresh install). Use 60 windows or more; record first-launch costs separately.
- **Pass 3 on D2 and D3 (2026-11-19), what it taught:**
  - *Read the spec's own placement before asserting one.* ACC-010's left-handed landscape pad puts the cue column
    trailing; the test asserted the right-handed placement. SHOW-010 draws only bars when beats would be under 4 pt
    apart (R2); the test assumed every beat is drawn. Derive the expectation (here the stride from the track width).
  - *Don't time events off a display that redraws at the event's own rate.* The beat readout redraws twice a second
    at 120 BPM: intervals between seen changes alias (0.73/0.29 s on D3). Fit the count over time instead.
  - *Rare events need a statistical allowance.* Skipped refresh slots (7 vs 15 of 3,600) are Poisson counts; allow
    3·√(a + b), not a fixed 5 slots.
  - *Compare like with like.* A luma cut picks hues by itself (FX-002's bright pixels); compare the same cut with and
    without the effect. A mean of three picture pairs is one outlier (a music-driven mode change, VIS-019): use the
    median of five.
  - *A probe answer must belong to this tap.* Two probe buttons sharing one `@State` answer let a decrement read the
    increment's "performed"; number each button's answers and wait for a new one. Probe buttons at the bottom-leading
    corner of the visualizer never got the test's taps on the iPads (the value stayed at its launch text): put probe
    buttons top-leading like the other DEBUG panels, and let a probe refresh itself when its input (a new file) appears.
  - *Fixtures must produce the condition without the music.* ACC-002's Strobe fixture was meant to flash only on strong
    bass; FX-019's device test uses `fixture:flicker`, a whole-frame inversion two frames in four. *Prove a projectM fixture
    renders as designed with a host test before a device run:* projectM 4 ignores per-frame `invert` and `gamma` (the
    fixed-function filters read the file's bInvert/fGammaAdj, and a version-201 preset takes the composite-shader
    path), so the first Flicker drew a steady dark frame on D3 (rerun 3, 2026-11-19). The inversion now lives in the
    composite shader, and `FlashLimiterTests` renders the same text through projectM and the envelope. The Strobe
    fixture had the same flaw, hidden because its test passed: ACC-012-T22's Strict clamp came from the rise limit on
    ordinary motion. It now inverts at 1.5 Hz in its composite shader (Standard allows it, Strict clamps it), also
    proven on the host. *A passing check can be vacuous:* when a fixture's effect is the premise, assert the effect
    (the frame really flashes; the reference really stays unclamped), not only the outcome under test.
  - *Hittable is not on screen.* XCUITest calls an element hittable when its centre is on screen, so a Files cell cut
    in half by the bottom edge counted as found and the tap selected nothing (D3, AUD-002-T27). `SystemUI.findFile`
    requires the item wholly inside the window and `tapFile` taps again while Open stays disabled.
  - *A tap on a coasting grid only stops it.* In a single-selection Files picker on iPadOS 27.2 (D2, FILE-009,
    PRE-012, PRE-014, 2026-11-19) the first tap after a swipe stopped the scroll and picked nothing; no Open button
    came, so the old `tapFile` took the silence as a pick and the test went on behind a picker still up. `tapFile`
    now waits for the item's frame to hold still, counts a single-selection pick only once the picker is gone, taps
    again otherwise, and `filesPick` fails with "the picker did not take <file>".
  - *Settings sections that swipes cannot reach:* on the iPad panel neither slow nor full-speed swipes reached
    Settings › Storage below the photo visual's sections (D2, D3). Tests that also use the top of Settings launch
    with `-uitestSettingsJump storage` (DEBUG): a navigation bar button `uitestSettingsJump.storage` scrolls to the
    section on a tap (`openStorage`). It began as a faint 44 pt square overlaid on the list's bottom-left corner; on D3
    (pass 5) XCUITest tapped it but the touch reached the visual row underneath ("Reaction Diffusion" was chosen) and
    nothing scrolled, so FILE-009 never reached Storage and PRE-001 then had no Presets control under the native visual.
    *A test-only control goes where no row can take its tap* (a bar, never overlaid on a list).
  - *Never write a non-finite number in a report.* `JSONSerialization` raises an Objective-C exception on NaN or
    infinity, which ends the whole xcodebuild run (FILE-009 on D3: a ratio over a zero total); `report` writes null.
  - *Reading a missing alert's label fails at once.* Guard `alert.exists` before `label` (PRE-012 on D2 restarted
    the runner).
  - *iPadOS takes a slow drag of a switcher card as a move.* Flick it (`swipeUp`, then a fast short drag) and check
    that the app ended after each try.
  - *Run an accessibility audit with the controls held up* (`-uitestKeepControls`); an audit during the fade catches
    half-transparent text.
  - *Read a changing tree once.* The share sheet builds its rows after it appears; reading
    `allElementsBoundByIndex` element by element failed with "No matches found for Element at index 36" (REC-012,
    D2 and D3). Collect labels from one `app.snapshot()` instead.
  - *A diagnostic overlay must sit below what a person taps.* With the performance overlay on, D3's narrower portrait
    screen put it over "Frame ready"; Save… had hit point {-1, -1} and never opened the exporter (REC-001). The overlay
    now draws below the panels (`VisualizerView.layers`).
  - *A disk ballast must aim at the figure the guard reads.* On D3 the important-use capacity stayed 0.4-2.8 GB above
    the real free space while 77 GB were written, so the ballast never reached its target and the guard never stopped
    (REC-009, REC-015). The guard and the ballast now read the smaller of the two (`VolumeStorageReading.guardBytes`),
    and the fill checks its time budget between 16 MB chunks.
  - *Files folders hold the fixtures.* On My iPad › projectM lists about 50 fixture files by name, so a "Visualizer
    Recording" sits below the first screen; scroll until its cell is built (REC-003).
  - *A host test that counts frames must not race a background queue.* Wait for the background work before the frame
    whose count matters (MED-011's clock test, 120 vs 119 in CI).
- **Pass 5 on D3 (2026-11-19), B07 files and presets:**
  - *Know which outcomes the app announces instead of alerting.* Import Preset… alerts only when the result needs
    attention (PRE-012-R28); a clean add is announced and its row appears. PRE-012 and PRE-014 waited 30 s for an
    alert after a successful import and failed. `importPreset` now takes the alert or the new `preset:<name>` row.
  - *A popover anchored to a whole sheet lands in the strip beside it.* The export share sheet pointed at the Export
    Presets sheet's full bounds, so the iPad put the popover in the 260 pt below it with Save to Files off screen
    (hit point {-1, -1}). `ShareSheetPresenter.popoverAnchor` points at the top trailing corner (the Export button);
    `revealShareActivity` scrolls the popover when an activity is still not hittable.
  - *Audits find real defects:* Quarantine's trash glyph failed the hit-region audit; it is now a 44 × 44 pt target.
- **Pass 4 on D2 and rerun 4 on D3 (2026-11-19), what it taught:**
  - *Put a DEBUG probe button where nothing else is.* The split editor's divider probes sat at the window's top-right
    corner, on the editor's undo/redo bar; the bar took the decrement's tap (its numbered answer stayed empty). They now
    sit in the divider's own column (UIX-007-T13).
  - *Let transient captions clear before a contrast audit.* The 4 s "Output restored" caption lay under the
    performance readout and the audit measured the readout's text over the caption's (ACC-003-T17). Wait for
    `statusCaption` to go.
  - *Look at the audit's screenshot, not only its message.* ACC-003's "Save Frame" contrast failure came with every
    iPad-portrait control title squeezed one or two letters wide: a real layout defect (now the compact layout when
    the labeled row does not fit), and the performance readout's fixed 0.6 backing ignored Increase Contrast.
  - *A missing permission grant is a precondition, not a result:* skip with the instruction only when a later step is
    sure to run the test with the grant (`AFTER_GRANTS` in the prompt flow).

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
