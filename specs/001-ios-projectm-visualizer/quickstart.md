# Quickstart: Validating ProjectM-iOS

A run guide for proving each stage works. Implementation details live in `tasks.md`. Contracts:
[audio-source](contracts/audio-source.md), [bridge](contracts/projectm-bridge.md),
[ui-states](contracts/ui-states.md), [export schema](contracts/diagnostics-export.schema.json).
Entities and states: [data-model.md](data-model.md).

## Prerequisites

| Need | Where |
|------|-------|
| Git, Python 3.11+, Spec Kit, Claude Code | Windows or macOS (specs, docs, scripts) |
| Xcode with the iOS 27+ SDK (pinned in ADR-0002), XcodeGen, CMake | macOS only |
| Apple Developer signing | macOS, human only |
| Devices per FR-032: D1 iPhone 15 (iOS 27), D2 iPad Pro M5 (iPadOS 27), D3 iPad A16 (iPadOS 26) | physical |
| Source apps for the FR-030 matrix, signed in by the tester | on each device |

Windows can run only the documentation checks (`py scripts/validate_docs.py`). Every build or test
result below requires macOS. On Windows, report it as "pending macOS".

Before Scenario A, record the concrete device model and OS build for each FR-032 role in
`docs/test-reports/devices.md` (FR-034).

## Device-only requirements and where they are proven

| Requirement | Scenario step |
|-------------|---------------|
| SC-001–SC-004, FR-030–FR-034, RI-002 | A.2–A.8 |
| FR-019 on iOS 27 (capture permission prompt) | A.2 |
| FR-004/FR-008 on iOS 26 | A.3 |
| FR-004 "Screen recording not allowed" on iOS 27 | host-tested only; on a device only if a restriction makes `isAvailable` false (T113) |
| RI-003, FR-050–FR-055 (capture evidence) | A.5 |
| Gate 2 thresholds | A.9 |
| Gate 3, ADR-0003, RI-009, RI-011 | B |
| SC-005–SC-010, SC-012–SC-015, FR-041, FR-084, FR-089 | C |
| SC-011, FR-063, FR-066, FR-067, FR-064 | D |

Simulator and Windows results never satisfy any row above.

## Setup (macOS)

```bash
git submodule update --init --recursive
python3 scripts/verify_environment.py          # checks pinned Xcode/XcodeGen/CMake versions
python3 scripts/build_projectm_xcframework.py  # Phase C+: Build/ProjectM.xcframework
xcodegen generate                              # ProjectM-iOS.xcodeproj
```

## Automated checks (macOS / CI)

```bash
swift test --package-path Packages/AudioCore      # classifier, ring buffer, normalizer
swift test --package-path Packages/CaptureKit     # manager with fake sources
swift test --package-path Packages/Diagnostics    # export validates against schema; no identifiers
swift test --package-path Packages/CaptureUI      # shared chooser, explainer, banner strings
python3 scripts/check_compliance.py               # constitution API/boundary rules (also runs on Windows)
xcodebuild -scheme CaptureLab -destination 'platform=iOS Simulator,name=<discovered>' test
```

Expected: all pass. Classifier tests cover every transition in data-model.md, including SC-002's
playing/paused/absent timelines and FR-011 hysteresis. Ring buffer tests cover wraparound,
overflow (drop-oldest plus counter), and underrun. Simulator results never count as capture
evidence.

## Scenario A — Stage 1 capture feasibility (physical device, CaptureLab)

System/App Capture can be tested only on D1 and D2 (iOS/iPadOS 27.0 or later, FR-008), never on a
simulator: the iOS Simulator SDK (Xcode 27.2) has no ScreenCaptureKit, so the mode always shows as
unavailable there. In every System/App Capture run:

- Start playback in the source app first, then switch to CaptureLab and start capture. Since
  2026-11-09 CaptureLab declares the `screen-capture` background mode (ADR-0001 ruling 17), so
  leaving it no longer ends the stream; a lock still does (-3817). Pause and resume the source without leaving CaptureLab, for example from
  the Now Playing controls in Control Center, and note it if that ends the stream. Set Auto-Lock to
  Never: CaptureLab does not keep the screen on, and a lock may end the stream too. Leave CaptureLab
  on purpose only in step 5.
- In steps 2, 6, and 9, change what is shared only by stopping and starting again in CaptureLab.
  CaptureLab does not use a new choice made from system UI while a stream runs; step 5 tests that
  case once.
- Before each export, write in the tester note: the source app; the picker options offered and the
  one chosen, as labeled on screen; whether a permission prompt appeared, whether it showed the
  `NSScreenCaptureUsageDescription` text in [ui-states](contracts/ui-states.md) (FR-019), and, if
  you declined it, the message and any code shown; whether the system screen-recording and
  microphone-in-use indicators were visible, and where (FR-089; the microphone indicator should
  not appear, FR-069); and any SCStreamError code shown, or "none shown". Keep the note under 500
  characters (the export refuses longer notes); use short answers such as "prompt: no;
  indicators: <where seen>; code: none shown". The export also records the stop or failure detail,
  with any SCStreamError code, in `session.stopDetail` (DiagnosticsView shows it as "Stop
  detail"); the "Ended by system" banner itself does not show the code.

1. Install CaptureLab on each FR-032 device, built with the iOS 27.2 SDK pinned in ADR-0002. A
   build from an SDK without ScreenCaptureKit (such as the iOS 26.5 SDK on CI) has no capture
   driver and shows System/App Capture as "Requires a newer iOS version" even on D1 and D2.
2. **US1** (D1, D2; T040): Play audio in a source app → CaptureLab → Choose Audio Source →
   System/App Capture → select in the system picker. Expect "Active audio" with live rate, channels,
   and levels. Pause the source without leaving CaptureLab → "Audio received — silent" within 2 s.
   Repeat with a source producing nothing → "No audio received" after 5 s. Cancel the picker → "Not
   started — cancelled". If a permission prompt appears, decline it in one run → "Screen recording
   not allowed" (US1-AS4). If the prompt does not appear again after the first answer, write that in
   the tester note, and how (if at all) it was reset.
3. On D3 (iPadOS 26.5; US1 scenario 5, T040): CaptureLab launches, and System/App Capture shows
   "Requires a newer iOS version" while Microphone and In-App Playback stay selectable. Device
   builds weak-link ScreenCaptureKit explicitly (`-weak_framework`, ADR-0002; Debug and Release
   checked with `otool -l` on 2026-11-08). Record which configuration was installed on D3; before a
   TestFlight upload, follow `docs/release/capturelab-distribution.md`. Only a run on D3 shows that it launches on iOS 26: the simulator build does
   not link ScreenCaptureKit at all.
4. **US2**: Microphone (explainer → permission), deny → message; In-App Playback → audible
   reference track, "Active audio" within 1 s; Stop → "Stopped" within 1 s.
5. **Lifecycle evidence (RI-003)**: during each mode, background, foreground, lock, unlock, and
   trigger an interruption and a headphone change. Export after each run. For System/App Capture
   (D1, D2; T041), also switch to the source app and back, and record for each event whether the
   stream survives. Leaving for the source app may end it ("Ended by system", possibly code -3824).
   Whether a lock ends it, and with which code, is unknown. On each of D1 and D2, also do one run
   that changes the shared content from system UI (for example Control Center) during capture,
   and record what happens in the tester note (T113); CaptureLab does not apply the new choice, by
   design. Since 2026-11-09 CaptureLab declares only the `screen-capture` background mode
   (ADR-0001 ruling 17, from the D1 runs of T041); `audio` is never added. Run the background, lock
   and app-switch runs with the normal build. The export records each stop code in `session.stopDetail`.
   Check device exports with `python3 scripts/check_capturelab_export.py --json <file> --expect
   none` (or with the expected lifecycle events).
6. For each FR-030 source, run 10 minutes in the foreground and export (FR-021).
7. Fill `docs/test-reports/compatibility-report.md` rows (FR-031) and rate each Works / Partial /
   Does not work.
8. The project owner records the Stage 2 decision (FR-033).
9. **Gate 2**: for each source rated "Works", run a 30-minute foreground capture on the reference
   device and check the Gate 2 thresholds in spec Delivery Gating.

**Pass**: SC-001–SC-004 met; report complete; decision recorded.

## Scenario B — Gate 3 render proof (physical device)

Run the projectM-iOS render-proof build with In-App Playback. Load `presets/tests/*.milk` and 20
starter presets. Record shader failures, fps, and app size per ADR-0003 option.
**Pass**: ADR-0003 exit criteria met and accepted.

## Scenario C — Gate 4 end-to-end and Stage 2 criteria (physical device)

| Check | Procedure | Pass |
|-------|-----------|------|
| SC-005 | 10-min session, overlay on (FR-048), reference device | ≥ 55 fps for 95% of the session |
| SC-006 | 240 fps camera filming screen + speaker, 20 clicks from reference track | median < 150 ms |
| SC-007 | Next × 50 across bundled set | 95% < 1 s |
| SC-008 | 30-min session, memory at min 5 vs min 30 | ≤ 10% growth, no crash |
| SC-009 | 50 start/stop/switch at 200 ms; lifecycle script per mode | 0 crashes, final state correct |
| SC-010 | Usability sessions | ≥ 90% identify mode + audio state |
| SC-012 | Screen-reader audit iPhone + iPad | all controls pass |
| SC-013 | 30-min thermal session per SC-013 conditions | never critical, ≥ 30 fps, no termination |
| SC-014 | 60-min session, 50% brightness, unplugged | ≤ 20% battery |
| SC-015 | Cold launch × 10, D1 (reference) and D3 | median < 2 s / < 4 s |
| FR-084 | Visualize for longer than the auto-lock interval | device does not lock |
| FR-041 | Rotate; iPad split view and resize | re-layout ≤ 1 s, capture uninterrupted |
| FR-089 | Hide the controls during System/App Capture and during Microphone, on D1 and D2 (T084) | the screen-recording and microphone indicators stay visible |

### Scenario C measurement tooling (T118)

Device runs that need no person at the device use two tools. Neither is in the shipping build.

- **Measurement build of projectM-iOS**: Release plus `SWIFT_ACTIVE_COMPILATION_CONDITIONS=PROJECTM_AUTOMATION`
  (Debug builds include it too). `Apps/projectM-iOS/Automation/AutomationRunner.swift` starts when the
  environment variable `PROJECTM_AUTORUN` is set, for example
  `xcrun devicectl device process launch --device <udid> --environment-variables '{"PROJECTM_AUTORUN":"sc007"}' org.projectmios.ProjectMiOS`:
  - `sc015`: cold launch to the source chooser, appended to `Documents/sc015.json`; launch repeatedly.
  - `sc007`: 50 x Next with In-App Playback, request to first presented frame.
  - `sc009`: 50 start/switch/stop cycles at 200 ms, then the lifecycle script per mode (Microphone
    needs its permission granted once by hand; System/App Capture needs a person at the picker).
  Reports go to the app's `Documents` (`automation-<mode>-<time>.json`); copy them with
  `devicectl device copy from`. Confirm the shipping Release build has no `AutomationRunner`
  symbols (`nm`).
- **RendererLab** (`RendererLab.yml`): `RL_BACKEND=gles|angle`, `RL_MODE=sweep|session|flashcost`,
  `RL_DURATION`, `RL_PRESET_SECONDS`, passed as environment variables. `flashcost` (ANGLE only, T104)
  times GPU-synchronized frames with Reduce flashing off and on for each starter preset.

## Scenario D — Release checks

- SC-011 privacy review: inspect the app container after sessions. Only the FR-065 keys exist; no
  audio files; no network traffic in a proxy capture.
- FR-064: ADR-0005 final conclusion is "go".
- FR-066: privacy manifest declares all required-reason APIs; App Privacy says "Data Not Collected".
- FR-067: the Licenses screen lists every component in ADR-0004 and every preset in LICENSES.md.
- FR-062: store copy and in-app help reviewed against report rows.
