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
| MIDI controller | `Apps/projectM-iOS/Debug/UITestVirtualMIDISource.swift` (`-uitestVirtualMIDISource`) | A DEBUG CoreMIDI virtual source and destination ("QA011 Test Source") inside the app; `B10MIDIDeviceTests` tap `midiProbe.<scenario>` and it sends CC, notes, programs, 14-bit pairs and clock through the system's MIDI service; the destination counts the app's MIDI feedback. The Mac driver `scripts/mac_driver/midi.py` is retired (network MIDI is excluded); its `SCENARIOS` table stays as the byte reference. |
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
- **Mic preflight (QA-011 pass 9, 2026-11-19):** the first microphone test that needs the Mac's sound measures, once
  per run, the gate probe's level with the Mac silent and then with the music (`requireMicHearsMac`, DEVICE-ACCEPT
  step "mic preflight"); under +10 dB every such test fails at once with "ENVIRONMENT, not the app". On D2 in pass 9
  the driver played every request on time (the MAC-DO ids, which are epoch milliseconds, matched the MAC-DONE times)
  yet the level went from -75 dB quiet to -81 dB with music, and five tests failed late with gate, trim and "silent"
  messages; in full 8 the same iPad read -61.5 dB quiet and the music opened the gate. The driver's `audio.play` and
  `audio.tone` answers now name the Mac's output volume and warn when it is muted or below 25, or when afplay exited
  at once.
- **The microphone has no transport:** after a real interruption it runs again by itself ("Active audio", or "Audio
  received — silent" in a quiet room) or shows "Interrupted"; `realInterruption` checks that and never looks for
  `transportPlayPause` in Microphone mode. On iPad the app's icon is on the Home Screen and in the Dock: tap the first
  hittable match, not `icons[name]`.
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
| `rendererlab-flashcost` | part of FX-019-T22 | RendererLab `RL_MODE=flashcost`: strobe pass cost ≤ 2 ms per frame on every starter preset (judged on the pass's GPU timer-query time, begun after the engine's frame has finished, plus CPU encoding on the frame it processes, `passIsolatedCostMedianMs`, since 2026-11-24; on minus off reported) (builds RendererLab into `Build/rendererlab` when missing) |
| `xctrace-perf004` | PERF-004-T16 | Logging template on the Text visual (`PROJECTM_VISUAL=text`, the default since 2026-11-23): "PERF-004 texture allocation" signposts only before the visual is up + 5 s (marker `QA-011 ready`, after playback start returned) and within 3 s of each rotation (perf004 rotates 10 s after `ready` and back at 20 s; time limit 50 s; xctrace then takes 3-5 min on D1 to save) |
| `xctrace-perf011` | part of PERF-011-T21 | Metal System Trace + os_signpost; counted from the moment the app's process appears, the Mac opens Settings at 10 s and relaunches the app at 26 s (app runs 40 s, time limit 70 s; a recording that never ends is stopped with SIGINT and fails the case): no frames (and no GPU intervals of the app) from 10 s after backgrounding until the return (willEnterForeground, marker `QA-011 return`), a lower footprint, the first frame within 2 s of the return |
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
  `background`, `return`, `foreground`) so trace times line up with the run; add `--instrument os_signpost` to templates that
  lack it (Metal System Trace, Power Profiler). `xctrace record --show-recording-options` lists a template's
  configurable instruments.
- **Backgrounding from the Mac**: `devicectl device process launch <id> com.apple.Preferences` sends the app away; a
  launch of the running app without `--terminate-existing` brings it back. The app holds a background task while
  away so its sampler can read footprint and frame counts (perf011). First D1 run 2026-11-23: see the lessons below.
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
- **An audit issue with no element can be a covered view** (D1, 2026-11-24): `type=1 id="" label=""` on the
  tutorial's Visual step was the source chooser under the opaque tutorial. `accessibilityHidden` (and `opacity(0)`)
  does not keep UIKit-hosted list cells out of `performAccessibilityAudit`, which then measures their texts against
  whatever is drawn over them. To find such an element, run the same audit on a simulator of the same size class
  and print `issue.element` snapshots with frames (the iPhone 15 simulator reproduced it). Fix in the app: don't
  build a screen that is fully covered.
- **iOS 27.0.1 (D1) keeps the app active while the Local Network prompt shows** (2026-11-24): the probe trace
  `start 1, browsing, stop, settled → granted` has no `inactive`, so a settle timed in active time granted before
  Don't Allow and the denied notice never came, on every D1 run, while D2 and D3 passed. Never infer "the prompt is
  answered" from the app's activity: a grant without positive evidence is unconfirmed and rechecked by fresh browses
  (ADR-0125 follow-up 3); a fresh browse reports `failed policyDenied` once denied. Read the probe trace the test
  prints before changing the test: here the test had tapped iOS's real "Don’t Allow" correctly.

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
`B10MIDIDeviceTests` (the app's DEBUG virtual MIDI source as controller), `B11OutputDeviceTests` (the DEBUG fake external display). Shared steps
are in `ControlSurfaceSupport.swift`; system UI goes through Batch 1's `SystemUI.swift` (one bridge section). Values
the Mac knows reach a test as `TEST_RUNNER_<NAME>=<value>` on the xcodebuild command (`MAC_IP`, `PEER_IP`); a
missing one skips with the reason. AirPlay to the Mac and USB-cable steps (Airplane Mode, Wi-Fi
outages) are not required (owner ruling 2026-11-18).

```bash
# Single device, OSC (D1): start the driver, then the tests (each -only-testing is its own argument).
# (OSC=1 scripts/run_device_ui_tests.sh does this for you: listen port 9100 + device number, driver lives the whole run.)
python3 scripts/osc_device_driver.py --log Build/b09-D1.log --host iPhone77.local --listen-port 9101 --timeout 43200 --device D1 &
xcodebuild test-without-building -xctestrun <copy>/…xctestrun -destination platform=iOS,id=<D1 UDID> \
  -only-testing:projectM-iOSDeviceUITests/B09OSCDeviceTests -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 300 TEST_RUNNER_MAC_IP=<Mac LAN address> TEST_RUNNER_MAC_OSC_PORT=9101 > Build/b09-D1.log 2>&1
# MIDI (D1, D2): -only-testing:projectM-iOSDeviceUITests/B10MIDIDeviceTests, no Mac driver (the in-app virtual source).
# Rehearse on a simulator first (never evidence): copy music-fixture.m4a into the app's Documents, then
#   TEST_RUNNER_SIMULATOR_REHEARSAL=1 xcodebuild test-without-building -xctestrun <simulator xctestrun> …
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
- **First D2+D3 peer run (2026-11-22, `--as D1=D3`): all three failures were test or runner faults, plus one
  accessibility-tree fault in the app.** `peer.py` delivered `TEST_RUNNER_PEER_IP`/`MAC_IP` through `env` to both
  sides (the logs print them), Local Network was granted, and iPadOS 26.5 and 27.2 behaved alike. What went wrong:
  - *A row container's label is empty.* Nearby Devices showed "projectM 76C7 / 192.168.1.219:9000" (IPv4, resolved;
    screenshot), but the found row is `.accessibilityElement(children: .contain)`, so its `label` was `""`. Read a
    row's child texts (`rowTexts` in `B09OSCPeerDeviceTests`), never the container's label.
  - *A row identifier on a plain `HStack` replaces its buttons' identifiers.* Approved Devices' rows carried
    `.accessibilityIdentifier("oscApprovedPeer_N")` without `.accessibilityElement(children: .contain)`, so
    `oscRemovePeer_0` and `oscAllowPeer_N` never existed (OSC-008 on D3). Fixed in `OSCPeersView.swift`; the
    simulator test `OSCPeersUITests.testApprovedRowKeepsItsRemoveButton` fails without the fix and passes with it.
    Any row that carries an identifier and contains identified controls needs `.contain`.
  - *Match addresses whole:* "192.168.1.2" is a prefix of "192.168.1.219"; the peer tests use `shows(text, address)`.
  - *Stamp a lead step before the tap.* XCUITest's tap (idle wait, event synthesis) plus the readout query took
    longer than the OSC hop, so D2 printed `PEER-SEEN` 0.1-0.26 s before D3's `PEER-STEP`. The follower stopped after
    12 changes while the lead stepped 26 times, and `pair_latencies` searched without a bound, pairing a step with
    the same cue 18.1 s later (the "max 18.1 s"). Now: the step time is taken before the tap (it can only overstate
    latency), the follower runs until 20 s without a change (at most 240 s) and ignores a missing readout, and a
    match must fall within [t - 0.25 s, t + 3 s] or the step is unmatched. Every cue the follower printed had followed
    the lead within ±0.26 s, so the app's cue sync was not the fault.
- **Network MIDI is excluded by the app's own policy, so B10 uses an in-app virtual source (2026-11-21):** the app
  drops network-attributed MIDI endpoints (MIDI-001-R2, R14; ADR-0038) and both compliance scans reject `MIDINetwork*`,
  DEBUG included, so the Mac's network session can never reach it and USB-cable tests are not required. With
  `-uitestVirtualMIDISource` a DEBUG build creates a CoreMIDI virtual source and destination named "QA011 Test Source"
  and a small probe window above every sheet; the test taps `midiProbe.<scenario>` and the source sends the retired Mac
  driver's bytes (`scripts/mac_driver/midi.py` `SCENARIOS`; `test_scripts.py` keeps the tables equal) through the
  system's MIDI service to the app's real discovery, input, mappings, clock and feedback (MIDI-001 Clarifications,
  QA-011 device run 2026-11-21). Readouts: `midiProbeStatus` ("ready" or "failed <status> <step>"), `midiProbeQueued`,
  `midiProbeRuns`, `midiProbeFeedback` (MIDI-009's verdict: at most 60 messages back, none 1 s after the moves).
- **Virtual MIDI endpoints need `audio` in UIBackgroundModes:** iOS refuses `MIDISourceCreate`/`MIDIDestinationCreate`
  with -10844 otherwise (CoreMIDI headers; seen on the simulator too). Only the Debug device-test host built from
  `DeviceTests.yml` gets `audio` (post-build script), and only when built with `QA011_MIDI_HOST=YES` into
  `Build/device-acceptance-midi`: with `audio` the host keeps playing in the background, which would change what every
  background test measures (AUD-006, PERF-011, CAM-011). `project.yml`'s app and every shipping build keep
  `[screen-capture]` alone (ADR-0001 ruling 17). On the ordinary host B10 skips ("failed -10844") with the build command.
- **A post-build Info.plist edit needs the plist as an input file:** without `inputFiles: [$(TARGET_BUILD_DIR)/
  $(INFOPLIST_PATH)]` the build system ran the device-test host's plist script before Info.plist processing on a
  rebuild, and the processed plist dropped its keys (the file-sharing keys too). Check the built plist with PlistBuddy.
- **A window above the sheets is not "hittable" to XCUITest:** the probe window (window level alert + 1, never key)
  is drawn and receives touches, but `isHittable` is false and `tap()` fails to "scroll to visible"; tap its buttons at
  their screen point (`coordinate(withNormalizedOffset:)`) and confirm with a readout (`midiProbeQueued`). Turn off the
  hosting controller's safe-area regions so its content stays inside the small window.
- **MIDI moves the glow's live value, not its manual value:** the MOD-002 readout's "manual" never changes with MIDI or
  OSC input (they are `externalValues`); read "effective" with the glow unbound. `-uitestDefaults` is written at every
  launch, so a relaunch that must keep learned state removes those keys from it first (MIDI-003-T17).
- **Readouts limit what a test can prove:** MOD-002's glow readout has two decimals, so MIDI-005's "> 1,000 steps"
  shows as at most ~100 distinct readings; a finer probe is needed for the full criterion.
- **Simulator classes cover device-only reruns:** SHOW-007/008/009 and SHOW-012's row label run as
  `projectM-iOSUITests/ShowTimelineUITests`, `ShowKeyframeUITests`, `ShowKeyframeEasingUITests`, `CueNoteUITests` on
  the device through the DeviceAcceptance scheme.
- **Windowed Apps covers, it does not replace; the test tiles the windows itself (UIX-008-T16, 2026-11-21):** on D2
  with Windowed Apps on, "Open in New Window" opened the editor window on top of the visualizer's (full size when the
  visualizer's was, otherwise at the editor's remembered size), so `visualizerTapArea` existed but was not hittable and
  the test skipped as if Windowed Apps were off. There is no public API to place a new iPadOS window (only orientation
  in `UIWindowScene.GeometryPreferences.iOS`; the spec leaves placement to iPadOS), so the test arranges the windows
  through springboard's own window UI, as a person would: the app's windows are springboard's
  `card:<bundle>:sceneID:<id>` elements (front first, screen points); a full-size window shows no window controls, so
  its `resize-grabber` ("Resize projectM") is dragged in first; then `window-controls:<bundle>` (the three dots) is
  tapped and the Zoom button held for 1.2 s, which opens Move & Resize / Fill & Arrange; "Left and Right" tiles the two
  windows. Springboard lists each control twice and the copies report `isHittable` false, so they are pressed at their
  frames. One app window on screen is the real replacement (Full Screen Apps) and the only case that skips; two
  windows that still overlap after arranging fail. In a half-width window the visualizer's Settings panel becomes a
  full sheet over the output, so the test closes it (Done) before checking that the visualizer is hittable. Rehearsed
  on iPad simulators with Windowed Apps on (`defaults write com.apple.springboard SBChamoisWindowingEnabled -bool YES`,
  then reboot the simulator): iPad Pro 13-inch (M5) iOS 27.2 from a full-size and a remembered-size editor, iPad (A16)
  iOS 26.5, and the skip with the key set to NO (never evidence).

## Camera (QA-011 Batch 4, 2026-11-18)

Tests: `B06CameraDeviceTests` (its Batch 4 extension: CAM-002-T21/T22, CAM-004-T08, CAM-005-T14, FX-009-T18,
REC-003-T23 Camera, CAM-007-T15/T16's crop modes from `cameraPictureRect`) and `B06CameraSystemDeviceTests` (CAM-001-T24/T26/T27, CAM-002-T21's
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
  Since 2026-11-20 REC-009 and REC-015 also pass `-uitestDiskGuardReserveMB 8000` (DEBUG): the guard keeps 8 GB
  instead of 200 MiB, and the ballast aims at 8390 / 8490 MB, so the real guard reads real free space and stops a real
  recording while the device still has 8 GB free.
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
| `…/testFILE001_A_ExportSceneArchive` (D1; DEBUG seed `-uitestPhotoVideoScene`), then `…_B_ImportSceneArchive` (D3) | FILE-001-T19 (offline: not required) | D1 → D3 | Mac driver (`files.pull` on D1, `files.push` on D3) |
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
  unreadable trace. Never leave it unwatched either: `xctrace.record()` stops it with SIGINT once 7 minutes have
  passed since the recording ended and the bundle has not changed for 1 minute, or at launch + time limit + 8 minutes
  (2026-11-24; an idle bundle right after the recording is not a hang, see the lesson below). `xctrace export --toc` lists the tables; Metal System Trace exports `metal-gpu-intervals` and
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
  - A notice that clears itself (6 s) cannot be found by dragging afterwards on a slow device: on D2 each slow drag
    of the 1376 pt panel took 3.5 s, and the 40 MB notice was gone before the first one settled (MED-001-T24, every D2
    run). Make room before the action instead: `pickFromFiles(..., roomBelow: true)` drags the picker button into
    the upper third of the list first (`raiseInList`) and skips the pause after the pick. Scroll back to a summary row
    above the buttons before reading it.
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
- **Media and share tests on D3, pass 5 (2026-11-19):**
  - *Set a slider through its VoiceOver step, not a drag,* when the value matters: a drag from a computed thumb position
    missed on the iPad's Settings row and left Seconds per picture at 5 s (MED-006). Launch with
    `-uitestAccessibilityActions`, tap `<id>.uitestDecrement` and read the value back.
  - *Derive a rate check from the rule that limits it:* "a slide per beat at 120 BPM" is held to MED-006-R7's 1 s
    safety floor, so 6 slides in 6 s can never pass. Measure the gaps between changes and assert the floor and the
    median.
  - *Keep pixel bands clear of the iPad's controls panel* (from 66 % of the height in portrait): MED-008's GIF bar was
    measured at 70-74 % and was seen once in 20 pictures although the GIF played.
  - *Parse counters as digits:* SwiftUI shows an interpolated `Int` with a grouping separator ("1,234"), so `Int(label)`
    became nil past 999 (MED-014).
  - *Tap a result panel only once it has stopped moving:* the panel moves up when the controls hide (5 s after they
    were shown); a tap computed before the move hit the visualization, so Save… never opened the exporter (REC-001).
  - *`app.snapshot()` can fail on a remote view (the share sheet) while queries still reach it:* check the labels you
    need with queries (REC-012).
  - *Files in iPad portrait keeps its sidebar over the folder* after a sidebar choice: tap the folder's cell, and close
    the sidebar first when the cell is not hittable (REC-003).
  - *A disk ballast must end within the guard's stop line,* not anywhere within a growth step of the reserve: shorten
    the last step (REC-015).
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
- **iPhone system apps differ from the iPad ones (D1, iOS 27.0.1, 2026-11-22).** Clock's Timers tab on the iPhone has
  no "Start" button: the start control is a glyph button labelled "play" (next to "Close", "Edit" and a disabled
  "chevron"), so `clockTimerStartButton` tries "Start", then "play", preferring a button outside list cells (a recent
  timer's own play button would start its duration). Settings › Battery has no Low Power Mode switch any more: it sits
  under Battery › Power Mode, which `openSettingPage(.lowPower)` follows, then Settings search; when the switch is
  still missing it prints the page. Expect every system-app helper to need an iPhone path checked on D1.
- **D1 rerun 5 (iPhone 15, iOS 27.0.1, 2026-11-23): what the iPhone does differently.**
  - *Read an interrupted run's result bundle anyway.* It has no Info.plist, but `Data/data.0~*` are zstd blobs: the
    HEIC/PNG screenshots, the "App UI hierarchy" text attached at each failure, and an activity summary that names each
    attachment with its timestamp. Decompress them (`zstd -dqc`), map step times to screenshots, and look before
    guessing; every cause below came from those files.
  - *A row under the floating search field is "hittable".* iOS 27 floats Settings' and the preset browser's search
    field over the foot of the list on an iPhone; the row's frame is inside the window, so `isHittable` is true and the
    tap opens the search (MED-006's switch vanished, PRE-012/PRE-014's My Presets never opened). `ControlSurfaceCase
    .scrollTo` and B07's `tapControl` now require `reachable` (clear of `bottomChromeTop`), and `openNode` taps again
    until the row's list shows.
  - *The iPhone's Files picker remembers its folder and its tab.* It opened on Shared, and Browse then showed projectM
    itself, so "On My iPhone" was nowhere. Save to Files opens a mover already in projectM with Save at the top and no
    tab bar; a "Browse" button existed for a moment while it came up and the tap on it failed. `filesPick`/`filesSave`
    now act in the app's folder when its title shows (`pickerInAppFolder`), tap Browse only while it is still there
    (`tapBrowseIfShown`), and tap Browse a second time to reach the locations from inside a folder.
  - *The iPhone's Files picker is a sheet with a half-height detent.* A swipe down at the top of a folder lowers it
    to half the screen; the grid left the tree for a moment, the pick "counted", and the picker covered Settings for the
    rest of MED-001 ("choosePhotoFromFiles is reachable in Settings"). `expandFilesSheetIfShrunk` drags inside the
    grid to raise it, and a single-selection pick counts only when the picker is still gone a second later.
  - *The iPhone's Control Center has the iPad's green pill.* "projectM  Controls ›" with camera and location icons and
    no "camera" label; the pill rules now apply on every device, scanning the whole width of the top 12 %. A second
    open can show a compact header (green camera glyph and "projectM ›", no pill); read its label before deciding.
  - *Reveal taps go off-centre on a phone.* After REC-003's 60 s recording, four taps at the tap area's centre (where
    the DEBUG probes stack) never brought the controls back; `tapCameraControl` now taps at 62 % and 70 % of the height,
    as `showCameraControls`. The run also showed the thermal notice "The device is getting hot…" at 30 fps.
  - *Picture checks must leave out every always-shown pill.* MED-010's bottom-right "dark fringe" (87 pixels) was the
    right end of the source status pill, which reaches the last 110 pt of a 393 pt screen; recomputed without it: 0.
  - *A lost connection can leave xcodebuild silent for good.* D1 left the Mac while MED-014 set up its automation
    session ("The connection was invalidated", Mercury 1001; nothing in the test or the app ran yet), diagnostics
    failed three minutes later and xcodebuild then sat silent until stopped by hand. `run_device_ui_tests.sh` now ends
    a run 5 silent minutes after such an error, or after 15 silent minutes of any kind.
- **Wait on a run by its process ID, never with `pgrep -f <name>` from a shell (2026-11-19).** A wait loop
  `until ! pgrep -f round5.sh` matched its own command line, so it never ended and both iPads sat idle for an hour
  after their runs had finished. Save `$!` when starting the run and poll `kill -0 <pid>`.
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

  - *Never fill a device to within a gigabyte of full.* D2 left the network (devicectl "unavailable", xcodebuild
    waiting for the destination for two hours) during REC-015 twice, at 199 and 700 MB of real free space (pass 4,
    full run 12, 2026-11-20); it passed once at 209 MB. Low storage makes iOS purge and its wireless developer
    services drop. Test a storage guard by raising its threshold in DEBUG, not by emptying the disk.
  - *A run that waits on a missing device must end.* full run 12 sat at "Waiting for the destination to become ready"
    for two hours. `scripts/run_device_ui_tests.sh` now ends a run whose log has not grown for 10 minutes while
    xcodebuild waits for its destination ("DEVICE LOST" in the log); then check `xcrun devicectl list devices`.
  - *A host render test must know its own frame rate.* A GitHub runner's simulator rendered so slowly that the 1.5 Hz
    strobe fixture was sampled once and read no flash (run 44681007689); the test now counts its frames and skips
    with the numbers below 8 fps.

  - *Pass TEST_RUNNER_ values in xcodebuild's environment.* `TEST_RUNNER_MAC_DRIVER=1` written as a build-setting
    argument after `test-without-building -xctestrun` never reached the tests, so every `requireMac` test skipped
    "needs the Mac" while the driver ran beside them (full runs 12-13). Tests that sent `MAC-DO` without checking the flag
    hid it. `run_device_ui_tests.sh` now sets them in the environment; a skip reason is a finding, read every one.
  - *devicectl sendMemoryWarning fails on iPadOS 27.2* ("No such file or directory", by hand too, 2026-11-21). PERF-006
    now taps the DEBUG `memory:fill`: dirty memory in 64 MB steps until UIKit posts the system's own warning, never
    below 200 MB of `os_proc_available_memory()`, freed at once (probe `memoryFill`).
  - *A two-device check stays two devices.* FILE-001-B imports the archive A exported on another device
    (`FILE001_FROM=<D>`, default D1); with only D2 in use it waits for D3, it never imports D2's own archive on D2.

  - *A typed Siri request does not interrupt audio.* With Siri on (D2, 2026-11-21) `siriService.activate(
    voiceRecognitionText:)` answered silently and iOS sent no interruption, so AUD-006/AUD-014's Siri steps now record
    `siriInterrupted=0` and check the app is undisturbed; the clock timer covers the interruption path.

  - *A maximized window hides, it does not cover.* On D2 (iPadOS 27.2) "Open in New Window" over a full-size window
    opened the editor maximized and moved the output to "1 Hidden Window", unlisted in springboard's cards, so
    Left and Right tiled the editor beside an empty half. Once tiled, iPadOS remembers the editor's half-width size and
    later runs open it beside the output (UIX-008 passed twice, 2026-11-21). The test shrinks a full-size output first
    when it finds the resize handle, and a run that still ends with one window fails with the frames. Capture the
    device's screen with `xcrun devicectl device capture screenshot --device <id> --destination x.png`.

  - *The Mac driver must outlive the run.* `mac_device_driver.py follow` stopped after its 30-minute default, silently,
    so every `MAC-DO` after the first half-hour of a full run went unanswered (D3 full run 1, 2026-11-22: FILE-001-B's
    `files.push`; the driver log was empty). `run_device_ui_tests.sh` now gives it 12 h and the driver says when it
    times out.

- **A side driver must live as long as the run it serves** (2026-11-24). D2's full17 and D3's full20 suites failed every
  B09 OSC test: `osc_device_driver.py` had a 900 s default limit and had quietly exited long before B09 started, hours
  into the suite; and the second device's listener died on the shared Mac port 9100 ("Address already in use").
  `run_device_ui_tests.sh` now gives the driver `--timeout 43200` (it is killed when the run ends) and a port per device
  (9100 + device number), passed to OSC-005 as `TEST_RUNNER_MAC_OSC_PORT`. Any new side driver: no limit shorter than
  the run, and no fixed Mac port shared between devices.

- **Keep test ballast small; a huge preallocated file is slow to close** (D3, 2026-11-24). REC-009 and REC-015 took
  7 minutes each on D3 only (iPadOS 26.5, 128 GB): with a fixed 8 GB guard reserve the disk ballast was 66 GB, and
  closing that F_PREALLOCATE'd file took about 6.5 minutes. It happened at the app's end, so every relaunch looked hung.
  Moving the delete off the main actor fixed the launch (0.9-2.5 s for 66 GB), but closing early only moved the wait,
  and a Darwin-notification "drop" hung on the same close. The fix was the size: the DEBUG guard reserve now sits 2 GB
  below the current free space, so the ballast is about 2 GB, the real guard still trips on real writes, and no device
  is brought near full (REC-009 29.7 s, REC-015 40.7 s on D3). The app logs each delete's timing in
  `Library/Caches/QA011-DiskBallast-timing.log`, which `clear_disk_ballast.py` prints. Measure where the time goes
  (the app's own timing log, devicectl terminate and launch times) before redesigning.
- **A lost device mid-run resumes by itself (2026-11-24).** About once per full run on every device, `app.launch()`
  fails after 60 s with "Failed to terminate" (always right after a heavy media or camera test: MED-001's 45 MB HEIC
  panorama, MED-014, CAM-003/004), and xcodebuild then loses the device ("An error occurred while communicating with a
  remote process"). D2 full28 stopped at test 117 of about 180 that way. `run_device_ui_tests.sh` now resumes such a run
  (up to `RESUME=3` times): every test that passed or was skipped is left out, a failed one runs again, each attempt's
  log is appended to the run's log, and the summary counts each test's last result. No crash or hang report was
  written for the stuck terminate, so the cause on the device is still unknown.
- **Never reboot a device from the Mac without the owner (2026-11-24).** After that lost connection D2 failed every
  start with "Timed out while enabling automation mode", and `devicectl device process terminate` had no effect on
  testmanagerd or the AutomationMode helpers. `devicectl device reboot` cleared it, but D2 stayed unavailable until a
  person unlocked it, and the next start failed with "Authentication canceled": after a restart iOS asks on the device
  for the passcode before it enables UI automation. `lockState`'s `passcodeRequired: false` does not mean the device
  has no passcode. A reboot therefore needs a person at the device; ask first and batch it with other owner steps.
- **Start each session with prompt-flow on every device (2026-11-27).** After three days away, D1 and D3 had lost the app's
  camera and Local Network access (cause unknown; nothing in these runs reinstalled the app there). On D3 every camera
  test failed with "Camera access is off"; on D1 the OSC tests then raised iOS's Local Network prompt in the middle of
  the full run, and the prompt covered the screen for the rest of it, so about 45 later tests failed with "the controls
  are shown" or "Failed to tap settings". A failure screenshot from the result bundle showed the prompt. Before the
  first full run of a session, run `mac_device_driver.py prompt-flow` on each device; when many unrelated tests suddenly
  fail at the controls, look at a failure screenshot first.

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

- **A low frame rate: read the overlay's own lines first (QA-011 D3, 2026-11-24).** D3's camera checks read a steady
  52 fps for two days; the result bundle's screenshot of the performance overlay already said why: "gpu 9.42/12.76"
  and "frames device: presented 669, late 665, skipped 112". Skipped refreshes at a GPU time well under 16.7 ms mean
  the frame loop missed ticks (main-thread work, a full output), not a slow camera or heat; the Photo visual on the
  same build had 12 skipped. `assertFrameRate` now reports `gpuMedianMs`, `gpuP95Ms`, `framesPresented`,
  `framesLate`, `framesSkipped`, `framesSubmitted` and `controlsShown` with every reading, and the camera tests report
  `cameraPicturesPerSecond` (the capture probe's `stored=`) beside the shown frames. Compare these across runs before
  suspecting the device: the skips rose 17 → 62 → 112 at the same GPU time as the controls card gained two
  `ViewThatFits` layouts. Remember that a check run with the controls card up (it stays up after Settings closes, see
  spec 033 Clarification 2026-11-24) measures the card's main-thread work too; say so in the report.
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
  - *A probe whose value grows grows over the controls too.* CAM-002-T22 on D1 (r16, 2026-11-24): the camera
    probes' readouts wrapped at the window's width; after Save Frame the 384-digit orientation grid made them about
    100 pt tall over the iPhone's controls card, and Record and Save Frame read "not hittable" while the screenshots
    showed them. The iPads passed (wider lines). Probe texts the tests read by value are one line (`.lineLimit(1)`)
    in a small fixed frame where no control sits; `CameraProbeReachUITests` (iPhone 15 simulator, 11 s) shows the
    controls hittable with the grid filled. When a control is on screen but "not hittable" only on the iPhone, look
    for a DEBUG text that grew since the last step.
- **Tap the lens that is not running.** The Lens row lists the lenses widest first and the back camera opens on
  Wide, so a fixed `buttons.element(boundBy: 1)` re-taps the running lens: nothing restarts and a lock "survives the
  lens change" (CAM-004-T08 on 2026-11-23, CAM-006-T09 again in D1 r16). `chooseOtherLens()` taps the unselected
  segment and waits for the row to show it; check `starts` grew before blaming the app.
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
  - *Don't trust a cell's activation point.* `element.tap()` aims at the accessibility activation point. In the Files
    icon grid that is normally the thumbnail's centre (59, 46 pt into a 117.5 × 190 cell), but in full run 12 (D2,
    PRE-014-T25, 2026-11-20) preset-512k.milk's cell reported (11.8, 19), its empty top-left margin: three taps picked
    nothing. Find it in the session log (`Computing hit point for Cell, {{x, y}, {w, h}}` then `Computed hit point`).
    `SystemUI.tapItem` taps by coordinate where a person would: the thumbnail, then the name, then the cell's middle.
  - *Never `visualizerTapArea.tap()` to show the controls.* The full-screen tap area's hit point is the app's
    accessibility "visible point": a part of it that no other element covers, and on a phone the DEBUG session panel,
    performance overlay and audio panel cover its middle. In D1 r16 (2026-11-24, AUD-006-T40, AUD-014-T29) the session
    log showed `Computed hit point {5.0, 1.0}` for the 393 × 852 tap area: both reveal taps went to the top-left
    corner, in the hidden status bar's band, and the controls never came ("the controls are shown", then no
    `transportPlayPause`); 37 s earlier in the same test it was {39.3, 766.8} and worked. `tapVisualizer(attempt:)`
    (DeviceAcceptanceCase) taps at 62 % / 70 % of the height, below the probes and above the bottom status;
    `revealControls` and `showControlsBar` use it. Other helpers that still call `area.tap()` should move to it when
    they fail the same way.
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
- **Pass 6 on D3 (2026-11-19), the last recording, share and export failures:**
  - *A reading that never changes is a finding.* REC-015 recorded 150 s while the ballast showed the real free space
    at 122 MB, under the guard's 200 MiB reserve. The app's 5 s check read the same directory URL from a detached task,
    and Foundation caches resource values per URL until a run-loop pass that never comes there, so every check got the
    first reading. `VolumeStorageProbe` now reads through a fresh URL (host test reproduces it: same URL off the main
    thread, 512 MiB written, 0 bytes difference before the fix). Compare the app's reading with an independent one.
  - *System sheets differ by release after an activity is cancelled.* On iPadOS 26.5 a cancelled Messages compose
    returns to the share sheet, which stays open over the panel; iPadOS 27.2 closes both. Close what is still up.
  - *An identifier on a SwiftUI `Label` tags its icon too.* `exportSummary`'s first match was the checkmark image,
    whose own label is "Selected"; read `staticTexts[id]` for the text (PRE-014).
  - *When a system sheet never appears, compare it with a sibling that does, and try the simulator of that OS.*
    REC-001's exporter never opened on iPadOS 26.5 for three passes while REC-003's mover (a modifier of the same
    view) did. The iPadOS 26.5 simulator reproduced it at once: there the outer Files dialog modifier of a view shadows
    the ones inside it. The exporter now has its own host view outside the mover
    (`CaptureShareUITests.testSaveOpensTheFilesExporterTwice`, red before the fix, green after). Keep one Files
    dialog (importer, exporter, mover) per view.
  - *A host view in a `.background` is still in front for accessibility.* That exporter host (a `Color.clear` the
    size of the whole visualizer) showed up as a bare full-screen element after the Settings pane, so on D2 (full 8,
    iPadOS 27.2) no Settings row in the split editor was hittable and about 20 tests failed to reach visual rows,
    Storage, Camera and OSC controls, while swipes still scrolled. The iPad 27.2 simulator reproduced it in 8 s
    (`SettingsPanelReachUITests`, red at ca105200, green with the host zero-sized, hidden and untouchable outside its
    modifier). When every control in one area stops being hittable at once, diff the hierarchy for a new element in
    front of it before touching the tests.
  - *Scroll steps start inside the list, away from the screen edges.* `swipeUp()`/`swipeDown()` on the full-height
    Settings panel leave the start point to XCUITest, and one prompt-flow run ended on the Home Screen. Settings
    scrolling in the device tests goes through `ListScrolling.swift` (`scrollStep(up:velocity:)`: drags in the
    list's right-hand margin, at least 15 % of its height and 120 pt / 100 pt clear of its top and bottom).
  - *A scroll step must not start on a switch.* The right-hand margin is where a row's switch sits: in full run 12 on
    D2 (2026-11-20) FILE-010-T11's search for the Photo row made twelve downward steps at the top of Settings, each
    starting on the "Lock scene" switch, and one turned the scene lock on. Every visual change after it was refused,
    so Record refused ("Recording is available for the Camera, Photo, Video, Text and spectrum visuals") and the
    relaunch showed projectM; the test read it as "recording" and "the current scene's photo" failures. The screenshots
    in the result bundle showed it (the switch on, "Scene locked" over the visual). `scrollStep` now moves its start
    point along the drag until it is clear of every switch and slider (one snapshot per step); `chooseVisual` searches
    towards the row first and asserts the row reads as selected, naming a locked scene; `recordClip` prints the
    refusal notice. When a later step fails "for no reason", look for a setting an earlier drag changed.
  - *Close a Files dialog by what is on screen.* On iPhone (iOS 26.5) the exporter can open inside On My iPhone with
    no Cancel or Close at all (only Browse, More and Save); pull the sheet down instead, and retry a close the remote
    view drops (`CaptureShareUITests.closeFilesDialog`). The exporter and mover checks are two tests, each under 30 s.
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
  - *"Hittable" is not "takes the tap": check what the tap changed.* REC-012's DEBUG "Simulate share cancelled" row
    (bare caption buttons, no surface) was `isHittable` on the iPad (A16) simulators (iPadOS 26.5 and 27.2), yet every
    tap fell through to the visualizer's tap area and toggled the controls; the probe stayed `last=none`. iPhone
    simulators passed. A content shape over the row fixed it (2026-11-19). When a tap "does nothing" on iPad only,
    print a state the tap area flips (the controls) after the tap, and give DEBUG buttons a content shape or surface.
    The content shape alone was not enough on the iPad Pro 13-inch (M5) iOS 27.2 simulator (3 of 7 runs still dropped
    the tap, 2026-11-20). The row now has the result panels' own backing (`overlaySurface`, one accessibility
    container), and the test's `simulateShare` checks the probe after each tap and retries a dropped one (`finish`
    ignores a second delivery). Afterwards 7 of 7 on the M5 clone, 3 of 3 on iPad (A16) and iPhone 17 iOS 26.5, every
    first tap taken. Rule: DEBUG controls over the visualizer get the same surface as real overlay panels.
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
- **Pass 6 on D2 (2026-11-19, right after a reinstall), what it taught:**
  - *A picker's starting folder is state; navigate from any of them.* After the reinstall the Files picker opened
    one level up, in On My iPad, with the projectM folder in the grid's first row; the search for the file swiped that
    grid away, the already selected sidebar row did not scroll it back, and nine B07 tests failed "Files: no projectM"
    (in pass 5b the picker had remembered projectM itself). `SystemUI.filesPick` and `pickFromAppDocuments` now go
    into the app's folder first when the grid shows it (`enterAppFolderIfShown`), and each place on a path is found by
    scrolling the grid back to the top and down again (`revealPlace`; grid cells only, so a folder's own title never
    counts). Rehearse a picker test once after a fresh install, not only on a warm one.
  - *A probe must tell a stop from a gap.* The buffer a pause stops in ends in zeros; the playback analyzer counted
    them as a 74 ms gap (AUD-003-T22 on D2, three runs). Trailing zeros now count only when the next tap buffer comes
    within 0.5 s (the stream ran on). And a track change whose edges named no ramp position (64 ms of zeros at the end
    of a lone looping track, D2 only) lost the change (`changes=none` with track 2 playing): the analyzer keeps the
    last track heard across such edges and logs the raw edge values as `undecoded=` so the next run shows why they did
    not decode (`PlaybackAnalyzerTests`).
- **Pass 9 on D2 (2026-11-19), what it taught:**
  - *A self-hiding control can go between the query and the tap.* The controls hide 5 s after they are shown;
    FILE-010 closed Settings 4.7 s after showing them, found Presets, and the bar faded under the tap ("Activation point
    invalid", then "no matches"). `B07FilesDeviceTests.openBrowser` taps the button's last frame by coordinate (a miss
    only shows the bar again) and retries once with a fresh bar.
  - *XCUITest's `tap()` is not an instant.* It waits for idle before the touch and again after it (0.53 s and 0.82 s on
    D2). A clock started after `tap()` returns is late by up to a second: REC-007 read 2.82-2.87 s for a countdown the
    app runs to 3 s exactly. Bracket the touch (`Date()` before and after `tap()`) and check each bound against the
    side that cannot be wrong, or time between two things the loop sees on screen (from "Recording in 1" to the start).
  - *A timed user flow must not time the test's own pauses.* PRE-007's S8 (under 30 s) read 31.4 s, of which 6.2 s
    were fixed settle pauses and 1.1 s an XCUITest retry; the app answered every step at once. Inside a timed span,
    wait on the element the next step needs instead of pausing, and wait for a button to be hittable after typing (the
    keyboard moves the sheet).
  - *Pick folders by their grid cell, not by an exact label.* The Files mover opened in projectM; the test chose On My
    iPad, then tapped the first element labelled exactly "projectM", which did not open the folder, so the recording was
    saved at the root of On My iPad (beside a dozen from earlier runs) and REC-003 found none in projectM. `SystemUI.filesSave` taps
    the folder's cell ("projectM, 44 items") and waits until the cell is gone. Look at where the file actually landed.
  - *An undecided permission probe needs its own trace.* After Don't Allow the Local Network notice never showed and
    the run held nothing about what the browse reported. DEBUG builds now show the probe's last events
    (`localNetworkProbe`), and testC prints them (ADR-0125 follow-up 2).
- **Re-assert the orientation after launch.** On D2 (full run 12, 2026-11-20) the first launch after an install took 9 s;
  the iPad's own sensor reported Landscape Right, then Face Up, and the interface came up in landscape although the test
  had set Portrait. The screenshot stayed in the device's portrait pixel frame (2064 × 2752 under a 1376 pt wide window), so
  SHD-005-T13 sampled the wrong place and "the palette strip was not found". `launch` and `launchPlain` now call
  `settleOrientation`, which sets the orientation again (through the other one) until the window's shape matches.
- **Re-derive a bound from every device, not the one it was set on.** REC-008-T14's 5 % dropped-slot bound came from D1
  (5-8 of 300); D2 drops 4-19 with no code change between runs (same render-frame count), so the bound is now D2's
  mean + 3 SD (27, REC-008 Clarifications 2026-11-20). Before moving a bound, check `git log` on the measured path and
  the raw counts behind it, so a real regression is not absorbed.
- **Check that the app can build the state a test exports.** FILE-001-A launched the Video visual with a seeded photo
  and video, tapped Add Current Scene and exported it; the archive held only `assets/video.mov` and D3's preview read
  "1 video" (D2, 2026-11-22). Not an export defect: the app's scene captures (`ShowSceneSnapshot`,
  `SceneAutosaveCapture`) record one visual's fixed stack (Video `[video, spectrum.circular]`), and no screen adds a
  layer, so no captured scene holds both. Seeding "carried" layers did not help either: the snapshot never reads them.
  The test now uses the DEBUG seed `-uitestPhotoVideoScene` (the stored photo under the stored video, saved through
  `addScene`, a fixed scene ID so reruns overwrite one copy) and exports it through the real share sheet; B expects the
  Photo visual after the cue (a scene with a photo layer applies Photo) and then plays the imported video under the
  Video visual. Simulator rehearsal: `ScenePackPhotoVideoUITests` (with `-uitestScenePackKeepExport`). Before writing an
  export test, open the exported file once (unzip it) and compare it with what the test claims it holds.
- **Start a count where the fixture has the content.** The music fixture opens with a 10 s intro without drums
  (`scripts/make_music_fixture.py`); ACC-007-T13's 12 s haptic count started about 8 s after launch, so Beats counted 2
  pulses on D1 (2026-11-22) while ANL-005's confidence was still building. Wait on the playback position
  (`sectionChangeProbe` `position=`) before counting: ACC-007 waits for 20 s (the chorus with drums, until 40 s).
- **A median of motion pairs can compare noise.** When the music's big change falls in the same pairs of both runs
  (VIS-019-T13: pairs 3 and 4 of five, on D1, D2 and D3), the median is a quiet pair and jitter decides "Reduce Motion is
  calmer". Compare the mean over the same stretch of the track instead, and leave the overlay's box out (VIS-017-T13 on
  the iPhone: the overlay's counters set a floor of about 0.008 under both runs).
- **iPhone landscape: hide the controls outside the card.** The controls card fills most of the 393 pt landscape window,
  so `hideControls`' tap at 30 % of the height landed on the card, every tap counted as use and the controls never hid
  (ACC-010-T13 on D1, 2026-11-22). The helper now taps clear of the card's frame, or waits for the 5 s timeout.
- **On an iPhone, "on screen" means above the bottom chrome.** D1's first full run (2026-11-22) failed ACC-002-T20,
  ACC-012-T22 and PRE-015-T26 at "the fixture is listed": each dump, 30 s after tapping My Presets, still showed the
  library home. The browser sheet's list runs to the bottom of the iPhone screen, iOS 26+ floats the `.searchable`
  field over its foot, and with the colour and motion chip rows the home's last rows sit under it; `isHittable` and the
  frames-only `reveal` both accepted the row, and the tap met the search field. PRE-009-T13's long press on the last
  Calm row met the compare bar the same way. On an iPad the search field sits in the navigation bar, so D2 and D3 passed.
  `XCUIApplication.bottomChromeTop` (ListScrolling.swift: a search field in the lower half, the compare and audition
  bars, a tab bar) is now B07's `reveal` limit, and `openListRow` taps a navigation row until its destination's bar shows
  (`openMyPresets`). Check that a navigation tap navigated before looking for the next screen's content.
  The rerun (2026-11-22) added two more: a short list cannot scroll its last row above a bar (PRE-009's twelve drags
  bounced back), so press the row that is higher on screen, or the part of a row above the chrome; and at AX5 a row
  far down a lazy list does not exist until the list is scrolled towards it (My Presets), so scroll before waiting.
- **A low device count can be the app's threshold, not the test's window.** ACC-007-T13's Beats counted 9 of 24 beats in
  the chorus (D1 rerun, 2026-11-23) while Kicks counted 23. Feeding the fixture's own audio
  (`scripts/make_music_fixture.py`) through the onset detector and beat tracker on the host (BeatTestSupport.pipeline)
  showed why in a second: off-beat hi-hats hold ANL-005's confidence at 0.46-0.52, so a 0.5 cut passed a third of the
  beats. Before tuning a device test's window, replay its fixture through the same package code on the host.
- **"Not hittable" at AX5: dump the frames on a simulator first.** AUD-006-T41 failed on D1 for the fourth time with
  every transport button "not hittable" and the scrubber "outside the window". A 10 s simulator dump (iPhone 17e,
  AX5, the same launch arguments) showed the real cause at once: the controls were 495 pt wide on a 390 pt screen
  (seven 66 pt icons in one row widened the whole layout; an app defect, fixed in TransportBar), and the DEBUG audio
  panel lay over the buttons after the scroll. Compare every frame with the window's width as well as its height, and
  launch layout tests without DEBUG panels they do not tap (`launchPlayback(..., panels: false)`).
- **A segmented control's "other" segment is not a fixed index.** CAM-004-T08 tapped Lens segment 1 for "the other
  lens", but the row lists lenses widest first (Ultra Wide, Wide) and the camera opens on Wide, so the tap chose the
  running lens and nothing changed (`starts` stayed 1, the lock stayed). Tap a segment that is not `isSelected` and wait
  for the control's value to change.
- **A band that reads the same in every mode is measuring something else.** CAM-007-T15's landscape "Fit bar" band read
  0.324 (back) and 0.802 (front) to three places for Fill center, Fill top 2x and Fit: the controls card, still shown a
  few seconds after Settings closed, lay over it. Read such bands after `waitControlsHidden()`, away from what stays on
  screen (status pill, Emergency blackout, the overlay), and from the upright picture (`uprightPixels` draws the
  screenshot's `UIImage`, applying `imageOrientation`; `rgba` reads `cgImage` as stored). Report a Fill value next to
  each Fit value so a band that cannot tell them apart shows at once.
- **A pixel check of a live camera depends on the light; check the geometry instead** (2026-11-23). After the fix
  above, D1 run 6 read the portrait band as 0.232 non-black in all three modes, with the whole picture's mean luma at
  about 0.07: the camera faced a dark room, so a dark picture and a black bar were the same, and something constant
  lay in the band. Unattended runs cannot light the scene. CAM-007-T15/T16 now read `cameraPictureRect` (DEBUG, under
  `-uitestDiagnostics`): the crop, the source's upright aspect and the picture's drawn rectangle in window fractions,
  taken from the geometry the camera layer drew with last frame (`CameraLayerSource.drawnLayout`,
  `CameraPictureGeometry.pictureRect`), never recomputed in the view. Fit must keep the source's aspect, lie inside the
  window and leave bars on one axis; Fill must cover it; Top must start at the window's top. The band is only
  reported, and the screenshots stay for review by eye. A probe proves the renderer only if it reads the renderer's
  own numbers; use a pixel assertion only when the test controls what is in front of the camera (the stand-in camera
  on the simulator, `CameraCropLayerTests` on the GPU).
- **A simulator test that reuses the exporting app cannot catch a fresh-install defect.** FILE-001-T19 passed on the
  simulator while D3 failed: the simulator test imported the pack into the same app that exported it, so the
  scene's photo and video were already the current ones (FILE-008: the pack's derived identifiers share their payload),
  and Go on the imported cue looked right. D3 imports into a fresh install, where the pack's media are adopted but not
  current (SCN-014-R6), and Go showed "No photo": the cue apply never selected the scene's media (an app defect, fixed
  in `AppCoordinator.applyShowScene`; SHOW-001 Clarification 2026-11-23). When a device test moves data between
  installs, its simulator twin must relaunch with `-uitestResetNotice` between the two halves
  (`ScenePackPhotoVideoUITests.testAnImportedSceneShowsItsPhotoAndPlaysItsVideoOnAFreshInstall`; fixture mode keeps the
  pack in `tmp/ScenePackFixture`, which the reset leaves alone). Two more faults in the same D3 run were the test's:
  it expected "Photo 64 × 48" although the exported photo is the `pattern` seed (256 × 192; check the seed's size,
  not the solid PNG's), and `-uitestSettingsSection show` reopens *every* later Settings at Show, so the photo summary
  and the visual rows above it were never found in 12 swipes each way. Add `-uitestSettingsSectionOnce` when a test
  needs the top of Settings after the jump.
- **A "no work while away" window ends where the app may work again, not at `didBecomeActive`.** D1's first perf011
  run (2026-11-23) failed "no frames while away" on one frame: the sample that counted it was taken in the inactive
  state on the way back, and the trace's first GPU interval of the app came 16 ms before the `QA-011 foreground`
  marker (didBecomeActive). PERF-011 lifts its gate at `willEnterForeground`, so that frame is the return's. perf011
  now marks `QA-011 return` (willEnterForeground) and reports `returnedAt`, `framesAtReturn` and a running `total` per
  sample; the verdict counts only samples taken in the background plus the frames between the last of them and the
  return, and the GPU window ends at the return marker. Older reports and traces (no return time) keep the strict
  didBecomeActive end.
- **A check that matches nothing passes by accident: make "found nothing" a failure.** The same run's GPU check
  passed vacuously: it looked for rows mentioning "projectM-iOS", but Metal System Trace names the process by its
  display name ("projectM (2164)"), so 35,000 of the app's intervals matched none. The verdict now matches the name
  before " (pid)" against `projectM-iOS` and `projectM`, and fails when the app has no interval in the trace at all
  (it lists the processes it saw). Before trusting a zero, count what the filter matches in the whole table.
- **Read a cost's distribution before blaming heat or noise.** D1's first `rendererlab-flashcost` run (2026-11-23)
  failed at max 3.03 ms against 2 ms. Heat was ruled out by the report itself (`thermalStates: ["nominal"]`, Release),
  and the method was T104's. The per-preset costs split into two groups, 1.0-1.4 ms and 2.1-2.4 ms, with an extra
  ~1.1 ms that did not scale with the preset's own frame time: a fixed full-screen workload behind a content-dependent
  branch (the envelope's exact sRGB decode/encode, only while it dims). The fix went into the pass (a per-frame tone
  table), never into the 2.0 ms limit. A simulator run can rank such a branch at a larger size (4096 × 4096) but is
  never the device result; the next D1 run is.
- **Choose the subject a measurement needs inside the case.** PERF-004-T16's first D1 run used the circular spectrum
  with the glow and got no "PERF-004 texture allocation" signpost at all: only the compositor visuals (Camera, Photo,
  Video, Text) draw from the shared texture pool; the native spectra, their effects and projectM keep their own
  textures (PERF-004 Clarification, 2026-11-13). perf004 now defaults to the Text visual (no permission, no import) and
  the matrix case passes `PROJECTM_VISUAL=text` explicitly, so the unattended run measures the pool without a person.

- **A row below a lazy list's foot does not exist until the list is scrolled** (D2 r17/r21, D3 r20, 2026-11-24,
  PRE-015-T26). `app.buttons["node:myPresets"].waitForExistence(timeout: 10)` failed while a later dump showed the row:
  the first dump listed the iPad popover's home only down to Collections, scroll bar 0 %; the PRE-004/005 chip rows
  (shown once thumbnails exist, so after earlier runs on that device) had pushed My Presets below the 660 pt popover,
  and the later dump came after the test's own drags. Wait for a row near the top (Included), then drag the list until
  the target exists; `XCUIApplication.openMyPresets()` does this for every device test. Read the first failure's dump,
  not the last one: a dump taken after scrolling shows a different list.
- **Sampling a periodic animation at a fixed interval can freeze it** (D2 r17/r21, 2026-11-24, MED-008-T12). The GIF
  fixture's bar repeats every 1.6 s; a 3 s pause plus a 0.21 s screenshot spaced pictures 3.21 s apart, two cycles less
  10 ms, so all 20 caught the same phase: one position when that phase was on screen, none when it was in the part the
  aspect fill crops. The app was playing (r9's bar crept 0.12 → 0.48 of the width, the alias). Time each picture from
  the start at a whole number of cycles plus a distinct phase offset (3.2 s × s + 0.08 s × (7s mod 20)); a frozen frame
  still shows one position. Before blaming the renderer for a "frozen" animation, check the picture spacing against the
  content's period.

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

- **A frame rate of exactly 30 fps is the thermal cap, not a slow app** (D1, 2026-11-23). After an hour of camera tests
  every frame-rate check on the iPhone read a median of exactly 30.0 fps; the reports showed thermal state 2 (serious),
  where the app's QualityGovernor caps rendering at 30 fps (FR-049). `launch()` now cools a hot device at the Home Screen
  (`coolDownIfHot`, up to 5 minutes, app not running) and `assertFrameRate` uses FR-049's floor while the device is
  still capped, reporting `capped` and `thermal`. Check `thermal` in the report before chasing a frame-rate failure.
- **A Settings restore can tap the wrong switch while Settings is still navigating** (D1, 2026-11-23). ACC-007's Low
  Power restore found "Low Power Mode" but the tap resolved to Battery Percentage (the page was still moving after
  relaunch); the Battery Percentage display on D1 may have been toggled. Verify the switch's own state after a restore.

- **A device on USB has a second, link-local address** (D2, 2026-11-23). After its iPadOS update D2 came back only
  over the USB cable, and `<name>.local` then resolved to its 169.254.x.x USB address: `peer.py` gave D3 (on Wi-Fi)
  that address for D2 and the Mac's USB-side address. `devices.resolve` now gathers every address and prefers a LAN
  one (`prefer_lan`). Check the `TEST_RUNNER_PEER_IP` and `TEST_RUNNER_MAC_IP` values in a peer log's first lines.

- **A DEBUG-only hook in a package test breaks the Release benches** (D3 matrix, 2026-11-23). `bench-rec003-encoder`
  builds the device test bundles in Release; two ANGLERendering tests had started using DEBUG-only renderer hooks
  (`ANGLEDebugFlashStats`, `PresetPrewarmer.afterLoadForTesting`) without `#if DEBUG`, so the case ended "no test summary;
  exit 65" before running. Any test that touches a DEBUG-only hook goes inside `#if DEBUG`; check with
  `xcodebuild build-for-testing -scheme DeviceTests -configuration Release ENABLE_TESTABILITY=YES`.

- **Size a DEBUG storage reserve to the device** (D1, 2026-11-23). REC-009/REC-015 set an 8000 MB guard reserve (chosen
  on the iPads); D1 had 3.6 GB free, so the app correctly refused to record ("refused: lowStorage").
  `B08RecordingDeviceTests.guardReserveMB(above:)` reads the guard's free-space figure in the runner (same volume) and
  keeps 8000 MB only when there is room, else 1000 MB below the free space.
- **Read a vanishing label from one snapshot** (REC-007, D1, 2026-11-23). `countdown.exists` then `countdown.label`
  raced the countdown's last second ("Failed to get matching snapshot"); `try? element.snapshot()` reads both at once.
- **iOS 27 iPhone share sheets hide actions under "View More"** (REC-012, D1, 2026-11-23): the frame's sheet listed
  Save to Files only there. `shareSheet` and REC-012 expand it. Never print a share sheet's whole label list: its first
  rows are people and devices suggested from the owner's contacts; print only the asked labels.

- **Watch every device run, not just the end of the queue** (D1 and D3, 2026-11-23). D3 sat in a silent run for 15
  minutes until the runner's watchdog stopped it, and D1's queue had ended 15 minutes before the owner noticed the
  app's last screen. `scripts/device_watch.py --devices D1,D3` runs beside the device runs and exits the moment a
  device's log is silent for 5 minutes (`SILENT`) or a device has no `xcodebuild test` (`IDLE`).

- **D1 rerun 6 and r9, D3 r9 (2026-11-23): eight failures, five causes, none in the app.**
  - *A query fixed before scrolling never sees a lazy row.* `tapSettingsRow` resolved the row once; off screen it does
    not exist, so `settingsRow` fell back to a cells query, and Settings' root "Accessibility" row (a text or a button
    when it scrolled in) was never matched in 16 swipes (ACC-001, ACC-003, ACC-008; Battery had only been reached through
    the search). The row is now resolved afresh after every step, must sit above the floating search field
    (`isReachable`), steps use `scrollStep` (a plain `swipeUp()` can start on that field), a root row falls back to
    Settings' own search, and `openSettingPage` searches the switch label when the path did not reach it.
  - *Scroll towards the element, and turn round at the list's end.* `ControlSurfaceCase.scrollTo` only stepped towards
    the end: MED-006's Slideshow switch sits above the seven picture rows (off screen after the Files picks) and
    FILE-010's storage rows above the Clear Caches result (every row read -1). It now follows an existing element's
    frame, turns round when a step moves nothing (`listSignature`) or after `swipes` steps, and drags in the list that
    holds the element (`listHolding`).
  - *Never tap the controls' Settings button while Settings is open.* MED-001's second pick called `openSettingsPanel`
    with Settings still open; on an iPhone the sheet covers the button (hit point -1, -1) and XCUITest tapped its
    visible frame, on a Settings row, which presented a sheet over Settings. The Settings list became the stacked-sheet
    card ({16, 59, 361, 728}, rows scaled 0.92) and Choose from Files… was never reachable. Every open-Settings helper now
    returns when the Settings bar shows (`settingsAlreadyOpen`). On an iPad the panel leaves the button uncovered.
  - *A notification banner can take a tap meant for the app.* MED-005 on D1: a Messages banner lay over Settings' Done
    ({8, 56, 377, 66}); XCUITest saw it but "Failed to construct element query matching interruption", tapped, and
    Messages opened. The app sat in the background for two minutes (reverse cache "preparing", state 3), which looked
    like a cache that never finished; D1 had passed twice before (preparation 4.3 s and 3.8 s). Every Settings Done now
    goes through `tapSettingsDone` (swipes a `NotificationShortLookView` away, re-activates the app if it left).
    Turn on a Focus (Do Not Disturb) on the devices for runs; never describe a banner's content in a report.
  - *`snapshot()` of a vanished element retries for 2 s.* REC-007 read "Recording in 1" first at t 10.7 s, then the
    countdown's own snapshot retried from 11.96 to 14.19 s once it had gone, so the start looked 3.48 s late. The poll
    now reads the countdown, indicator and announcement from one snapshot of the app (`windowValues`), which never
    retries. The app had started on time (countdown gone about 1.2 s after "1" first showed).
  - *Tapping the chosen Camera mode opens Camera Controls* (iOS 26+). MED-014 tapped "PhotoModeButton" while Photo was
    chosen; the drawer ("Dismiss Camera Controls", Edit, Flash, Live Photo…) hid "PhotoCapture". The chosen mode is left
    alone, an open drawer is closed, and the shutter is found by identifier or label (buttons printed when missing).
  - *An iPad sheet is not the window.* D3 ACC-002 at AX5 dragged twelve times at x 787 of 820, beside the browser form
    sheet (x 140-680), so My Presets was never built. `dragContentUp(near:)` drags inside the list holding a reference
    row; `openListRow` brings a row above the top bar down instead of pushing it further up.

- **A matrix run reinstalls the app and empties its Documents** (D2 and D3, 2026-11-23). The UI regression run right
  after the device matrix failed every music test at launch ("music-fixture.m4a is missing") and every Files pick
  ("no photo-small.jpg"). `run_device_ui_tests.sh` now seeds the fixtures before every run
  (`install_test_fixtures.py --media --if-missing`, only what Documents lacks; `FIXTURES=0` skips it).

- **Order after a matrix run: matrix, then prompt-flow, then UI tests** (D1, 2026-11-23). The matrix reinstalls the
  app, which resets every permission answer as well as Documents. D1's next UI run had a springboard permission alert
  over the app: 51 taps reported "Interrupting element Alert" and 8 of 9 tests failed on "the controls are shown". After
  every `run_device_matrix.py` run on a device, run `mac_device_driver.py prompt-flow` there before any UI test.

- **D2 r10 (iPad Pro M5, iPadOS 27.2.1, 2026-11-23): four failures, two causes, none in the app.**
  - *A Save tapped as the mover comes up does nothing; check that the sheet closed.* Today's iPhone shortcut in
    `filesSave` (Save at once when the mover opens in projectM) also ran on the iPad, whose mover opens there as well (pass 9); before it, the iPad went through On My iPad and
    the folder first, which gave the sheet time to settle.
    The tap on `DOCPicker.actionButton` came 0.5-1.2 s after the sheet appeared; the result bundle's screenshots 11 s
    later still show the mover with "Save as" filled in. REC-001 ("PNG:" empty) and REC-003 ("the mover finished:"
    empty) waited for a save that never happened, and PRE-014 *passed* with its ZIP mover still up, because
    `filesSave` returned true on the tap. Every picker action now goes through `tapPickerAction`: it waits for the
    sheet to settle, taps, and counts only when the button left the screen (or "Replace" came up); otherwise it taps
    again by coordinate, then saves the long way (the location, then the folder), and fails honestly if the sheet
    is still up.
  - *A sheet left up blocks the next launch.* MED-001 failed in setUp after 60 s with "Failed to terminate
    org.projectmios.ProjectMiOS" (and the runner restarted): PRE-014's mover was still over the app (MED-001's first
    screenshots show it). `DeviceAcceptanceCase.tearDown` now cancels any Files sheet still up
    (`dismissLeftoverFilesSheet`). When a test fails at launch, look at the previous test's last screenshot first.
  - *Compare with the reference by the policy's outcome, not by what iOS delivered.* AUD-002-T26 failed "seed-aac.m4a
    autoResumed: got 1, expected nil": the same 5 s Clock timer, stopped the same way, reached the reference track
    and the MP3 as began=1 ended=0 (held, then Play continued) and the M4A as ended=1 shouldResume=1 (it continued by
    itself). The app followed AUD-014 each time; iOS chose differently. The test now compares `policyOutcome` (did the
    track do what the policy asks for what arrived), and the keys only when the delivery matched.
- **An xctrace recording can say "Stopping recording..." and never end** (D1 matrix, `xctrace-perf011`,
  2026-11-23). After "Target app exited, ending recording... Stopping recording..." xctrace wrote a 1.98 GB Metal
  System Trace until 8 minutes after the app had exited, then nothing for 2 minutes, until it was stopped by hand; the
  export then found no tables. `xctrace.record()` runs every recording with its output in the case's log and stops it
  with SIGINT (then SIGTERM, SIGKILL) when the bundle stops changing for 3 minutes after the recording time or 15
  minutes past it; the case then fails with the reason, and `export` gets 10 minutes per table.
  - *Time steps from the app's launch, not from the command.* The same run's report shows the app in the background
    (state 2, no frames) for its first 15 samples: Metal System Trace took about 18 s to launch the app, so Settings,
    opened 15 s after the command, came first, and the "return" only brought the app to the front once ("not
    backgrounded and brought back"). The background driver now waits for a new process of the app
    (`Target.app_pids`) and counts from there. `--launch` stays (`--attach` did not find the app on D3), and
    `--time-limit` is longer than the app's own run so the app ends the recording by exiting.
  - *Keep a GPU trace short.* The app now draws for about 24 s of the run (10 s before, 14 s after the away time)
    instead of 35, which roughly halves the trace.
- **"Target app exited" ends the recording; a save that hangs after it is xctrace's** (D1 matrix 20261123T210326Z,
  `xctrace-perf004`). The app wrote its report and exited after 31 s, as designed, and xctrace printed "Target app
  exited, ending recording..." and then nothing; two earlier runs that day saved within seconds. The stall rule waited
  out its 180 s launch allowance before counting, so the case took about 7 minutes. Now `xctrace.record` stops a
  recording 60 s after "Target app exited" once the bundle stops changing, and the case records once more when the
  stop left no readable trace. *A directory is not a saved trace:* the stopped bundle held only `Trace1.run` with the
  raw `trace-data.atrc`; `export --toc` fails on it, and `xctrace import --input trace-data.atrc --template Logging`
  produces a trace whose os-signpost table is empty (the log stream arrives with the save). `trace_complete` checks for
  `form.template`; a whole trace is exported even after a stop, and a stopped run counts only when the app had exited
  and its tables exported. (Corrected 2026-11-24 in the next lesson: the save had not hung; the 60 s stop and the
  retry are gone.)
- **xctrace's save is silent for minutes; read the file times before calling it hung** (D1 matrix 20261124T183541Z,
  `xctrace-perf004`, PERF-004 Clarifications 2026-11-24). Both attempts were stopped "60 s after the app exited" and
  left only the raw `trace-data.atrc`. The bundles' birth and modification times (`stat -f "%SB %Sm"`) settled it: in
  the two D1 runs that saved, xctrace wrote the raw recording within a second of "Target app exited", then changed
  nothing on disk, neither the bundle nor `$TMPDIR/instruments*.ktrace`, for 196 s and 307 s, then wrote the whole
  trace in 8 s by itself. Every failed run had been stopped inside that phase (183 s, 60 s, 60 s), and SIGINT there
  only prints "Stopping recording..." and leaves xctrace running, so SIGTERM ended it and destroyed the trace.
  `xctrace.record` now treats an idle bundle as a hang only after `SAVE_QUIET` (420 s, the slowest save seen plus a
  third) from the app's exit and 60 s unchanged, writes a heartbeat line each minute while it saves (bundle bytes,
  seconds unchanged, xctrace CPU time) and returns `saveSeconds`, which the verdict names. There is no second attempt,
  because two saves would pass the 10-minute check budget. Lessons for any repository: a progress watchdog must watch
  something the tool really updates in that phase; measure that phase on a run that succeeded before choosing a
  timeout; never retry what your own stop broke. xctrace also leaves `$TMPDIR/instruments*.ktrace` behind (1.3-2 GB
  each after a Metal System Trace run), so check that folder when the Mac's disk fills.
  - *Judge a window from the event that starts it, not from the command.* The run that did save failed with "14 elsewhere
    (at 8.911 s)". Those 14 were the first allocations in the trace: starting playback on the Text visual held the main
    thread 5.0 s (a hangtracer `HangInterval` in the same os-signpost table), so the first cycle came 5.3 s after
    "QA-011 start", just past the start + 5 s window. perf004 now emits "QA-011 ready" once playback start returns, and
    older traces infer it from the report (`markSeconds` count from that moment). A gap between the app's own times
    and the trace's markers is the clue: the rotation was 10.0 s after the start in the report and 15.0 s in the trace.
- **A sheet at its start closes on a full-height drag towards the start** (FILE-010-T11, D1 r10b). After Clear Caches
  the Storage list was scrolled to its top, the first row ("storage.photos") still counted as above the navigation bar
  (under the expanded large title), and `scrollTo` dragged the list's height towards the start: the Settings sheet
  closed and every later row read -1 while 60 more drags moved the visual behind it. Read a value where the element is
  (no scrolling for an element that exists), bring an element already on screen clear with one short held drag of
  what it lacks (`nudge`, at most 160 pt), and stop when the list being scrolled leaves the screen. When a test reads
  -1 for rows it read a minute earlier, look for the sheet in the screenshots first.
- **"Failed to terminate" in setUp is the previous app instance, not the test** (D1 r10b, REC-007 and ACC-003). Both
  failed in `launch()` after 60 s with the app alive and drawing in the screenshots, and the runner restarted 4-5
  minutes later; neither reached its subject (REC-007's countdown poll was not exercised). XCUITest terminations of
  the app are often slow on every device: in the UI logs of 2026-11-22/23, 71 of 1,082 took over 5 s and 8 failed at
  60 s (count them from "Terminate org.projectmios.ProjectMiOS:<pid>" to the next step's time). The cause is not known
  from the Mac; the next one needs a device log around the termination (RunningBoard, FrontBoard). Rerun such a test
  before changing it.
- **Measure a pass's cost in ABBA rounds and report its spread** (`rendererlab-flashcost`, D1 2026-11-23). After the
  tone table one preset stayed over 2 ms in all three runs (3.03, 2.99, 2.64 ms) about 0.8 ms above its group, which the
  dimming fix did not move. Measuring "on" always after "off" folds a preset's frame-time drift into the cost, so
  RendererLab now runs 20 off, 40 on, 20 off per round and the report carries each round's cost, both IQRs, and how
  often the envelope dimmed (the dimming path's share). Read those before calling a cost real or noise.
- **Pair a pass's cost with the frame it processes; never judge a max over presets of unpaired medians**
  (`rendererlab-flashcost`, D1 2026-11-24). Two D1 runs of identical code (2026-11-23, 200159Z and 210326Z) gave
  per-preset on-minus-off costs up to 2 ms apart (`Martin - The Beast Mandala Chaser` -0.29 and 1.73 ms, `Goody -
  Vertigo` 2.24 and 1.04 ms), and the ABBA run of 2026-11-24 put `ORB - Saturns Rings` at 4.39 ms (0.84-1.14 ms the day
  before) with an "on" IQR of 3.5 ms against 1.0 ms "off". "On" and "off" are different frames of a moving picture,
  so a preset whose frame time swings with its content puts that swing into the difference, and the maximum over 28
  presets picks the worst swing. RendererLab now also times the pass alone on each frame (the engine's frame finished
  first, then the pass encoded, submitted and finished: `timedPassFrames`, 160 frames per preset) and the matrix
  verdict uses those paired medians; on-minus-off stays in the report. Also keep every extra wait symmetric: the
  2026-11-23 version read the gain texel back after "on" frames only, an extra GPU round trip on one side.
- **Time GPU work with GPU timestamps, not a wall clock between two glFinish calls** (`rendererlab-flashcost`, D1
  20261124T191740Z). Timing the pass alone as glFinish → pass → glFinish read 2.6-3.1 ms on every preset, 1.0-1.5 ms
  above on minus off and nearly constant: the CPU's submit, the GPU waking from idle and the completion wait, which the
  app never pays. A sign it was overhead: the presets with the largest on-minus-off cost had the smallest paired time.
  ANGLE's Metal backend implements GL_EXT_disjoint_timer_query (public, via eglGetProcAddress): `glBeginQueryEXT(
  GL_TIME_ELAPSED_EXT)` and `glEndQueryEXT` end the command buffer at each call and report GPUEndTime - GPUStartTime
  of the buffers in between (`PMANGLETimerBegin`/`End`/`ResultMs` in CANGLE). RendererLab now adds that GPU time to
  the pass's CPU encoding time and reports the round trip it excludes (a 1 × 1 clear's submit-and-wait) beside it.
- **A GPU timer query times command buffers from when the GPU starts them, so finish the earlier work first**
  (`rendererlab-flashcost`, D1 20261124T222416Z). The timer bracket around the pass read 7.7 ms of GPU time for a
  64 × 64 measure step and one full-screen output step. ANGLE's Metal backend gives each GL_TIME_ELAPSED query the
  command buffers created while it is active (`QueryMtl::begin`/`end` flush, `CommandQueue::makeMetalCommandBuffer`)
  and sums their `GPUEndTime - GPUStartTime` (`onCommandBufferCompleted`, `mtl_command_buffer.mm`). A buffer
  committed right behind another and reading its output starts early and waits inside that interval, so the pass's
  time held most of the engine's frame. The giveaway: a fixed-size pass's GPU time followed each preset's own frame
  time (correlation 0.87). `timedPassFrames` now calls glFinish before the query begins and reports that wait apart
  (`engineWaitMedianMs`). Sanity-check any GPU timing against what cannot depend on the content.
- **Discard what a full-screen pass overwrites** (FX-019 output step, 2026-11-24). ANGLE's Metal backend starts a
  render pass with `MTLLoadActionLoad` unless the attachment was invalidated (`glInvalidateFramebuffer`) or cleared
  (`FramebufferMtl::setLoadStoreActionOnRenderPassFirstStart`), and projectM never clears its target. The strobe pass's
  output wrote every pixel of the window yet loaded it first: 12 MB read per frame at 1179 × 2556 on D1, in the app
  too. A GL test fills the window with magenta first and checks no pixel survives (red with a half-height viewport).
  The Mac's GPU shows no difference (its bandwidth hides 12 MB), so only the device run can size the saving.

- **B09 OSC tests need the OSC driver beside the run** (D2, 2026-11-23). A regression run through
  `run_device_ui_tests.sh` without `osc_device_driver.py` failed every Mac-to-device OSC test ("Test value, 0.00",
  "OSC learn timed out"). `OSC=1 scripts/run_device_ui_tests.sh …` now starts the driver aimed at the device's LAN
  address (never its USB 169.254 one) and passes `TEST_RUNNER_MAC_IP` and `TEST_RUNNER_OSC_DRIVER=1`.

- **D2 r12 (iPad Pro M5, iPadOS 27.2.1, 2026-11-23, with the OSC driver): four failures, three causes, none in the app.**
  - *Read the value the visual shows, not the one the user set.* OSC-003 and OSC-004 read "manual" from the MOD-002
    readout ("unbound, manual 0.50, effective 0.50"). MIDI-003 and OSC-003 write live values on top of the manual glow
    (`NativeSpectrumHost.externalValues`), so "manual" stays 0.50 by design, as the app's unit test says ("the manual glow
    is unchanged"). The driver log shows every send (`/projectm/param/glow.intensity` 0.2 and 0.9, `/b8/fader/9` 0.5,
    0.1 and 0.95 to the device's LAN address, port 9000), and OSC-004 *learned* `/b8/fader/9`: the values arrived.
    These two tests had never passed on any device (D1-D3 on 2026-11-18 failed them too, with no driver then). B10 had
    switched to "effective" on 2026-11-21; the reader is now shared (`ControlSurfaceCase.liveGlow`), and the app test
    pins the readout's format. When one control path passes and its sibling does not, diff what the two tests read.
  - *Scroll the list that holds the row; on an iPad the root rows are in the sidebar.* FILE-012 had its own `open()`
    that swiped the whole Settings app: on the iPad that scrolled the General page beside the sidebar twelve times and
    never reached "Privacy & Security" (the result bundle's screenshots). It now goes through
    `SystemUI.openSettings(path:)` with Settings' search as the fallback, and fails when the report page is not reached
    (before, the domain check passed on whatever page was showing). Never write a private Settings walker in a test.
  - *`app.windows.firstMatch` is not always the main window.* PERF-011's return after a rotation while away read the
    window as 683 × 1032 (portrait) while the visual, its controls and the playback pill filled the 1376 × 1032 landscape
    screen in the screenshots. The result bundle's log shows why: at launch the first window was the main one
    (1032 × 1376, a window context), after the return it was another element of the app (window context 0, 683 × 1032),
    probably a system window of iPadOS 27.2.1's windowing (not identified). `DeviceAcceptanceCase.interfaceFrame()`
    reads the full-screen tap area (`visualizerTapArea`), which follows a smaller iPad window too; `settleOrientation`
    uses it, and PERF-011 reports both frames. Other tests still read `windows.firstMatch` for coordinates; move them
    to `interfaceFrame()` if they misplace taps after a background return.
  - *"audio: Paused" after a return: read the banner in the screenshot before blaming the test.* PERF-011-T22 and
    VIS-001-T36 on D2 (iPadOS 27.2.1, 2026-11-23) failed "playback resumes … audio: Paused" after a background round
    trip with a rotation while away (d2rest, d2r13 and all three d2resume iterations; VIS-001 passed once in d2rest12),
    while D1/D3 and the D2 runs of 2026-11-18 to 11-20 passed with no app change in that path since 11-19 (D2 now
    runs iPadOS 27.2.1, so likely an OS behaviour change). The overlay prints
    only the state; the result bundles' "after the return" screenshots (both tests) showed the status panel "Interrupted · Playback
    is on hold at its position", so an AUD-014 interruption had opened. Nothing else played. Most likely cause (the
    notice's reason value was not logged, so not proven on the device): the app had paused its engine but kept its
    audio session active, iOS interrupted the suspended app's session and never ended it, and an open interruption
    correctly blocks the return resume. Confirm with the next D2 rerun of both tests. A real app defect, fixed in the app (CaptureKit): going
    away releases the session (`suspendWhileAway`), the return activates it again, and a refused activation stays on
    hold as "Interrupted" (AUD-015 Clarifications 2026-11-23). Lesson: an app without the audio background mode must
    not hold an active session while suspended; and the export/overlay should be read together with the status
    panel, whose reason line tells "paused by the lifecycle" from "interrupted".
  - *A fix aimed at a guessed cause needs the evidence that tells the candidates apart.* The session release alone
    did not fix D2 (r14: 1 of 6 returns resumed, the panel still read "Interrupted"), because the app could not tell
    an iOS interruption from its own refused-activation path, and neither was logged. Now `-uitestSessionLog` adds
    CaptureKit's `AudioSessionTrace` to the `sessionLog` probe after " || trace: ": raw interruption/route notices
    (type, reason, options, wasSuspended), `session.activate`/`session.deactivate` with ok or the error's code and
    four characters (e.g. '!pla'), `app didEnterBackground/willEnterForeground/didBecomeActive`, `lifecycle …`,
    `hold: …`, `resume: ok|refused …`, `policy: …`, `active: retry=…`, each with `t=` seconds and `app=<state>`.
    PERF-011-T22 and VIS-001-T36 print it as `SESSION-TRACE <task> resumed|NOT resumed: …` after every return and
    put its last 1,500 characters in the failure message: grep the run log for `SESSION-TRACE`. The app also retries
    a refused return at didBecomeActive (AUD-015 Clarifications, r14).
  - *The trace decided it in one run (r15).* `d2diag1` VIS-001: `session.deactivate ok` at 53.51 s, then
    `notice interruption type=1 reason=0 options=- wasSuspended=-` at 53.52 s with `app=background`, no end, and the
    return's `policy: stayPaused(interrupted) signal=pending`. iPadOS 27.2.1 posts a suspension notice as a plain
    interruption about 10 ms after the app backgrounds; neither guessed cause was it. A plain "began" within 1.0 s of the
    away hold (`CaptureManager.suspensionNoticeWindow`) is now recorded as `suspension notice: <n> ms after the away
    hold` and opens nothing. Lesson: log first, then fix; two guesses cost two device rounds, the trace one.
    Verified on D2 2026-11-24: PERF-011 and VIS-001 passed 3 of 3 runs on r16 (notice 22-33 ms after the hold).

- **A test that fills the disk must be cleaned up from the Mac too** (D3, 2026-11-24). D3 ran out of space and every
  run was refused ("Developer App Certificate is not trusted"; even a plain `devicectl` launch hung). The app container
  held a 67 GB `Library/Caches/QA011-DiskBallast.bin` from a REC-015/REC-009 run the evening before: the app deletes an
  old ballast at every DEBUG launch and the tests relaunch in tearDown, but that run was stopped, so no launch followed,
  and with the disk full none could. devicectl cannot delete a file in a container, so `scripts/clear_disk_ballast.py
  --device DX` launches the app once (its launch deletes the ballast) and checks; `run_device_ui_tests.sh` runs it after
  every run (`BALLAST=0` skips it). If the launch cannot clear it, uninstall the app (`devicectl device uninstall app`):
  that frees the whole container. When a device starts refusing launches for no clear reason, check its free space and
  list the app container's sizes first.

- **Split a failing reading by what was on screen before blaming the GPU** (D3 r27, 2026-11-24). Every D3 frame-rate
  reading with the controls card up read 52-55 fps and every one without it 60 fps, even at a higher GPU time; the
  `controlsShown` field that `assertFrameRate` reports made this a one-line grep of the run log. The card was up
  because of an app defect, not the test: Settings suspends the 5 s auto-hide, and a timer that fired while Settings
  was open was never restarted, so every test that chose a visual in Settings measured with the card up for good.
  Fixed in the app (closing a panel restarts the delay); frame-rate checks about the visual's rate now call
  `waitForControlsAutoHide(task, step)` (at most 8 s, reported) after a step that revealed the controls, which is what
  a viewer sees 5 s later. Lessons: report the screen state with every measurement; when a check measures the visual,
  wait for the view a viewer has, not the one the test's own taps left; and count SwiftUI body rebuilds on the
  simulator (a temporary per-view counter logged every 5 s, `-uitestKeepControls` to keep the card up) before guessing
  which view is busy: here only the tempo group (4 Hz, same words) and the transport's position row were.

## What still needs a person

Headphones and Bluetooth routes, real phone and FaceTime calls, Airplane Mode and Wi-Fi off (they need the USB cable:
not required, owner ruling 2026-11-18), a real face or hands in front of the
camera, a USB MIDI device's own transport, real projectors and curved screens, a 240 fps camera, and the iOS prompts
that guard UI automation and permissions. Stand-ins that are automatable: a CoreMIDI virtual source for a controller,
the Mac sending OSC over Wi-Fi for a LAN controller, Siri and a Clock timer for an interruption (SystemUI), Settings
toggles for permissions and accessibility settings (SystemUI), `xctrace` for Instruments. The virtual MIDI source
runs inside the app (`-uitestVirtualMIDISource`, B10). AirPlay steps are not required (owner ruling 2026-11-18).

## For another repository

1. Put measurement modes in the app behind a compile-time flag, writing JSON reports and exiting.
2. Give UI tests typed settings, a clean start, fixtures for media and audio, and an overlay or probe that exposes
   the numbers you assert.
3. Host package tests in the app for device runs; keep test code free of `Bundle.module`, guard DEBUG-only members.
4. Write a run record per device with hashes; keep it free of personal data; verify before committing.
5. Classify every hands-on task (scripted, stand-in, person) and batch the person-steps into a few sessions.
