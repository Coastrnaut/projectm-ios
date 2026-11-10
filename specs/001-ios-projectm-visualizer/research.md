# Research: ProjectM-iOS Visualizer

**Date**: 2026-11-07 · **Plan**: [plan.md](plan.md) · **Spec**: [spec.md](spec.md)

Each item records a **Decision**, **Rationale**, and **Alternatives considered**. Items marked
**Verification pending** are planning decisions whose underlying platform facts must still be
confirmed against the SDK or a device (Constitution: unknown Apple API behavior). They map to the
spec's research items (RI-xxx). None of them is presented as fact.

Sources: this repository's README and constitution; direct inspection of `Vendor/projectM`
@ `eae22de` (CMakeLists.txt, docs/building.rst, src/api/include/projectM-4/*.h, shader sources,
Renderer/Platform/GLResolver.cpp).

---

## R-01 Toolchain and SDK pin

- **Decision**: Use the newest stable Xcode that ships the iOS 27 SDK, with deployment target iOS
  26.0. The exact Xcode build, SDK version, and Swift version are recorded in ADR-0002 at Gate 0
  and in the CI workflow.
- **Rationale**: System/App Capture needs the newest SDK; the iOS 26 deployment target comes from
  the clarified spec.
- **Alternatives**: Building with the iOS 26 SDK. Rejected: it cannot compile the iOS 27 capture
  APIs.
- **Verification pending**: Exact version (Gate 0).

## R-02 System/App Capture API (RI-001, RI-004)

- **Decision**: ScreenCaptureKit only, in-process, on iOS/iPadOS 27.0 and later (RI-004). No
  broadcast upload extension, no App Group IPC, no ReplayKit. No entitlement: the Screen Recording
  entitlement Apple's iOS sample declares was added by the owner review (ADR-0001 Decision 6) and
  removed on 2026-11-09, because it is offered only to organization accounts (ruling 16). The app calls the
  system picker's `present()` from `start` and does not steer the selection (iOS has no picker
  modes). The stream enables audio (48 kHz, 2 channels, own audio excluded), adds an `.audio`
  output into `PCMSink` and a frame-discarding 64×64 `.screen` output, and never a `.microphone`
  output; the picker hides its microphone control (FR-069). `SCContentSharingPicker.isAvailable`
  gates availability and start (FR-004). Decisions taken in T035 (2026-11-08) are
  listed in ADR-0001, which the project owner accepted on 2026-11-08 with the rulings listed there.
- **Rationale**: Apple documents ScreenCaptureKit as the iOS 27 replacement for ReplayKit, whose
  capture APIs are deprecated in iOS 27.0. The constitution forbids ReplayKit as the default, and
  the spec (FR-009) forbids a legacy path.
- **Alternatives**: ReplayKit `RPScreenRecorder.startCapture` or a broadcast extension. Rejected:
  deprecated, and out of scope per the clarification. `present(using:)` with a window or display
  style: not used, so the user decides in system UI.
- **Verified 2026-11-08** (from the iOS 27.2 SDK headers and Apple's docs;
  `docs/platform-research/screencapturekit-ios.md`): iOS symbols and availability, no picker modes,
  output types `.screen`/`.audio`/`.microphone`, no content identity on iOS (FR-014),
  `NSScreenCaptureUsageDescription` named by Apple's overview (FR-019). **Open until device
  testing**: whose audio `.audio` carries (RI-002; a first answer in T040, per source T051 and
  T052), usage-key enforcement (T040), and, in the device checks of T113, whether audio-only
  streams work (approved temporary build), the minimum video size, and the capture indicator
  (FR-089). **Owner ruling
  2026-11-08**: an iOS 27 device where screen recording is not allowed (`isAvailable` false), and a
  declined screen-recording permission (-3801), use the new reason `screenRecordingNotAllowed`.

## R-03 Background modes and lifecycle (RI-003)

- **Decision**: Ship with no background audio mode in the first release. In-App Playback pauses
  and Microphone stops on background (FR-050). For System/App Capture, CaptureLab logs
  stream-delegate events across background/lock/foreground to produce RI-003 evidence; the app
  continues only if the stream is still delivering (FR-050).
- **Rationale**: Background visualization is out of scope. Adding a background mode without need
  invites App Review questions.
- **Change rule**: If RI-003 shows that ScreenCaptureKit on iOS needs a specific background mode to
  keep a foreground session alive, add only that mode, through an ADR-0001 amendment approved by the
  project owner. No other modes are added. Owner review 2026-11-08: the only mode this rule can add
  is `screen-capture`; `audio` is never added, and capture in the background stays out of scope.
- **Alternatives**: Audio background mode to keep the microphone alive. Rejected: no user value
  without visuals.
- **What the sources say (2026-11-08)**: Apple documents the `UIBackgroundModes` value
  `screen-capture` for capturing in the background, and the SDK has `SCStreamError`
  `missingBackgroundMode` (-3824, iOS/visionOS/tvOS only) without naming the mode or trigger. No
  Apple source covers device lock. The Change rule therefore has a concrete candidate,
  `screen-capture`. Owner ruling 2026-11-08: decide after T041, once its runs (without the mode)
  show which stop codes leaving CaptureLab produces. Until then the test procedure is: start
  playback in the source app first, then stay in CaptureLab (quickstart Scenario A).
  **Applied 2026-11-09 (ADR-0001 ruling 17):** CaptureLab declares only `screen-capture`. T041 on D1, 2026-11-09 (`docs/test-reports/t041-lifecycle.md`): without the mode, background and an app switch end capture 1 ms later with -3824; with it (diagnostic build 9001), capture ran unbroken for 53 s in the background. A lock ends capture either way (-3817).
  `scripts/check_compliance.py` allows exactly `UIBackgroundModes: [screen-capture]` and rejects any
  other background mode in `project.yml`.
- **Open until device testing** (T041): behavior on background, lock, unlock and switching to the
  source app, with the stop code recorded; the export carries it in `session.stopDetail`
  (schemaVersion 2, owner ruling 2026-11-08).

## R-04 Microphone and In-App Playback

- **Decision**: Use one `AVAudioEngine` per source session. Microphone: an input-node tap, with
  an `AVAudioSession` category `.playAndRecord` or `.record` (chosen during implementation and
  documented), requesting `AVAudioApplication.requestRecordPermission` at the point of use (after
  the FR-005 explanation). `NSMicrophoneUsageDescription` uses the explainer text in
  contracts/ui-states.md (FR-019). In-App Playback: `AVAudioPlayerNode` → main mixer, a tap on the mixer
  output, category `.playback` (so the silent switch does not mute user-started media), with the
  bundled track looped. Interruption and route-change notifications drive FR-051.
- **Rationale**: These are public and stable APIs, and both modes produce `AVAudioPCMBuffer`, which
  shares one conversion path.
- **Alternatives**: AudioQueue or RemoteIO units. Rejected: more code for no benefit at this scale.

## R-05 Internal audio format

- **Decision**: Normalize every source to **Float32, interleaved stereo, 44,100 Hz**. Mono is
  duplicated to L=R. Streams with more than 2 channels and a known channel layout are downmixed to
  stereo by `AVAudioConverter` using the platform's standard layout downmix. Streams with an unknown
  layout use channels 1 and 2 (FR-017). Int16 and Int32 samples are converted to Float32.
  Resampling uses `AVAudioConverter` on the work queue (not in the callback). No custom FFT, band,
  or beat analysis is built: the engine performs its own (README §5.1). AudioCore computes only
  peak and RMS levels for the classifier and diagnostics.
- **Rationale**: `projectm_pcm_add_float` takes interleaved LR floats with no rate parameter; the
  engine is tuned for about 44.1 kHz. Stereo is kept for presets that use channel separation.
- **Alternatives**: Feeding the native 48 kHz. Rejected: it skews the engine's beat/spectrum
  timing. Mono only. Rejected: it loses stereo presets.

## R-06 Real-time transport

- **Decision**: Each source callback copies raw samples into a preallocated per-source **SPSC ring
  buffer** (capacity 1 s at the native rate, atomics from the `Synchronization` module). Overflow
  drops the oldest data and increments a counter. A dedicated serial work queue (user-interactive
  QoS) drains the ring every 10 ms or less, converts and resamples (R-05), updates the `LevelMeter`
  and `AudioStateClassifier`, and writes into a second **normalized SPSC ring** (capacity 0.5 s =
  22,050 stereo frames at 44.1 kHz, drop-oldest). The work queue posts classifier state and
  diagnostics to the main actor at most 4 times per second. The render loop reads the normalized
  ring once per frame, up to `projectm_pcm_get_max_samples()` frames, and passes them to
  `projectm_pcm_add_float`.
- **Freshness rule**: If the normalized ring holds more than 50 ms of audio when a frame starts, the
  reader skips ahead to the newest 50 ms (counted as dropped). This caps the ring residency in the
  latency budget.
- **Underrun policy**: If the normalized ring is empty at frame time, the renderer adds no samples
  that frame; the engine keeps animating from its existing audio history. No synthetic silence is
  injected. Sustained emptiness is already reported by the classifier ("No audio received" or
  "Audio received — silent").
- **Latency budget** (SC-006, 150 ms): capture delivery ≤ 30 ms; source ring and conversion ≤ 20
  ms; normalized ring residency ≤ 50 ms (freshness rule); engine frame and display ≤ 50 ms. Each
  stage is measured with signposts in Phase B/D. Owner ruling 2026-11-09 (T062): ring + conversion
  is a signpost interval; capture delivery and normalized residency are measured after the fact
  and recorded as signpost points carrying the milliseconds. The residency trace is T114 (Phase C).
- **Acceptance**: A Phase B allocation-trace test runs each adapter for 60 s and must record zero
  heap allocations and zero lock acquisitions on the audio callback thread.
- **Rationale**: Satisfies Constitution VII: no allocation, locks, or logging in callbacks, and
  bounded memory.
- **Alternatives**: `AsyncStream` per buffer (allocates, unbounded). Locks with a deque (priority
  inversion risk).
- **Note**: ScreenCaptureKit delivers `CMSampleBuffer`. The callback extracts the
  `AudioBufferList` into the ring with no Swift allocation; this is checked with an
  Instruments/allocation test in Phase B.

## R-07 Audio-state classifier

- **Decision**: A pure, deterministic state machine in AudioCore (contract in
  [contracts/audio-source.md](contracts/audio-source.md)). Inputs: a monotonic clock, "data
  arrived" events, and per-window peak dBFS. Thresholds come from the spec (FR-011/FR-012/FR-018)
  and are injectable for tuning.
- **Rationale**: SC-002/SC-003 need exhaustive unit tests with simulated timelines, independent of
  devices.

## R-08 Renderer / GL ES provider (RI-005)

- **Finding**: The engine's shaders are written in GLSL ES `#version 300 es` (with `330` for
  desktop). Preset HLSL is translated by the bundled hlslparser to that GLSL. The build docs'
  "OpenGL ES 3.2" requirement does not appear to match the code, so this must be verified.
  `projectm_create_with_opengl_load_proc` accepts a host loader, which avoids the resolver's
  CGL/EGL/WGL detection (it has no iOS EAGL path).
- **Decision**: Prototype on two candidates in Phase C and decide in ADR-0003:
  1. **Apple OpenGL ES 3.0** (EAGL + `CAEAGLLayer`). The load_proc is a static lookup table of
     directly linked, documented OpenGL ES 3.0 C functions, so there is no `dlsym` and no dynamic
     symbol lookup (Constitution I). Fastest path to Gate 3. Deprecated since iOS 12.
  2. **ANGLE (Metal backend) as a pinned dependency**, providing GLES 3.0 via EGL on Metal. It
     avoids the deprecated API and is the production candidate. It adds a third-party dependency
     with its own license (BSD-3) and binary size.
  A full Metal port of the engine is **not** planned. It is a large rewrite that risks preset
  fidelity (Constitution VIII), and is reconsidered only if both candidates fail.
- **Relation to "evaluate Metal"**: Option 2 *is* the Metal evaluation. It runs the unmodified
  engine on Metal through ANGLE, which keeps preset fidelity and upstream compatibility. A native
  Metal renderer would replace the engine's whole GL renderer and shader translation, so it is
  out of scope unless both options fail.
- **Engine runtime loading (RI-009)**: The engine's resolver uses `dlopen` on POSIX platforms
  (`DynamicLibrary_posix.cpp`). Phase C determines whether it runs on iOS when a load_proc is
  supplied. Preferred outcome: it is not reached. Fallback: a minimal patch disabling it for iOS,
  recorded in `docs/projectm-patches.md` (the engine is pinned to the owner's fork, branch `ios`,
  which already carries the iOS framework patch; Constitution VIII v1.1.0).
- **Quality tiers**: Phase C sets engine settings (per-point mesh size, render scale, texture size)
  for two tiers, "current" (reference device D1, and D2) and "oldest" (D3, the iPadOS 26 device), following
  upstream's advice to keep the mesh low on mobile (e.g., 48×32). The tiers and the device-to-tier
  rule are recorded in ADR-0003.
- **Rationale**: Gets an early, measurable Gate 3 while keeping a non-deprecated route.
- **Exit criteria (ADR-0003)**: the test presets in `Vendor/projectM/presets/tests` plus 20 starter
  presets render on D1, D2, and D3; fps is measured; shader
  compile failures are counted; binary size is measured.

## R-09 Presets and reference audio (RI-008)

- **Decision**: Bundle only presets with explicit redistribution licenses, starting from upstream
  ProjectM-maintained preset packs if their licenses permit. `Apps/ProjectMiOS/Resources/Presets/LICENSES.md`
  records, per preset: file path, display name, pack, author, license identifier, source URL, and
  source commit/version. A preset with any field missing is not bundled. Reference audio is a short track
  synthesized in-house (generated tones, clicks, and beat pattern), giving full rights and a
  deterministic signal for SC-006.
- **Rationale**: FR-006/FR-047. An in-house track also gives the click impulses SC-006 needs.
- **Verification pending**: License review of the candidate preset packs.

## R-10 Engine packaging and LGPL-2.1 (RI-007)

- **Decision**: Build libprojectM with CMake as a **dynamic framework**, packaged as
  `ProjectM.xcframework` (iphoneos arm64 and iphonesimulator arm64/x86_64), embedded and signed in
  the app. Ship engine source (submodule pin) plus build scripts publicly. Provide written notice
  and the LGPL text in-app (Settings → Licenses).
- **Rationale**: This is the commonly used approach to LGPL relinking expectations. Whether it
  satisfies LGPL-2.1 §6 alongside App Store terms needs a written review; it is not assumed.
- **Alternatives**: Static linking plus distributing object files for relinking. Seeking a license
  exception from upstream.
- **Verification pending**: RI-007 preliminary conclusion (blocks Stage 2 entry) and final
  conclusion (blocks release). RI-010 (the reason behind upstream's App Store warning) is analyzed in
  the same ADR-0005. Attribution and the source offer appear on the Licenses screen (FR-067).
- **iOS build configuration (RI-011)**: `scripts/build_projectm_xcframework.py` configures CMake
  for each slice (`CMAKE_SYSTEM_NAME=iOS`, device and simulator SDKs, `ENABLE_GLES=ON`, shared
  library as a framework) and combines the slices with `xcodebuild -create-xcframework`. These
  flags are planned, not yet verified against upstream; the exit is a CI-produced xcframework.

## R-11 Engine version pin (RI-006)

- **Decision**: Pin to the **latest upstream release tag** that passes the Phase C render proof.
  Use the current untagged commit `eae22de` only if a needed fix is not yet tagged, with the
  reason recorded in ADR-0004.
- **Rationale**: Tags are reproducible and reviewable; Constitution IX.

## R-12 Project generation and CI

- **Decision**: XcodeGen (`project.yml`, version pinned in `scripts/verify_environment.py`)
  generates the project on macOS. GitHub Actions `macos-*` runs: `swift test` per package →
  `scripts/build_projectm_xcframework.py` (cached by submodule SHA) → `xcodebuild build` and `test`
  on simulator destinations discovered at runtime. CI tests on both an iOS 26 and an iOS 27+
  simulator runtime when the runner image provides them. If the iOS 26 runtime is missing, the job
  logs that, and iOS 26 coverage comes from the physical D3 (iPadOS 26) run (FR-032). No signing
  secrets in CI.
- **Rationale**: Text-only project definition supports Windows editing; CI matches the README §15
  template.
- **Alternatives**: A committed `.xcodeproj` (merge conflicts, not editable on Windows). Tuist
  (heavier).

## R-13 Diagnostics and privacy-safe telemetry

- **Decision**: No network telemetry. Diagnostics are in-memory snapshots, `os_signpost`
  intervals for Instruments, and the tester-initiated export (FR-021) validated against
  [contracts/diagnostics-export.schema.json](contracts/diagnostics-export.schema.json). Logs never
  include sample data and never run on the audio thread (the work queue posts counters).
- **Logging rules**: `Logger` messages mark every dynamic string as private; they never include the
  tester note, content identity, or sample data. There are no file logs. Export files are named
  `CaptureLab-<UTC yyyyMMdd-HHmmss>.json` / `.txt`, with no device or user identifiers.
- **Rationale**: FR-060/FR-061/FR-068; Constitution privacy section.

## R-15 Threat model (summary)

| Asset | Entry point / threat | Mitigation (requirement) |
|-------|----------------------|--------------------------|
| Captured audio (in memory) | Persisted or exfiltrated | No storage, no network (FR-060, FR-068); SC-011 proxy check |
| Ambient sound | Microphone opened unexpectedly | Mic only in Microphone mode (FR-069); usage text (FR-019) |
| Device/tester metadata | Diagnostics export shared | Tester-initiated only; schema excludes identifiers; private log strings (FR-021, R-13) |
| Preset files | Malformed or hostile preset code evaluated by the engine | Bundled, license-reviewed presets only; no import/download (Out of Scope); load failures isolated (FR-045) |
| Supply chain | Tampered engine or ANGLE binaries | Submodule SHA pin, CI builds from source, cache keyed by SHA (ADR-0004) |
| Capture indicators | User unaware of capture | Never obscure system indicators (FR-089); explicit system picker (FR-002) |

## R-16 Entitlements and capabilities

No App Groups, no background mode except `screen-capture` (R-03 change rule, ADR-0001 ruling 17), no network, no push, no iCloud. No entitlement:
the Screen Recording entitlement (ADR-0001 Decision 6) was removed on 2026-11-09 because it is
offered only to organization accounts (ruling 16); T040 shows whether capture needs it. Info.plist contains only `NSMicrophoneUsageDescription` and the capture usage keys
Apple's documentation tells apps to add: `NSScreenCaptureUsageDescription`, kept whether or not
iOS 27 requires it (owner review 2026-11-08). The set is listed in `project.yml`, enforced by
`scripts/check_compliance.py`, and reviewed in Phase E.

## R-14 Accessibility and photosensitivity

- **Decision**: SwiftUI accessibility labels on all controls; `AccessibilityNotification.Announcement`
  on audio-state changes; Dynamic Type for control text. "Reduce flashing" clamps per-frame
  full-screen luminance change in a post-pass (method chosen in Phase D and measured against a
  luminance-delta threshold). Default on when `accessibilityReduceMotion` is set.
- **Rationale**: FR-070–FR-072, SC-012.
- **Verification pending**: Post-pass feasibility depends on the ADR-0003 renderer.

---

## Unresolved → owner/exit summary

| Item | Spec RI | Blocks | Exit artifact |
|------|---------|--------|---------------|
| R-01 exact toolchain | — | Gate 0 | ADR-0002 updated |
| R-02 ScreenCaptureKit iOS surface | RI-001, RI-004 | Gate 0 | docs/platform-research/screencapturekit-ios.md |
| R-03 background behavior | RI-003 | Gate 2 (owner ruling 2026-11-08) | platform research + report rows |
| R-08 renderer | RI-005 | Gate 3 | ADR-0003 accepted |
| R-09 preset licenses | RI-008 | Gate 3 | Presets/LICENSES.md |
| R-10 LGPL review | RI-007 | Stage 2 entry / release | docs/adr/0005-lgpl-compliance.md |
| R-11 engine tag | RI-006 | Gate 3 | ADR-0004 updated |
| R-08 engine dlopen | RI-009 | Gate 3 | ADR-0003 analysis |
| R-10 upstream App Store warning | RI-010 | Stage 2 entry | docs/adr/0005-lgpl-compliance.md |
| R-10 iOS CMake config | RI-011 | Gate 3 | CI-built xcframework + ADR-0004 |

Owner for all: project owner.
