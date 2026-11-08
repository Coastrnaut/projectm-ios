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

- **Decision**: ScreenCaptureKit only, in-process. `SCContentSharingPicker` presents the
  system UI. `SCStream` runs with an `SCStreamConfiguration` that enables audio capture, and an
  `SCStreamOutput` receives the audio-type outputs. `SCStreamDelegate` reports stop and error. All
  code sits behind `@available(iOS 27, *)` (the version is updated by RI-004) plus a runtime
  capability check. No broadcast upload extension and no App Group IPC.
- **Rationale**: The README cites Apple docs describing ScreenCaptureKit as the iOS replacement
  for ReplayKit, with an iOS 27+ sample. The constitution forbids ReplayKit as the default, and
  the spec (FR-009) forbids a legacy path.
- **Alternatives**: ReplayKit `RPScreenRecorder.startCapture` or a broadcast extension. Rejected:
  deprecated, and out of scope per the clarification.
- **Verification pending**: The exact iOS symbol names, picker modes, audio output types, whether
  app audio (not just microphone) is delivered, whether the OS reveals the selected app's identity
  (FR-014), and Info.plist keys. Exit: `docs/platform-research/screencapturekit-ios.md` written
  from the SDK headers. macOS ScreenCaptureKit behavior is not assumed.

## R-03 Background modes and lifecycle (RI-003)

- **Decision**: Ship with no background audio mode in the first release. In-App Playback pauses
  and Microphone stops on background (FR-050). For System/App Capture, CaptureLab logs
  stream-delegate events across background/lock/foreground to produce RI-003 evidence; the app
  continues only if the stream is still delivering (FR-050).
- **Rationale**: Background visualization is out of scope. Adding a background mode without need
  invites App Review questions.
- **Alternatives**: Audio background mode to keep the microphone alive. Rejected: no user value
  without visuals.
- **Verification pending**: Whether ScreenCaptureKit requires or offers any background mode on
  iOS (Gate 0/2).

## R-04 Microphone and In-App Playback

- **Decision**: Use one `AVAudioEngine` per source session. Microphone: an input-node tap, with
  an `AVAudioSession` category `.playAndRecord` or `.record` (chosen during implementation and
  documented), requesting `AVAudioApplication.requestRecordPermission` at the point of use (after
  the FR-005 explanation). In-App Playback: `AVAudioPlayerNode` → main mixer, a tap on the mixer
  output, category `.playback` (so the silent switch does not mute user-started media), with the
  bundled track looped. Interruption and route-change notifications drive FR-051.
- **Rationale**: These are public and stable APIs, and both modes produce `AVAudioPCMBuffer`, which
  shares one conversion path.
- **Alternatives**: AudioQueue or RemoteIO units. Rejected: more code for no benefit at this scale.

## R-05 Internal audio format

- **Decision**: Normalize every source to **Float32, interleaved stereo, 44,100 Hz**. Mono is
  duplicated to L=R. More than 2 channels are downmixed: L = mean of left-side channels, R = mean
  of right-side channels, otherwise channel 0/1. The coefficients are documented in AudioCore.
  Resampling uses `AVAudioConverter` on the work queue (not in the callback).
- **Rationale**: `projectm_pcm_add_float` takes interleaved LR floats with no rate parameter; the
  engine is tuned for about 44.1 kHz. Stereo is kept for presets that use channel separation.
- **Alternatives**: Feeding the native 48 kHz. Rejected: it skews the engine's beat/spectrum
  timing. Mono only. Rejected: it loses stereo presets.

## R-06 Real-time transport

- **Decision**: Each source callback copies raw samples into a preallocated per-source **SPSC ring
  buffer** (capacity 1 s at the native rate, atomics from the `Synchronization` module). Overflow
  drops the oldest data and increments a counter. A dedicated serial work queue drains the ring,
  converts and resamples (R-05), updates the `LevelMeter` and `AudioStateClassifier`, and writes
  into a second SPSC ring that the render loop reads with `projectm_pcm_add_float` up to
  `projectm_pcm_get_max_samples()` per frame.
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
  1. **Apple OpenGL ES 3.0** (EAGL + `GLKView`/`CAEAGLLayer`, load_proc via `dlsym` on the
     public OpenGLES framework symbols). Fastest path to Gate 3. Deprecated since iOS 12.
  2. **ANGLE (Metal backend) as a pinned dependency**, providing GLES 3.0 via EGL on Metal. It
     avoids the deprecated API and is the production candidate. It adds a third-party dependency
     with its own license (BSD-3) and binary size.
  A full Metal port of the engine is **not** planned. It is a large rewrite that risks preset
  fidelity (Constitution VIII), and is reconsidered only if both candidates fail.
- **Rationale**: Gets an early, measurable Gate 3 while keeping a non-deprecated route.
- **Exit criteria (ADR-0003)**: the test presets in `Vendor/projectM/presets/tests` plus 20 starter
  presets render on the reference device and the oldest iOS 26 device; fps is measured; shader
  compile failures are counted; binary size is measured.

## R-09 Presets and reference audio (RI-008)

- **Decision**: Bundle only presets with explicit redistribution licenses, starting from upstream
  ProjectM-maintained preset packs if their licenses permit. Each preset's source and license is
  recorded in `Apps/ProjectMiOS/Resources/Presets/LICENSES.md`. Reference audio is a short track
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
  conclusion (blocks release).

## R-11 Engine version pin (RI-006)

- **Decision**: Pin to the **latest upstream release tag** that passes the Phase C render proof.
  Use the current untagged commit `eae22de` only if a needed fix is not yet tagged, with the
  reason recorded in ADR-0004.
- **Rationale**: Tags are reproducible and reviewable; Constitution IX.

## R-12 Project generation and CI

- **Decision**: XcodeGen (`project.yml`, version pinned in `scripts/verify_environment.py`)
  generates the project on macOS. GitHub Actions `macos-*` runs: `swift test` per package →
  `scripts/build_projectm_xcframework.py` (cached by submodule SHA) → `xcodebuild build` and `test`
  on a simulator destination discovered at runtime. No signing secrets in CI.
- **Rationale**: Text-only project definition supports Windows editing; CI matches the README §15
  template.
- **Alternatives**: A committed `.xcodeproj` (merge conflicts, not editable on Windows). Tuist
  (heavier).

## R-13 Diagnostics and privacy-safe telemetry

- **Decision**: No network telemetry. Diagnostics are in-memory snapshots, `os_signpost`
  intervals for Instruments, and the tester-initiated export (FR-021) validated against
  [contracts/diagnostics-export.schema.json](contracts/diagnostics-export.schema.json). Logs never
  include sample data and never run on the audio thread (the work queue posts counters).
- **Rationale**: FR-060/FR-061; Constitution privacy section.

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
| R-03 background behavior | RI-003 | Gates 0, 2 | platform research + report rows |
| R-08 renderer | RI-005 | Gate 3 | ADR-0003 accepted |
| R-09 preset licenses | RI-008 | Gate 3 | Presets/LICENSES.md |
| R-10 LGPL review | RI-007 | Stage 2 entry / release | docs/adr/0005-lgpl-compliance.md |
| R-11 engine tag | RI-006 | Gate 3 | ADR-0004 updated |

Owner for all: project owner.
