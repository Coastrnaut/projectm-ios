---

description: "Task list for ProjectM-iOS Visualizer"
---

# Tasks: ProjectM-iOS Visualizer

**Input**: Design documents from `specs/001-ios-projectm-visualizer/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md),
[docs/adr](../../docs/adr/README.md)

**Tests**: Required. The constitution (X) mandates unit tests for deterministic logic and
physical-device validation for capture, lifecycle, rendering, and performance. Within each phase,
test tasks come before the implementation they cover.

**Organization**: Tasks are grouped by user story. Stories 1–3 form Stage 1 (Plan Phase A). Stories
4–7 form Stage 2 (Plan Phases B–D). Polish is Plan Phase E.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: User story label (US1–US7) for story-phase tasks
- **Tags in each description**:
  - `{A}`…`{E}` = plan phase (plan.md §Delivery Phases)
  - `{win}` = can be completed on Windows (docs, scripts, source authoring without compiling)
  - `{mac}` = requires macOS + Xcode (compile, simulator, `swift test`, CMake engine build)
  - `{device}` = requires a physical iPhone/iPad (named role from FR-032 / devices.md)
  - `AC:` = acceptance criterion for the task
- A Windows agent MAY author `{mac}` source files but MUST report their build/test status as
  "pending macOS" (Constitution: Platform). `{device}` tasks are never completed without recorded
  device evidence.

## Path Conventions

Per plan.md §Project Structure: `Apps/CaptureLab/`, `Apps/ProjectMiOS/`, `Packages/<Name>/Sources/<Name>/`,
`Packages/<Name>/Tests/<Name>Tests/`, `scripts/`, `docs/`, `project.yml`.

---

## Phase 1: Setup (Shared Infrastructure) — Plan Phase A

**Purpose**: Repository skeleton, tooling, CI, and report templates.

- [ ] T001 {A}{win} Create the directory skeleton from plan.md §Source Code: `Apps/CaptureLab/{Views,Resources}`, `Apps/ProjectMiOS/{Coordinators,Views,Resources}`, `Packages/{AudioCore,CaptureKit,Diagnostics,ProjectMBridge,Rendering}/{Sources,Tests}`, `docs/platform-research/`, `docs/test-reports/`, `scripts/` (with `.gitkeep` files) — AC: tree matches plan.md exactly
- [ ] T002 [P] {A}{win} Add `Build/`, `*.xcodeproj/`, `DerivedData/`, `.build/`, `.swiftpm/` to `.gitignore` — AC: `git status` shows no generated files after a build
- [ ] T003 [P] {A}{win} Create `scripts/validate_docs.py` that fails on dangling FR-/SC-/RI-/R- references across `specs/` and `docs/` and on invalid JSON in `contracts/diagnostics-export.schema.json` — AC: exits 0 on the current docs; exits 1 when a fake `FR-999` reference is added
- [ ] T004 [P] {A}{win} Create `scripts/verify_environment.py`: checks Xcode, iOS SDK, Swift, XcodeGen, CMake, and Python versions against pins it reads from `docs/adr/0002-minimum-ios-version.md`; on non-macOS hosts it prints "macOS required for build tasks" and exits 0 — AC: exits non-zero on macOS when any pinned tool is missing or mismatched
- [ ] T005 [P] {A}{win} Create `Packages/AudioCore/Package.swift` (swift-tools-version 6.0; platforms iOS 26, macOS 15 for host tests; no dependencies; library `AudioCore`; test target `AudioCoreTests`) — AC: manifest parses with `swift package describe` {mac}
- [ ] T006 [P] {A}{win} Create `Packages/CaptureKit/Package.swift` (depends on AudioCore; test target `CaptureKitTests`) — AC: same as T005
- [ ] T007 [P] {A}{win} Create `Packages/Diagnostics/Package.swift` (depends on AudioCore; test target `DiagnosticsTests`; test resource: a copy of `diagnostics-export.schema.json`) — AC: same as T005
- [ ] T008 {A}{win} Create `project.yml` (XcodeGen) with target `CaptureLab`: iOS 26.0 deployment, universal (iPhone + iPad), depends on AudioCore/CaptureKit/Diagnostics, Info.plist with `NSMicrophoneUsageDescription` set to the exact Microphone explainer from contracts/ui-states.md (FR-019), no background modes, no entitlements (R-16) — AC: `xcodegen generate` produces a project that builds an empty app {mac}
- [ ] T009 {A}{mac} Install the newest stable Xcode with the iOS 27 SDK; record the Xcode build, SDK, Swift, XcodeGen, and CMake versions in `docs/adr/0002-minimum-ios-version.md` (replace each `TBD`) — AC: `python3 scripts/verify_environment.py` exits 0
- [ ] T010 {A}{mac} Create `.github/workflows/ios-ci.yml` on a pinned `macos-*` runner: `scripts/validate_docs.py`, `swift test` for each package, `xcodegen generate`, `xcodebuild build test -scheme CaptureLab` on simulator destinations discovered at runtime (iOS 26 and iOS 27+ runtimes when present; log a warning if one is missing); no signing secrets — AC: workflow green on the skeleton
- [ ] T011 [P] {A}{win} Create `docs/test-reports/devices.md` (a row per FR-032 role plus the reference device: role, model, model identifier, OS build, owner) and `docs/test-reports/compatibility-report.md` (FR-031 columns, rating scale, evidence links, Stage Decision section per FR-033/FR-034) — AC: every FR-031 field has a column
- [ ] T012 [P] {A}{win} Create `docs/test-reports/performance.md` template (sections for SC-005–SC-009, SC-013–SC-015, ADR-0003 measurements, per-device rows) — AC: one section per listed SC

**Checkpoint**: Skeleton builds in CI (pending macOS on Windows hosts).

---

## Phase 2: Foundational (Blocking Prerequisites) — Plan Phase A

**Purpose**: AudioCore, CaptureKit, and Diagnostics pieces that every Stage 1 story needs.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests (write first; they must fail before implementation)

- [ ] T013 [P] {A}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/AudioStateClassifierTests.swift` covering every transition in data-model.md §Transitions with an injected clock: active when "peak ≥ −50 dBFS for ≥ 250 ms"; silent when "peak < −60 dBFS for ≥ 2 s"; "no data for 5 s" → noAudioReceived; 60 s silent → `prolongedSilenceHint` with no state change; format change → no transition; plus SC-002's 20 scripted playing/paused/absent timelines — AC: tests compile and fail against an empty stub
- [ ] T014 [P] {A}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/SPSCRingBufferTests.swift`: wraparound, drop-oldest overflow increments `droppedFrames`, underrun read returns 0, a 10-second two-thread producer/consumer stress test with no lost ordering — AC: tests fail against a stub
- [ ] T015 [P] {A}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/LevelMeterTests.swift`: a −6 dBFS sine gives peak −6 ± 0.1 dBFS and RMS −9 ± 0.1 dBFS; digital silence clamps to −120 dBFS — AC: tests fail against a stub
- [ ] T016 [P] {A}{mac} Write `Packages/CaptureKit/Tests/CaptureKitTests/CaptureManagerTests.swift` with a `FakeAudioSource`: only one active source (FR-001); switching stops the old source before starting the new one and publishes `waiting` (FR-016); `stop()` is idempotent and returns within 1 s (FR-007); 50 start/stop/switch cycles at 200 ms intervals end in the state of the last action, with no duplicate sessions (FR-052); `restart()` after a non-user stop (FR-055) — AC: tests fail against a stub
- [ ] T017 [P] {A}{mac} Write `Packages/Diagnostics/Tests/DiagnosticsTests/DiagnosticsTests.swift`: cadence mean/max, late buffer = interval > 2× mean, startToFirstAudio; exported JSON validates against the schema; JSON contains no `identifierForVendor`, serial, or advertising ID; `testerNote` rejects more than 500 characters; filename matches `CaptureLab-\d{8}-\d{6}\.(json|txt)` — AC: tests fail against a stub

### Implementation

- [ ] T018 [P] {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/AudioTypes.swift`: `AudioSourceMode` (systemAppCapture, microphone, inAppPlayback); `AudioState` (9 cases from data-model.md); `StopReason` (9 cases, `error(description)`); `AudioFormat` ("channelCount ≥ 1", sampleType float32/int16/int32); `SourceAvailability`; `LifecycleEvent`; `ClassifierThresholds` with defaults −50 dBFS/250 ms, −60 dBFS/2 s, 5 s, 60 s — AC: T013 compiles {mac}
- [ ] T019 [P] {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/SPSCRingBuffer.swift` (preallocated Float storage, capacity set at init, `Synchronization.Atomic` indices, drop-oldest on overflow, `droppedFrames` counter, no allocation after init) — AC: T014 passes {mac}
- [ ] T020 [P] {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/LevelMeter.swift` using vDSP for peak and RMS dBFS per window — AC: T015 passes {mac}
- [ ] T021 {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/AudioStateClassifier.swift` per contracts/audio-source.md (`dataArrived`, `tick`, `lifecycle`, `prolongedSilenceHint`) — AC: T013 passes {mac}
- [ ] T022 {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/PCMSink.swift`: a real-time-safe `write(_:format:frameCount:hostTime:)` that copies an `AudioBufferList` into the SPSC ring without allocating — AC: unit test writes 1 s of frames and reads them back identically {mac}
- [ ] T023 {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/AudioSource.swift` (protocol, `SourceEvent`, guarantees 1–5 from contracts/audio-source.md as doc comments) — AC: FakeAudioSource in T016 conforms {mac}
- [ ] T024 {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/CaptureManager.swift`: `@MainActor`; a serial work queue (user-interactive QoS) drains the source ring every ≤ 10 ms, runs LevelMeter + classifier, and publishes state/diagnostics to the main actor at most 4 times per second (and at least once per second) — AC: T016 passes {mac}
- [ ] T025 [P] {A}{win} Implement `Packages/Diagnostics/Sources/Diagnostics/DiagnosticsSnapshot.swift` (fields from data-model.md §AudioDiagnosticsSnapshot) — AC: T017 snapshot cases pass {mac}
- [ ] T026 {A}{win} Implement `Packages/Diagnostics/Sources/Diagnostics/DiagnosticsExporter.swift`: `schemaVersion` 1 JSON plus a human-readable .txt, filenames `CaptureLab-<UTC yyyyMMdd-HHmmss>`, `testerNote` max 500, export only when called from a user action — AC: T017 passes {mac}
- [ ] T027 [P] {A}{win} Implement `Packages/Diagnostics/Sources/Diagnostics/Logging.swift`: `Logger` wrappers where every dynamic string is `.private`; `os_signpost` interval helpers; never callable from the audio thread (debug assertion) — AC: code review confirms that no public interpolation exists
- [ ] T028 {A}{win} Implement the CaptureLab shell: `Apps/CaptureLab/CaptureLabApp.swift`; `Views/SourceChooserView.swift` (3 modes with labels, one-line descriptions, and availability per FR-080 and ui-states); `Views/DiagnosticsView.swift` (FR-020 fields, ≥ 1 Hz); `Views/StatusBanner.swift` (non-modal, FR-083); `Views/ExportView.swift` (share sheet, note field with the ui-states placeholder) — AC: builds and runs on the simulator showing all three modes {mac}

**Checkpoint**: Foundation ready. CI is green for AudioCore, CaptureKit, and Diagnostics.

---

## Phase 3: User Story 1 — Verify external-app audio capture (P1) 🎯 MVP — Plan Phase A

**Goal**: CaptureLab captures other apps' audio through the system picker and reports No audio /
Silent / Active truthfully.

**Independent Test**: quickstart.md Scenario A steps 2–3 on a capture-capable iPhone and the iOS 26
iPhone.

- [ ] T029 [US1] {A}{mac} Gate 0 research: write `docs/platform-research/screencapturekit-ios.md` from the iOS SDK headers and current Apple docs, answering every RI-001 question (picker modes and selection scope, stream configuration, audio output types, whether app audio is delivered, mic exclusion, usage-description keys, content identity, capture indicator behavior with a hidden status bar) and RI-004 (first OS version); update FR-008, FR-019/ui-states capture key text, ADR-0001 and ADR-0002 status to Accepted — AC: every RI-001/RI-004 question has a sourced answer; `scripts/validate_docs.py` passes
- [ ] T030 [US1] {A}{mac} Write `Packages/CaptureKit/Tests/CaptureKitTests/ScreenCaptureSourceTests.swift` against a `StreamDriver` protocol fake: picker cancel → `cancelled`; delegate stop → `endedBySystem`; iOS 26 availability → `.unavailable(unsupportedOS)`; interruption while the stream delivers → no state change (FR-051); `contentIdentity` is nil unless the OS identifies the content and Active audio was verified (FR-014) — AC: tests fail against a stub
- [ ] T031 [US1] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/ScreenCaptureSource.swift` behind `@available(iOS <RI-004 version>, *)` plus a runtime probe: presents the system picker only from `start` (FR-002); configures audio-only capture, excluding microphone audio (FR-069); the output handler copies the `AudioBufferList` into `PCMSink` with no allocation; delegate events map to `SourceEvent` — AC: T030 passes {mac}
- [ ] T032 [US1] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/StreamDriver.swift` (thin wrapper over the ScreenCaptureKit types so they never leave CaptureKit; Constitution VI) — AC: no ScreenCaptureKit import outside `ScreenCapture/` (grep check in CI)
- [ ] T033 [US1] {A}{win} Add lifecycle event capture to `Apps/CaptureLab/CaptureLabApp.swift` and `DiagnosticsSnapshot.lifecycleEvents` (background, foreground, lock, unlock, interruptionBegan/Ended, routeChange, streamStopped, formatChange), for RI-003 evidence — AC: events appear in the export JSON in order {mac}
- [ ] T034 [US1] {A}{device} Run US1 acceptance scenarios 1–5 on the capture-capable iPhones and the iOS 26 iPhone (devices.md roles); attach exports to `docs/test-reports/` — AC: all 5 scenarios pass and are recorded with exports
- [ ] T035 [US1] {A}{device} Collect RI-003 evidence for System/App Capture across background, lock, foreground, and interruption; record the results in `docs/platform-research/screencapturekit-ios.md` and update FR-050 / research R-03 if the behavior differs from the plan — AC: one recorded run per lifecycle event per capture-capable device

**Checkpoint**: US1 independently demonstrable in CaptureLab.

---

## Phase 4: User Story 2 — Fallback sources (P1) — Plan Phase A

**Goal**: Microphone and In-App Playback work on every device, labeled correctly.

**Independent Test**: quickstart.md Scenario A step 4 on every FR-032 device.

- [ ] T036 [P] [US2] {A}{mac} Write `Packages/CaptureKit/Tests/CaptureKitTests/MicrophoneSourceTests.swift` with injected session/notification fakes: explainer shown before permission (FR-005); denied → `permissionDenied`; no input → `microphoneUnavailable`; interruption ended with "should resume" → auto-resume, else `interrupted`; background → `paused`, foreground → `waiting` within 2 s (FR-050); permission revoked while backgrounded → `permissionDenied` on foreground (FR-053) — AC: tests fail against a stub
- [ ] T037 [P] [US2] {A}{mac} Write `Packages/CaptureKit/Tests/CaptureKitTests/InAppPlaybackSourceTests.swift`: missing or undecodable track → `inAppPlaybackFailed`; output route lost → `paused` with `audioRouteChanged`; loops until stopped; stop ≤ 1 s; never opens an input (FR-069) — AC: tests fail against a stub
- [ ] T038 [P] [US2] {A}{win} Create `scripts/generate_reference_audio.py`: a deterministic 60 s, 44.1 kHz stereo WAV with tones, sharp clicks at known times, and a beat pattern, written to `Apps/CaptureLab/Resources/reference.wav` plus `reference-clicks.json` (click timestamps, for SC-006) — AC: two runs produce byte-identical files
- [ ] T039 [US2] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/Microphone/MicrophoneSource.swift` (AVAudioEngine input tap → PCMSink; permission at point of use; interruption and route handling per data-model.md lifecycle matrix) — AC: T036 passes {mac}
- [ ] T040 [US2] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackSource.swift` (`.playback` category, AVAudioPlayerNode looping the bundled track, mixer tap → PCMSink, route-loss pause) — AC: T037 passes {mac}
- [ ] T041 [US2] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/LifecycleObserver.swift` (app background/foreground and protected-data/lock notifications → `LifecycleEvent`; permission re-check on foreground) — AC: T036/T037 lifecycle cases pass {mac}
- [ ] T042 [US2] {A}{win} Add the Microphone explainer sheet and the "Open Settings" banner action to `Apps/CaptureLab/Views/` using the exact ui-states strings — AC: UI test shows the explainer before the system prompt {mac}
- [ ] T043 [US2] {A}{device} Run US2 acceptance scenarios 1–7 on every FR-032 device; record them in the compatibility report — AC: all 7 scenarios pass on every device, and SC-004 (Active audio within 2 s) holds

**Checkpoint**: US1 and US2 both work independently.

---

## Phase 5: User Story 3 — Compatibility report and Stage 1 gate (P1) — Plan Phase A

**Goal**: Evidence-based compatibility report and the Stage 2 go/no-go decision.

**Independent Test**: quickstart.md Scenario A steps 5–9; the report is complete and reproducible.

- [ ] T044 [US3] {A}{win} Record the concrete model, model identifier, and OS build for every FR-032 role, and choose the reference device (newest capture-capable iPhone), in `docs/test-reports/devices.md` — AC: every role filled before any T045 run
- [ ] T045 [US3] {A}{device} For each FR-030 source on each applicable device, run 10 minutes in the foreground and export diagnostics into `docs/test-reports/exports/<device>/<source>/` — AC: SC-001 coverage (≥ 2 capture-capable iPhones + 1 iPad for capture sources; all devices for fallbacks)
- [ ] T046 [US3] {A}{win} Rate every report row Works / Partial / Does not work using the FR-031 thresholds, citing the exports; write the limitation for each Partial row — AC: zero "Works" rows without an export showing non-silent audio (SC-001)
- [ ] T047 [US3] {A}{device} Gate 2: for each source rated "Works", run a 30-minute foreground capture on the reference device and record unrecovered failures, dropped audio, start-to-first-audio, CPU, and memory against the Gate 2 thresholds in spec Delivery Gating — AC: each Works source passes or is downgraded to Partial with its reason
- [ ] T048 [US3] {A}{win} Finalize the Stage 1 thresholds (dBFS levels, timeouts, 200 ms cycle, Works thresholds) in the report; update FR-011/FR-012/FR-018/FR-031/FR-052 and the `ClassifierThresholds` defaults to match — AC: spec and code defaults are identical; `validate_docs.py` passes
- [ ] T049 [US3] {A}{win} Write the preliminary conclusions for RI-007 and RI-010 in `docs/adr/0005-lgpl-compliance.md` (relinking approach, upstream's App Store warning, vendored obligations) — AC: the conclusion section states go / no-go / conditional, with reasons
- [ ] T050 [US3] {A}{win} The project owner records the Stage 2 go/no-go decision, approver, date, evidence, and claimable sources in the report's Stage Decision section (FR-033) — AC: the decision is recorded; if "no external source works", the product description is updated to fallbacks only

**🚧 STAGE 1 GATE**: Nothing below this line may start until T050 records "go" and T049 is not
"no-go" (spec Stage 2 approval rule). This blocks all ProjectM engine, renderer, preset, and
visualizer work.

---

## Phase 6: Stage 2 Foundation — Plan Phase B (audio pipeline), then Plan Phase C (engine)

**Purpose**: Normalized audio pipeline, then the engine build and render proof (Gate 3). Blocks
US4–US7.

### Plan Phase B — Audio pipeline (starts after the Stage 1 gate)

- [ ] T051 [P] {B}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/NormalizerTests.swift`: mono → stereo duplication; 5.1 → stereo via the standard layout downmix; unknown layout → channels 1–2; int16/int32 → Float32; a 48 kHz 1 kHz sine resampled to 44.1 kHz keeps 1 kHz ± 1 Hz; a mid-stream format change does not stop the stream (FR-017); an unconvertible format → `error` — AC: tests fail against a stub
- [ ] T052 [P] {B}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/NormalizedReaderTests.swift`: capacity 22,050 stereo frames; freshness rule (backlog > 50 ms → skip to the newest 50 ms, counted as dropped); empty ring → `read` returns 0 (underrun policy) — AC: tests fail against a stub
- [ ] T053 {B}{win} Implement `Packages/AudioCore/Sources/AudioCore/Normalizer.swift` (AVAudioConverter on the work queue; output Float32 interleaved stereo at 44,100 Hz) — AC: T051 passes {mac}
- [ ] T054 {B}{win} Implement `Packages/AudioCore/Sources/AudioCore/NormalizedPCMReader.swift` (second SPSC ring plus the freshness rule) — AC: T052 passes {mac}
- [ ] T055 {B}{win} Wire the CaptureManager work queue → Normalizer → normalized ring, and expose `normalizedOutput` in `Packages/CaptureKit/Sources/CaptureKit/CaptureManager.swift` — AC: integration test with FakeAudioSource reads normalized frames {mac}
- [ ] T056 [P] {B}{win} Add latency signposts per stage (capture delivery, ring + conversion, normalized residency) in `Packages/Diagnostics/Sources/Diagnostics/Logging.swift` call sites — AC: an Instruments trace shows the three intervals {mac}
- [ ] T057 {B}{device} Run an allocation trace for 60 s per adapter on the reference device; record the results in `docs/test-reports/performance.md` — AC: zero heap allocations and zero lock acquisitions on the audio callback thread (Plan Phase B exit)

**Checkpoint (Plan B exit)**: The project owner accepts Phase B evidence before Phase C starts.

### Plan Phase C — Engine build and render proof (Gate 3)

- [ ] T058 {C}{win} Verify the glm license text in `Vendor/projectM/vendor/glm` (or upstream at the pinned version) and update the ADR-0004 vendored table — AC: every vendored row says "Recorded"
- [ ] T059 {C}{mac} Implement `scripts/build_projectm_xcframework.py` (RI-011): CMake per slice (`CMAKE_SYSTEM_NAME=iOS`; iphoneos arm64; iphonesimulator arm64 + x86_64; `ENABLE_GLES=ON`; shared framework), `xcodebuild -create-xcframework` → `Build/ProjectM.xcframework`; record the final flags in ADR-0004 — AC: the script succeeds from a clean checkout
- [ ] T060 {C}{mac} Add the engine build to `.github/workflows/ios-ci.yml`, cached by submodule SHA — AC: CI produces the xcframework; a cache hit on rerun
- [ ] T061 {C}{win} Create `Packages/ProjectMBridge/Package.swift` (binary target `Build/ProjectM.xcframework`, ObjC++ target `ProjectMBridge`) — AC: package resolves {mac}
- [ ] T062 {C}{mac} Write `Packages/ProjectMBridge/Tests/ProjectMBridgeTests/PMEngineTests.swift`: a malformed preset returns `NSError` `presetLoadFailed` with no exception crossing; `maxSamplesPerFrame` > 0; create/destroy 100× without leaks — AC: tests fail against a stub
- [ ] T063 {C}{win} Implement `Packages/ProjectMBridge/Sources/ProjectMBridge/PMBridge.h` and `PMBridge.mm` per contracts/projectm-bridge.md (all C++ exceptions caught, render-thread assertion, destroy on the render thread, 1:1 C API mapping, no engine patches) — AC: T062 passes {mac}
- [ ] T064 [P] {C}{win} Create `Packages/Rendering/Package.swift` and `Sources/Rendering/VisualizerRenderer.swift` (protocol plus `RenderMetrics` per the contract; fps from presentation timestamps in 1 s windows) — AC: compiles {mac}
- [ ] T065 {C}{win} Implement `Packages/Rendering/Sources/Rendering/GLESRenderer.swift` (Option A: CAEAGLLayer ES 3.0 context; load_proc = static table of linked ES 3.0 functions, no `dlsym`; display link capped at 60 fps; drains the normalized reader up to `maxSamplesPerFrame` per frame) — AC: renders the upstream test preset in the simulator {mac}
- [ ] T066 {C}{device} RI-009: on a device, record whether the engine's `dlopen` path runs with a load_proc supplied and which names it tries; record this in ADR-0003; if needed, add a minimal iOS-only patch and log it in `docs/projectm-patches.md` — AC: the ADR-0003 RI-009 section is resolved
- [ ] T067 [P] {C}{win} Select ≥ 20 starter presets with verified redistribution rights into `Apps/ProjectMiOS/Resources/Presets/`, with `LICENSES.md` rows carrying all required fields (file path, display name, pack, author, license identifier, source URL, source version) — AC: no preset is bundled without every field (FR-047)
- [ ] T068 {C}{win} Implement `Packages/Rendering/Sources/Rendering/PresetRepository.swift` (enumerates bundled presets, joins them with LICENSES.md, excludes unlicensed files, sorts alphabetically by display name) — AC: unit test with fixture presets {mac}
- [ ] T069 {C}{device} Measure Option A against the ADR-0003 thresholds on every measurement device; record in `docs/test-reports/performance.md` — AC: all threshold rows filled with numbers
- [ ] T070 {C}{mac} Pin and build ANGLE (Metal backend) reproducibly into `Build/ANGLE.xcframework`; add its row to ADR-0004 — AC: CI builds it from the pinned source
- [ ] T071 {C}{win} Implement `Packages/Rendering/Sources/Rendering/ANGLERenderer.swift` (Option B; EGL context; load_proc = `eglGetProcAddress`) — AC: renders the upstream test preset in the simulator {mac}
- [ ] T072 {C}{device} Measure Option B against the ADR-0003 thresholds on every measurement device — AC: all threshold rows filled
- [ ] T073 {C}{win} Accept ADR-0003: choose the option, record the quality tiers (mesh size, render scale, device-to-tier rule), and select the engine tag or commit per RI-006 in ADR-0004 — AC: ADR-0003 status "Accepted"; **Gate 3 passed**

**Checkpoint (Gate 3)**: The engine renders on devices. US4–US7 may start.

---

## Phase 7: User Story 4 — Full-screen visualization (P2) — Plan Phase D

**Goal**: Full-screen visualization driven by the active source.

**Independent Test**: quickstart.md Scenario C rows SC-005, SC-006, FR-041 with In-App Playback.

- [ ] T074 [US4] {D}{win} Add target `ProjectMiOS` to `project.yml` (all packages, embed and sign `ProjectM.xcframework` and ANGLE if chosen, Info.plist keys from ui-states, no background modes or extra entitlements per R-16, empty `PrivacyInfo.xcprivacy` placeholder) — AC: app builds and launches {mac}
- [ ] T075 [US4] {D}{mac} Write `Apps/ProjectMiOS/UITests/VisualizerUITests.swift`: tap toggles controls; controls hide after 5 s while the compact indicator stays visible (FR-042); rotation re-layout ≤ 1 s with no capture restart; compact width shows the single-row layout (FR-087) — AC: tests fail before T078–T080
- [ ] T076 [US4] {D}{win} Implement `Apps/ProjectMiOS/ProjectMApp.swift` and `Coordinators/AppCoordinator.swift`: launch flow per FR-081 (notice on first launch → source chooser; no auto-start) — AC: UI test covers first and second launch {mac}
- [ ] T077 [P] [US4] {D}{win} Implement `Apps/ProjectMiOS/Views/PhotosensitivityNoticeView.swift` (FR-071; acknowledgment persisted under `notice.photosensitivityAcknowledged`) — AC: shown once, before any visualization {mac}
- [ ] T078 [US4] {D}{win} Implement `Apps/ProjectMiOS/Views/VisualizerView.swift` (UIViewRepresentable hosting the renderer full-screen; portrait/landscape/split (FR-041); status bar and home indicator hidden with controls, unless that hides the capture/mic indicator per FR-086/FR-089) — AC: T075 rotation case passes {mac}
- [ ] T079 [US4] {D}{win} Implement `Apps/ProjectMiOS/Views/ControlsOverlay.swift` (FR-082 contents, 5 s auto-hide, always-visible compact indicator (FR-042), compact layout with the preset browser as a sheet (FR-087)) — AC: T075 passes {mac}
- [ ] T080 [US4] {D}{win} Suppress device auto-lock while the visualization runs in the foreground and restore it on pause/stop/background (FR-084), in `Coordinators/AppCoordinator.swift` — AC: unit test of idle-timer state per visualization state {mac}
- [ ] T081 [US4] {D}{device} Run US4 acceptance 1–4 and SC-006 (240 fps camera, 20 clicks from `reference-clicks.json`, median < 150 ms) on the reference device; verify FR-084 by visualizing past the auto-lock interval — AC: all pass; results in performance.md

---

## Phase 8: User Story 5 — Presets and favorites (P2) — Plan Phase D

**Goal**: Browse, switch, randomize, and favorite presets.

**Independent Test**: quickstart.md Scenario C row SC-007 plus US5 scenarios.

- [ ] T082 [P] [US5] {D}{mac} Write `Apps/ProjectMiOS/Tests/PresetTests.swift`: favorites persist under `favorites` and `lastPresetID`; alphabetical order; random never returns the current preset (FR-088); empty-favorites text; a failed load keeps the previous preset (FR-045) — AC: tests fail against a stub
- [ ] T083 [US5] {D}{win} Implement `Apps/ProjectMiOS/Coordinators/FavoritesStore.swift` (only the FR-065 keys) — AC: T082 persistence cases pass {mac}
- [ ] T084 [US5] {D}{win} Implement `Apps/ProjectMiOS/Views/PresetBrowserView.swift` (FR-043/FR-044/FR-088; closes on selection; favorites filter and empty state) — AC: T082 UI cases pass {mac}
- [ ] T085 [US5] {D}{win} Wire Next/Previous/Random and the preset-failure banner ("Preset could not be loaded") in `Apps/ProjectMiOS/Coordinators/PresetCoordinator.swift`; blend ≤ 2 s — AC: T082 passes {mac}
- [ ] T086 [US5] {D}{device} Run US5 acceptance 1–4 and SC-007 (Next × 50: 95% of first frames within 1 s) on the reference device — AC: pass; recorded in performance.md

---

## Phase 9: User Story 6 — Source status and capture control (P2) — Plan Phase D

**Goal**: Truthful status, stop/pause/resume, and recovery.

**Independent Test**: quickstart.md Scenario C row SC-010 plus US6 scenarios.

- [ ] T087 [P] [US6] {D}{mac} Write `Apps/ProjectMiOS/UITests/StatusUITests.swift` with a fake source: every FR-010 state string and FR-015 message/action from ui-states; visualization pause does not change the audio state (FR-046); paused frame dimmed with "Paused" (FR-085); Ended by system → Restart re-presents the picker (FR-055) — AC: tests fail before T088–T090
- [ ] T088 [US6] {D}{win} Implement `Apps/ProjectMiOS/Views/SourceStatusIndicator.swift` and `Views/StatusBanner.swift` from the ui-states tables (FR-013, FR-015, FR-083) — AC: T087 string cases pass {mac}
- [ ] T089 [US6] {D}{win} Implement Stop / Pause / Resume and `VisualizationState` (running, paused, suspended) in `Apps/ProjectMiOS/Coordinators/AppCoordinator.swift` (FR-007, FR-046, FR-085) — AC: T087 passes {mac}
- [ ] T090 [US6] {D}{win} Implement one-tap restart per the data-model lifecycle matrix (System/App Capture re-presents the picker; mic/in-app restart directly) in `Coordinators/AppCoordinator.swift` (FR-055) — AC: T087 restart cases pass {mac}
- [ ] T091 [US6] {D}{device} Run US6 acceptance 1–4 on the reference device and an iPad; run SC-010 usability with ≥ 8 participants not involved in development (≥ 3 on iPad) — AC: all pass; ≥ 90% correct identification

---

## Phase 10: User Story 7 — Lifecycle and interruption resilience (P3) — Plan Phase D

**Goal**: Predictable behavior across background, lock, interruptions, route changes, and thermal pressure.

**Independent Test**: quickstart.md Scenario C row SC-009.

- [ ] T092 [P] [US7] {D}{mac} Write `Apps/ProjectMiOS/Tests/LifecycleCoordinatorTests.swift`: for each adapter, every row of the data-model lifecycle matrix (background/lock = FR-054, foreground auto-resume ≤ 2 s, interruption, route change) — AC: tests fail against a stub
- [ ] T093 [US7] {D}{win} Implement `Apps/ProjectMiOS/Coordinators/LifecycleCoordinator.swift` (suspend the visualization on background/lock; apply the per-adapter matrix; banners via ui-states) — AC: T092 passes {mac}
- [ ] T094 [US7] {D}{win} Implement thermal and low-power adaptation in `Packages/Rendering/Sources/Rendering/QualityGovernor.swift` (lower fps or render scale, never below 30 fps; labels and audio state unaffected, FR-049) — AC: unit test of each thermal state → settings {mac}
- [ ] T095 [US7] {D}{device} Run the US7 scripted sequence per source mode and SC-009 (50 cycles at 200 ms plus the lifecycle script) on the reference device and the oldest iPhone — AC: zero crashes, correct final states
- [ ] T096 [US7] {D}{device} Gate 4: run SC-005, SC-008, SC-013, SC-014, and SC-015 on the reference device and the oldest iOS 26 iPhone/iPad; finalize the Stage 2 thresholds in `docs/test-reports/performance.md` and update the affected FR/SC lines — AC: all targets met or thresholds formally revised by the project owner; **Gate 4 passed**

---

## Phase 11: Polish & Cross-Cutting Concerns — Plan Phase E (release)

- [ ] T097 [P] {E}{win} Implement `Apps/ProjectMiOS/Views/SettingsView.swift`: performance overlay toggle (default off, FR-048), "Reduce flashing" (nil → follow Reduce Motion, FR-072), and the Licenses screen listing ADR-0004 components and LICENSES.md presets with license texts and the LGPL source/replacement note (FR-067) — AC: UI test covers all three {mac}
- [ ] T098 {E}{win} Implement the Reduce-flashing post-pass in the chosen renderer (`Packages/Rendering/Sources/Rendering/FlashLimiter.swift`) — AC: ≤ 2 ms per frame on the reference device {device}
- [ ] T099 [P] {E}{win} Add accessibility labels, state announcements, and Dynamic Type to all controls and the indicator (FR-070) — AC: SC-012 screen-reader audit passes on iPhone and iPad {device}
- [ ] T100 [P] {E}{win} Fill `Apps/ProjectMiOS/PrivacyInfo.xcprivacy` with every required-reason API used and its approved reason (FR-066); draft the App Privacy answers as "Data Not Collected" in `docs/release/app-privacy.md` — AC: Xcode privacy report shows no undeclared APIs {mac}
- [ ] T101 [P] {E}{win} Write `docs/privacy-policy.md` covering every FR-063 point — AC: each FR-063 clause maps to a paragraph
- [ ] T102 {E}{device} SC-011 privacy review: inspect the app container after sessions (only FR-065 keys, no audio files) and run a proxy capture showing zero network connections (FR-068) — AC: findings recorded in `docs/test-reports/privacy-review.md`, with zero violations
- [ ] T103 {E}{win} Write the final ADR-0005 conclusion for RI-007 and RI-010 — AC: status "go"; otherwise the release is blocked
- [ ] T104 [P] {E}{win} Review the store listing and in-app help against the report's "Works" rows (FR-062: scoped by OS/device class/app version; no Partial claims; iPad only with an iPad "Works" row) in `docs/release/store-copy.md` — AC: every claim cites a report row
- [ ] T105 [P] {E}{win} Entitlements and Info.plist review against R-16 in `docs/release/entitlements-review.md` — AC: no capability beyond R-16
- [ ] T106 {E}{device} Full quickstart.md run (Scenarios A–D) on the release build; write `docs/test-reports/release-report.md` — AC: every quickstart row passes or has an owner-approved waiver

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** → **Foundational (Phase 2)** → **US1 (3)** and **US2 (4)** → **US3 (5)** →
  **🚧 Stage 1 Gate (T050)** → **Plan B (T051–T057)** → **Plan C (T058–T073, Gate 3)** → **US4–US7
  (7–10)** → **Polish (11)**.
- Plan phases are strictly sequential (spec Delivery Gating): B starts only after T050; C only after
  the Plan B exit (T057 accepted); US4–US7 only after T073 (Gate 3).
- T029 (Gate 0) blocks T031; T009 blocks every `{mac}` build task.

### User Story Dependencies

- **US1, US2**: depend only on Foundational; they can proceed in parallel.
- **US3**: needs US1 and US2 working on devices (T034, T043).
- **US4**: needs Gate 3. **US5, US6**: need US4's app target (T074) and overlay (T079). **US7**:
  needs US4 and US6 (status banners).

### Within Each Story

Tests → model/types → source/coordinator → UI → device acceptance.

### Parallel Opportunities

- Setup: T002–T007 and T011–T012 in parallel.
- Foundational tests T013–T017 in parallel; implementations T018–T020 and T025, T027 in parallel.
- US1 and US2 in parallel after Phase 2 (different packages: `ScreenCapture/` vs `Microphone/`, `InAppPlayback/`).
- Plan B tests T051–T052 in parallel; T067 (presets) in parallel with T059–T065.
- US5 (T082–T085) and US6 (T087–T090) in parallel after T079.
- Polish: T097, T099–T101, T104, T105 in parallel.

## Parallel Example: User Story 2

```text
T036 MicrophoneSourceTests.swift      ‖  T037 InAppPlaybackSourceTests.swift  ‖  T038 generate_reference_audio.py
then: T039 MicrophoneSource.swift      ‖  T040 InAppPlaybackSource.swift
then: T041 LifecycleObserver.swift → T042 explainer UI → T043 {device} acceptance
```

## Implementation Strategy

### MVP First (User Story 1)

1. Phases 1–2, then Phase 3 (US1): CaptureLab proves or disproves external-app capture on a device.
2. **Stop and validate**: T034/T035 evidence answers the central product risk.

### Incremental Delivery

1. US2 adds the fallbacks, so the product is viable even if US1 fails.
2. US3 produces the report and the Stage 2 decision (**the gate**).
3. Plan B → Plan C (Gate 3) → US4 → US5/US6 → US7 (Gate 4) → Polish → release.

### Host Split

- Windows agents: all `{win}` tasks (docs, scripts, Swift/ObjC++ source authoring), reporting
  `{mac}` verification as pending.
- macOS: every `{mac}` task and the CI.
- Device owner: every `{device}` task, with exports and reports committed as evidence.
