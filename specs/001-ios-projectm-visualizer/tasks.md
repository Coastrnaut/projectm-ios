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

**Numbering map**: Spec Stage 1 = Plan Phase A = Constitution Phase 0 = task Phases 1–5. Spec Stage 2
= Plan Phases B, C, D = Constitution Phases 1, 2, 3 = task Phases 6–10. Release = Plan Phase E =
Constitution Phase 4 = task Phase 11. Gates 0–4 are named where they occur.

## Implementation Status (updated 2026-11-08, `/speckit-implement` Phase 0 run)

**Project Mac run (2026-11-08, Xcode 27.2, iOS SDK 27.2):** T010, T017 and T035 done. Package tests
pass on the macOS host and on the iOS 27.2 and 26.5 simulators (AudioCore 50, CaptureKit 65,
Diagnostics 8, CaptureUI 10, after the owner rulings of 2026-11-08: new stop reason
`screenRecordingNotAllowed`, export schemaVersion 2 with `session.stopDetail`); CaptureLab UI tests
(3) pass on both simulators; script tests (28)
pass; all packages and CaptureLab build for iOS devices with 0 warnings, including the
ScreenCaptureKit driver. A multi-agent review found and fixed bugs simulators could not show,
including a driver bug that would have dropped every System/App Capture buffer, an AV tap crash, and
session/timing errors in exports. No device run yet; the earlier notes below are the Windows run.

**Owner review implementation (2026-11-08):** the owner accepted ADR-0001 and ADR-0002 (Gate 0
met). Implemented and verified on the project Mac: Stop, Restart or another source cancels a start
that is queued or waiting on the system picker (CaptureKit 74 tests on the host and on the iOS
27.2 and 26.5 simulators; CaptureLab keeps Stop enabled while a start is in flight); the Screen
Recording entitlement (added, then removed on 2026-11-09 because only organization accounts can
provision it; ADR-0001 ruling 16); the explicit ScreenCaptureKit weak link (Debug and Release device builds load it as
`LC_LOAD_WEAK_DYLIB`); the compliance hardening, the entitlement allowlist and the Xcode build check
(54 script tests); CaptureLab UI tests (3) on both simulators; the iOS 26.5 runtime 23F73 removed.
The CI changes (main job on `macos-26`, iOS 27 simulator tests in `build-ios27`) are green in
run 42552713447. New device task: T113.

- `[X]` = acceptance criterion verified. ⏳ = written but not yet verifiable here.
- Host: Windows 11 plus WSL Ubuntu 24.04 with Swift 6.4.2 (user-local swiftly install). The
  platform-independent packages compile and pass `swift test` on Linux: **AudioCore 40, CaptureKit 33,
  Diagnostics 7, CaptureUI 4 (84 tests, 0 failures)**. Apple-only code (ScreenCaptureKit, AVFAudio,
  UIKit, SwiftUI, os) is compiled out on Linux and is still unverified; the iOS build and every
  device criterion remain pending macOS/Xcode and devices.
- Linux runs exercise LevelMeter's scalar path; the vDSP path runs only on Apple platforms.
- GitHub Actions (2026-11-08, run 42492340431, all green): package tests on the macOS host (vDSP path)
  and on the iOS Simulator; all packages and CaptureLab build for generic iOS (Xcode 26.6, iOS SDK
  26.5). ScreenCaptureKit is absent from that SDK, so the System/App Capture driver has not been
  compiled anywhere yet (needs the iOS 27 SDK on the MacBook).
- Verified on Windows: `python scripts/test_scripts.py` (15 tests: validate_docs, check_compliance,
  verify_environment, reference-audio determinism and segments, UI strings vs contract, schema copy).
- Not started (need the project owner or devices): T040, T041, T049–T054, T056, T113.
- **No source is rated yet; no source is claimed to work.** First device run 2026-11-09: D1 and
  D2, System/App Capture with Spotify, non-silent audio in short runs (exports in
  `docs/test-reports/exports/`); T040 stays open (D3, scenarios 2-5, SC-003).

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

- [X] T001 {A}{win} Create the directory skeleton from plan.md §Source Code: `Apps/CaptureLab/{Views,Resources}`, `Apps/ProjectMiOS/{Coordinators,Views,Resources}`, `Packages/{AudioCore,CaptureKit,Diagnostics,ProjectMBridge,Rendering}/{Sources,Tests}`, `docs/platform-research/`, `docs/test-reports/`, `scripts/` (with `.gitkeep` files) — AC: tree matches plan.md exactly
- [X] T002 [P] {A}{win} Add `Build/`, `*.xcodeproj/`, `DerivedData/`, `.build/`, `.swiftpm/` to `.gitignore` — AC: `git status` shows no generated files after a build — ✅ verified 2026-11-08: CI clean-tree check passes after all builds (CI run 42492340431); it caught the XcodeGen Info.plist, now ignored
- [X] T003 [P] {A}{win} Create `scripts/validate_docs.py` that fails on dangling FR-/SC-/RI-/R- references across `specs/` and `docs/` and on invalid JSON in `contracts/diagnostics-export.schema.json` — AC: exits 0 on the current docs; exits 1 when a test fixture file under `scripts/fixtures/` cites a requirement ID that the spec does not define (fixtures are excluded from the normal scan)
- [X] T004 [P] {A}{win} Create `scripts/verify_environment.py`: checks Xcode, iOS SDK, Swift, XcodeGen, CMake, and Python versions against pins it reads from `docs/adr/0002-minimum-ios-version.md`; on non-macOS hosts it prints "macOS required for build tasks" and exits 0 — AC: exits non-zero on macOS when any pinned tool is missing or mismatched — ✅ verified 2026-11-08: exits 0 on Windows; exits non-zero on macOS while pins are TBD (CI run 42492340431)
- [X] T005 [P] {A}{win} Create `Packages/AudioCore/Package.swift` (swift-tools-version 6.0; platforms iOS 26, macOS 15 for host tests; no dependencies; library `AudioCore`; test target `AudioCoreTests`) — AC: manifest parses with `swift package describe` {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T006 [P] {A}{win} Create `Packages/CaptureKit/Package.swift` (depends on AudioCore; test target `CaptureKitTests`) — AC: same as T005 — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T007 [P] {A}{win} Create `Packages/Diagnostics/Package.swift` (depends on AudioCore; test target `DiagnosticsTests`; test resource: a copy of `diagnostics-export.schema.json`) — AC: same as T005 — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T008 [P] {A}{win} Create `Packages/CaptureUI/Package.swift` (depends on CaptureKit; SwiftUI views shared by CaptureLab and ProjectMiOS; test target `CaptureUITests`) — AC: same as T005 — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T009 {A}{win} Create `project.yml` (XcodeGen) with target `CaptureLab`: iOS 26.0 deployment, iPhone and iPad device family, separate bundle ID suffix `.CaptureLab`, depends on AudioCore/CaptureKit/Diagnostics/CaptureUI, Info.plist with `NSMicrophoneUsageDescription` set to the exact Microphone explainer from contracts/ui-states.md (FR-019), no background modes, no entitlements (R-16) — AC: `xcodegen generate` produces a project that builds an empty app {mac} — ✅ verified 2026-11-08: `xcodegen generate` + unsigned generic-iOS CaptureLab build succeed (CI run 42492340431, Xcode 26.6, iOS SDK 26.5)
- [X] T010 {A}{mac} Install the newest stable Xcode with the iOS 27 SDK; record the Xcode build, SDK, Swift, XcodeGen, and CMake versions in `docs/adr/0002-minimum-ios-version.md` (replace each `TBD`) — AC: `python3 scripts/verify_environment.py` exits 0 — ✅ verified 2026-11-08 on the project Mac: Xcode 27.2 (27B52), iOS SDK 27.2, Swift 6.4.2, XcodeGen 2.46.0, CMake 4.4.5; `verify_environment.py` exits 0. CI installs the pinned XcodeGen (checksum-verified), but GitHub's runner offers only Xcode 26.x, so CI's Xcode/SDK gap is documented in ADR-0002 (since then the `build-ios27` job compiles the driver on GitHub's `xcode-27` image). Owner review 2026-11-08: `verify_environment.py` also requires the Xcode build 27B52 (ADR-0002 ruling 5), and prints "Xcode build: 27B52 OK" on the project Mac
- [X] T011 {A}{mac} Create `.github/workflows/ios-ci.yml` on a pinned `macos-*` runner: `scripts/validate_docs.py`, `swift test` for each package, `xcodegen generate`, `xcodebuild build test -scheme CaptureLab` on simulator destinations discovered at runtime (iOS 26 and iOS 27+ runtimes when present; log a warning if one is missing); no signing secrets — AC: workflow green on the skeleton — ✅ verified 2026-11-08: workflow green — docs/compliance, Linux package tests, macOS host + iOS Simulator package tests, iOS builds (CI run 42492340431) — Note 2026-11-08: CI builds the CaptureLab scheme but does not run `xcodebuild test -scheme CaptureLab`; the CaptureLab UI tests (added 2026-11-08) run on the project Mac only
- [X] T012 [P] {A}{win} Create `docs/test-reports/devices.md` (a row per FR-032 role plus the reference device: role, model, model identifier, OS build, owner) and `docs/test-reports/compatibility-report.md` (FR-031 columns, rating scale, evidence links, Stage Decision section per FR-033/FR-034) — AC: every FR-031 field has a column
- [X] T013 [P] {A}{win} Create `docs/test-reports/performance.md` template (sections for SC-005–SC-009, SC-013–SC-015, ADR-0003 measurements, per-device rows) — AC: one section per listed SC
- [X] T014 {A}{win} Create `scripts/check_compliance.py` enforcing the constitution on every merge (FR-003, FR-009, FR-068, Constitution I/III/VI): fail on any `import ReplayKit`, any `dlsym`/`dlopen`/`NSClassFromString`/`performSelector` with string literals in `Apps/` or `Packages/`, private framework paths (`/System/Library/PrivateFrameworks`), `import ScreenCaptureKit` outside `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/`, networking APIs (`URLSession`, `Network`, `NWConnection`, `CFNetwork`, `WKWebView`) anywhere, and entitlements beyond research R-16 in `project.yml`; also add `.github/pull_request_template.md` with a checkbox per constitution principle — AC: exits 0 on the clean tree; exits 1 on a fixture file containing `import ReplayKit`. Updated 2026-11-08 (owner review; ADR-0001 ruling 13 and Decision 6): also catches kind-qualified imports and quoted or flow-style `project.yml` keys; allows `CODE_SIGN_ENTITLEMENTS` only with `Apps/CaptureLab/CaptureLab.entitlements` and any `*.entitlements` file only with the Screen Recording entitlement; 54 script tests pass on the project Mac
- [X] T015 {A}{mac} Add `scripts/check_compliance.py` as a required step in `.github/workflows/ios-ci.yml` before the build steps — AC: CI fails when a compliance fixture is introduced on a test branch — ✅ verified 2026-11-08: negative test run 42491957245 (branch with `import ReplayKit`) failed at the compliance step and skipped the later jobs
- [X] T016 {A}{win} Configure CaptureLab for tester-only distribution (FR-090): `project.yml` scheme `CaptureLab` with no App Store archive action, and `docs/release/capturelab-distribution.md` describing TestFlight-only use — AC: the document exists and the ProjectMiOS release checklist (T112) checks that CaptureLab is never submitted
- [X] T017 {A}{win} Record the concrete model, model identifier, and OS build for every FR-032 role, and choose the reference device (newest capture-capable iPhone), in `docs/test-reports/devices.md` (FR-034: before any device testing) — AC: every role filled before the first `{device}` task — ✅ verified 2026-11-08: D1 iPhone15,4 iOS 27.0.1 (24A446) = reference; D2 iPad17,3 iPadOS 27.2 (24B119); D3 iPad15,7 iPadOS 26.5 (23F77), read with `xcrun devicectl list devices` (Xcode 27.2) on the paired devices before any device task; other FR-032 roles N/A by owner decision

**Checkpoint**: Skeleton builds in CI (pending macOS on Windows hosts).

---

## Phase 2: Foundational (Blocking Prerequisites) — Plan Phase A

**Purpose**: AudioCore, CaptureKit, and Diagnostics pieces that every Stage 1 story needs.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests (write first; they must fail before implementation)

- [X] T018 [P] {A}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/AudioStateClassifierTests.swift` covering every transition in data-model.md §Transitions with an injected clock: active when "peak ≥ −50 dBFS for ≥ 250 ms"; silent when "peak < −60 dBFS for ≥ 2 s"; "no data for 5 s" → noAudioReceived; 60 s silent → `prolongedSilenceHint` with no state change; format change → no transition; plus SC-002's 20 scripted playing/paused/absent timelines — AC: tests compile and fail against an empty stub — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T019 [P] {A}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/SPSCRingBufferTests.swift`: wraparound, drop-oldest overflow increments `droppedFrames`, underrun read returns 0, a 10-second two-thread producer/consumer stress test with no lost ordering — AC: tests fail against a stub — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T020 [P] {A}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/LevelMeterTests.swift`: a −6 dBFS sine gives peak −6 ± 0.1 dBFS and RMS −9 ± 0.1 dBFS; digital silence clamps to −120 dBFS — AC: tests fail against a stub — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T021 [P] {A}{mac} Write `Packages/CaptureKit/Tests/CaptureKitTests/CaptureManagerTests.swift` with a `FakeAudioSource`: only one active source (FR-001); switching stops the old source before starting the new one and publishes `waiting` (FR-016); `stop()` is idempotent and returns within 1 s (FR-007); 50 start/stop/switch cycles at 200 ms intervals end in the state of the last action, with no duplicate sessions (FR-052); `restart()` after a non-user stop (FR-055) — AC: tests fail against a stub — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T022 [P] {A}{mac} Write `Packages/Diagnostics/Tests/DiagnosticsTests/DiagnosticsTests.swift`: cadence mean/max, late buffer = interval > 2× mean, startToFirstAudio; exported JSON validates against the schema; JSON contains no `identifierForVendor`, serial, or advertising ID; `testerNote` rejects more than 500 characters; filename matches `CaptureLab-\d{8}-\d{6}\.(json|txt)` (FR-021, FR-022) — AC: tests fail against a stub — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)

### Implementation

- [X] T023 [P] {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/AudioTypes.swift`: `AudioSourceMode` (systemAppCapture, microphone, inAppPlayback); `AudioState` (9 cases from data-model.md); `StopReason` (9 cases, `error(description)`); `AudioFormat` ("channelCount ≥ 1", sampleType float32/int16/int32); `SourceAvailability`; `LifecycleEvent`; `ClassifierThresholds` with defaults −50 dBFS/250 ms, −60 dBFS/2 s, 5 s, 60 s — AC: T018 compiles {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T024 [P] {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/SPSCRingBuffer.swift` (preallocated Float storage, capacity set at init, `Synchronization.Atomic` indices, drop-oldest on overflow, `droppedFrames` counter, no allocation after init) — AC: T019 passes {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T025 [P] {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/LevelMeter.swift` using vDSP for peak and RMS dBFS per window — AC: T020 passes {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T026 {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/AudioStateClassifier.swift` per contracts/audio-source.md (`dataArrived`, `tick`, `lifecycle`, `prolongedSilenceHint`) — AC: T018 passes {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T027 {A}{win} Implement `Packages/AudioCore/Sources/AudioCore/PCMSink.swift`: a real-time-safe `write(_:format:frameCount:hostTime:)` that copies an `AudioBufferList` into the SPSC ring without allocating — AC: unit test writes 1 s of frames and reads them back identically {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T028 {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/AudioSource.swift` (protocol, `SourceEvent`, guarantees 1–5 from contracts/audio-source.md as doc comments) — AC: FakeAudioSource in T021 conforms {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T029 {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/CaptureManager.swift`: `@MainActor`; a serial work queue (user-interactive QoS) drains the source ring every ≤ 10 ms, runs LevelMeter + classifier, and publishes state/diagnostics to the main actor at most 4 times per second (and at least once per second) — AC: T021 passes {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T030 [P] {A}{win} Implement `Packages/Diagnostics/Sources/Diagnostics/DiagnosticsSnapshot.swift` (fields from data-model.md §AudioDiagnosticsSnapshot) — AC: T022 snapshot cases pass {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T031 {A}{win} Implement `Packages/Diagnostics/Sources/Diagnostics/DiagnosticsExporter.swift`: `schemaVersion` 1 JSON plus a human-readable .txt, filenames `CaptureLab-<UTC yyyyMMdd-HHmmss>`, `testerNote` max 500, export only when called from a user action (FR-021) — AC: T022 passes {mac} — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2) — Note 2026-11-08: the export is now schemaVersion 2, which adds the optional `session.stopDetail` (owner ruling)
- [X] T032 [P] {A}{win} Implement `Packages/Diagnostics/Sources/Diagnostics/Logging.swift`: `Logger` wrappers where every dynamic string is `.private`; `os_signpost` interval helpers; never callable from the audio thread (debug assertion) — AC: code review confirms that no public interpolation exists — ✅ verified 2026-11-08 by code review (all interpolations `.private`); compiles only on Apple platforms, build pending macOS
- [X] T033 {A}{win} Implement the shared views in `Packages/CaptureUI/Sources/CaptureUI/`: `SourceChooserView.swift` (3 modes with labels, one-line descriptions, and availability per FR-080 and ui-states) and `StatusBanner.swift` (non-modal banner with the ui-states actions, FR-083) — AC: SwiftUI previews render all modes and every StopReason message {mac} — ✅ verified 2026-11-08 on the project Mac: all six previews in `Packages/CaptureUI/Sources/CaptureUI/Previews.swift` render in Xcode 27.2's preview canvas, read on screen via computer use. The chooser shows the three modes with the ui-states labels and descriptions: all available (iOS 27), then System/App Capture disabled with "Requires a newer iOS version" (iOS 26) or "Screen recording not allowed". The banner shows all 10 StopReason messages with their ui-states actions and every state with the no-audio and silence hints, and the microphone explainer renders. Canvas device: Automatic (iPhone 18 Pro); the 10-banner list is taller than that screen, so it was read on the iPad 13-inch. `ViewRenderTests` also smoke-render these views, and the chooser renders in the running app (`CaptureLabUITests`, iOS 27.2 and 26.5 simulators)
- [X] T034 {A}{win} Implement the CaptureLab shell: `Apps/CaptureLab/CaptureLabApp.swift` using CaptureUI's chooser and banner; `Views/DiagnosticsView.swift` (FR-020 fields, ≥ 1 Hz); `Views/ExportView.swift` (share sheet, note field with the ui-states placeholder) — AC: builds and runs on the simulator showing all three modes {mac} — ✅ verified 2026-11-08 on the project Mac: `CaptureLabUITests.testChooserShowsAllThreeModes` passes on the iOS 27.2 (iPhone 17) and iOS 26.5 (iPad A16) simulators; all three modes are listed and System/App Capture is disabled, because the Simulator SDK has no ScreenCaptureKit. Simulator only; device behavior is T040/T049

**Checkpoint**: Foundation ready. CI is green for AudioCore, CaptureKit, CaptureUI, and Diagnostics, and the compliance check passes.

---

## Phase 3: User Story 1 — Verify external-app audio capture (P1) 🎯 MVP — Plan Phase A

**Goal**: CaptureLab captures other apps' audio through the system picker and reports No audio /
Silent / Active truthfully.

**Independent Test**: quickstart.md Scenario A steps 2–3 on a capture-capable iPhone and the iOS 26
iPhone.

- [X] T035 [US1] {A}{mac} Gate 0 research: write `docs/platform-research/screencapturekit-ios.md` from the iOS SDK headers and current Apple docs, answering every RI-001 question (picker modes and selection scope, stream configuration, audio output types, whether app audio is delivered, mic exclusion, usage-description keys, content identity, capture indicator behavior with a hidden status bar) and RI-004 (first OS version); update FR-008, FR-019/ui-states capture key text, ADR-0001 and ADR-0002 status to Accepted — AC: every RI-001/RI-004 question has a sourced answer; `scripts/validate_docs.py` passes — ✅ verified 2026-11-08: `docs/platform-research/screencapturekit-ios.md` answers every RI-001/RI-004 question from the iOS 27.2 SDK headers and Apple's docs (each answer sourced, or marked device-only with its deciding task); FR-008 (iOS 27.0), FR-019 (`NSScreenCaptureUsageDescription`, contract text in ui-states) updated; ADR-0001 and ADR-0002 accepted by this task, then by the owner (owner review 2026-11-08; ADR-0001 amended to declare the Screen Recording entitlement); `validate_docs.py` passes. Owner rulings 2026-11-08: RI-003 is checked at Gate 2, not Gate 0; background mode decided after T041; stop detail exported; capture-specific reason for -3801 and `isAvailable` false; `xcode-27` CI job
- [X] T036 [US1] {A}{mac} Write `Packages/CaptureKit/Tests/CaptureKitTests/ScreenCaptureSourceTests.swift` against a `StreamDriver` protocol fake: picker cancel → `cancelled`; delegate stop → `endedBySystem`; iOS 26 availability → `.unavailable(unsupportedOS)`; interruption while the stream delivers → no state change (FR-051); `contentIdentity` is nil unless the OS identifies the content and Active audio was verified (FR-014) (FR-004) — AC: tests fail against a stub — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T037 [US1] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/ScreenCaptureSource.swift` behind `@available(iOS N, *)`, where N is the first capture-capable iOS version recorded by T035 (RI-004), plus a runtime probe: presents the system picker only from `start` (FR-002); configures audio-only capture, excluding microphone audio (FR-069); the output handler copies the `AudioBufferList` into `PCMSink` with no allocation; delegate events map to `SourceEvent` — AC: T036 passes {mac} — ✅ verified 2026-11-08: T036 passes (macOS host; iOS 27.2 and 26.5 simulators); the real driver builds for iOS 27.2 devices with 0 warnings. A review found the first version would have dropped every audio buffer (wrong AudioBufferList size, CoreMedia error -12737); the copy now asks CoreMedia for the exact size and is covered by host tests with synthetic planar and interleaved buffers (`SampleBufferAudioTests`). N = 27.0 (T035); runtime probe `isAvailable` at start; stop drains the sample-handler queues. Never run on a device: behavior pending T040; allocation check T050 — Note 2026-11-08: the `isAvailable` probe now also decides availability (`screenRecordingNotAllowed`, owner ruling), and -3801 keeps its code in the stop detail
- [X] T038 [US1] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/ScreenCapture/StreamDriver.swift` (thin wrapper over the ScreenCaptureKit types so they never leave CaptureKit; Constitution VI) — AC: no ScreenCaptureKit import outside `ScreenCapture/` (grep check in CI) — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T039 [US1] {A}{win} Add lifecycle event capture to `Apps/CaptureLab/CaptureLabApp.swift` and `DiagnosticsSnapshot.lifecycleEvents` (background, foreground, lock, unlock, interruptionBegan/Ended, routeChange, streamStopped, formatChange), for RI-003 evidence — AC: events appear in the export JSON in order {mac} — ✅ verified 2026-11-08 on the iOS 27.2 and 26.5 simulators: `CaptureLabUITests.testBackgroundForegroundAreExported` runs In-App Playback → background → foreground → export, then `python3 scripts/check_capturelab_export.py --udid <sim>` confirms `background` before `foreground` with non-decreasing times. Events are now stamped with the session clock when handled. Lock/unlock and interruptions cannot be driven on a simulator (device: T041)
- [ ] T040 [US1] {A}{device} Run US1 acceptance scenarios 1–5 on D1 (iPhone, capture-capable), D2 (iPad, capture-capable), and D3 (iPadOS 26; scenario 5); attach exports to `docs/test-reports/` — AC: all 5 scenarios pass and are recorded with exports; SC-003 measured over 20 silent↔active trials (≥ 95% shown within 2 s)
- [ ] T041 [US1] {A}{device} Collect RI-003 evidence for System/App Capture across background, lock, foreground, and interruption; record the results in `docs/platform-research/screencapturekit-ios.md` and update FR-050 / research R-03 if the behavior differs from the plan — AC: one recorded run per lifecycle event per capture-capable device
- [ ] T113 [US1] {A}{device} Device checks no other task requires (owner review 2026-11-08, ADR-0001 ruling 11), run in the T040 and T041 sessions on D1 and D2 and recorded in `docs/platform-research/screencapturekit-ios.md` ("Open until device testing"): what `present()` offers (item 12); `isAvailable` (14); whether a system capture indicator appears (quickstart A.2 tester note; if none, the owner decides on an in-app indicator, ruling 10); the microphone stays out (13); `excludesCurrentProcessAudio` with the approved test-tone build (8); an audio-only stream with the approved build without the `.screen` output (2); the minimum video size (3; if 64 × 64 is refused, a mid size, then the native size); picker callbacks and Stop cancelling a waiting start (10); FairPlay audio (11); a Control Center re-pick and a stop of sharing from system UI during capture, with callbacks, stop code and whether audio continues, in the T041 session (9, quickstart A.5); and, if audio is silent with `present()`, one diagnostic run with `present(using: .display)` before T056 (ruling 6). Temporary builds are diagnostic only and never compatibility evidence — AC: each item has a recorded result with its export or tester note on D1 and D2; required before Gate 1

**Checkpoint**: US1 independently demonstrable in CaptureLab.

---

## Phase 4: User Story 2 — Fallback sources (P1) — Plan Phase A

**Goal**: Microphone and In-App Playback work on every device, labeled correctly.

**Independent Test**: quickstart.md Scenario A step 4 on every FR-032 device.

- [X] T042 [P] [US2] {A}{mac} Write `Packages/CaptureKit/Tests/CaptureKitTests/MicrophoneSourceTests.swift` with injected session/notification fakes: explainer shown before permission (FR-005); denied → `permissionDenied`; no input → `microphoneUnavailable`; interruption ended with "should resume" → auto-resume, else `interrupted`; background → `paused`, foreground → `waiting` within 2 s (FR-050); permission revoked while backgrounded → `permissionDenied` on foreground (FR-053) — AC: tests fail against a stub — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T043 [P] [US2] {A}{mac} Write `Packages/CaptureKit/Tests/CaptureKitTests/InAppPlaybackSourceTests.swift`: missing or undecodable track → `inAppPlaybackFailed`; output route lost → `paused` with `audioRouteChanged`; loops until stopped; stop ≤ 1 s; never opens an input (FR-069) — AC: tests fail against a stub — ✅ verified 2026-11-08 by `swift test` on Linux (Swift 6.4.2)
- [X] T044 [P] [US2] {A}{win} Create `scripts/generate_reference_audio.py`: a deterministic 60 s, 44.1 kHz stereo WAV with tones, sharp clicks at known times, and a beat pattern, written to `Apps/CaptureLab/Resources/reference.wav` plus `reference-clicks.json` (click timestamps, for SC-006) — AC: two runs produce byte-identical files
- [X] T045 [US2] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/Microphone/MicrophoneSource.swift` (AVAudioEngine input tap → PCMSink; permission at point of use; interruption and route handling per data-model.md lifecycle matrix) — AC: T042 passes {mac} — ✅ verified 2026-11-08: T042 passes on the macOS host and the iOS 27.2 and 26.5 simulators; `AVMicrophoneBackend` builds for iOS 27.2 devices. The input tap had the same `@MainActor` isolation pattern as the In-App Playback tap whose crash the new simulator UI tests exposed (Swift 6's runtime check traps when AVFAudio calls the tap off the main thread), so it was made `@Sendable` preemptively; no test exercises the microphone tap's audio path yet (the UI test ends at the permission prompt). Behavior pending device (T049)
- [X] T046 [US2] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackSource.swift` (`.playback` category, AVAudioPlayerNode looping the bundled track, mixer tap → PCMSink, route-loss pause) (FR-006) — AC: T043 passes {mac} — ✅ verified 2026-11-08: T043 passes on the macOS host and the iOS 27.2 and 26.5 simulators. The same `@MainActor` tap crash was found by the UI tests and fixed; In-App Playback then reaches Active audio in CaptureLab on both simulators (simulator only, not evidence). Behavior pending device (T049)
- [X] T047 [US2] {A}{win} Implement `Packages/CaptureKit/Sources/CaptureKit/LifecycleObserver.swift` (app background/foreground and protected-data/lock notifications → `LifecycleEvent`; permission re-check on foreground) — AC: T042/T043 lifecycle cases pass {mac} — ✅ verified 2026-11-08: the T042/T043 lifecycle cases pass (macOS host; iOS 27.2 and 26.5 simulators), and `LifecycleObserver` delivers background/foreground in the running app (UI test plus `scripts/check_capturelab_export.py`, both simulators). Lifecycle forwarding now lives in the app model, so it survives scene recreation. Lock/unlock pending device (T041)
- [X] T048 [US2] {A}{win} Add `Packages/CaptureUI/Sources/CaptureUI/MicrophoneExplainerView.swift` and the "Open Settings" banner action, using the exact ui-states strings, and use them from CaptureLab — AC: UI test shows the explainer before the system prompt {mac} — ✅ verified 2026-11-08: `CaptureLabUITests.testMicrophoneExplainerAppearsBeforeSystemPrompt` passes on the iOS 27.2 and 26.5 simulators: the explainer shows while no system alert exists, and after Continue the system prompt appears with the same text (FR-019)
- [ ] T049 [US2] {A}{device} Run US2 acceptance scenarios 1–7 on every FR-032 device; record them in `docs/test-reports/compatibility-report.md` — AC: all 7 scenarios pass on every device, and SC-004 (Active audio within 2 s) holds
- [ ] T050 [US2] {A}{device} Phase A real-time check (Constitution VII): run an allocation trace for 60 s on each Phase A adapter callback (System/App Capture, Microphone, In-App Playback) on the reference device before any Gate 1/2 run; record the results in `docs/test-reports/performance.md` — AC: zero heap allocations and zero lock acquisitions on each audio callback thread

**Checkpoint**: US1 and US2 both work independently.

---

## Phase 5: User Story 3 — Compatibility report and Stage 1 gate (P1) — Plan Phase A

**Goal**: Evidence-based compatibility report and the Stage 2 go/no-go decision.

**Independent Test**: quickstart.md Scenario A steps 5–9; the report is complete and reproducible.

- [ ] T051 [US3] {A}{device} For each FR-030 source on each applicable device, run 10 minutes in the foreground and export diagnostics into `docs/test-reports/exports/<device>/<source>/` — AC: SC-001 coverage (≥ 2 capture-capable iPhones + 1 iPad for capture sources; all devices for fallbacks)
- [ ] T052 [US3] {A}{win} Rate every row of `docs/test-reports/compatibility-report.md` Works / Partial / Does not work using the FR-031 thresholds, citing the exports; write the limitation for each Partial row — AC: zero "Works" rows without an export showing non-silent audio (SC-001)
- [ ] T053 [US3] {A}{device} Gate 2: for each source rated "Works", run a 30-minute foreground capture (results in `docs/test-reports/compatibility-report.md`) on the reference device and record unrecovered failures, dropped audio, start-to-first-audio, CPU, and memory against the Gate 2 thresholds in spec Delivery Gating — AC: each Works source passes or is downgraded to Partial with its reason
- [ ] T054 [US3] {A}{win} Finalize the Stage 1 thresholds (dBFS levels, timeouts, 200 ms cycle, Works thresholds) in the report; update FR-011/FR-012/FR-018/FR-031/FR-052 and the `ClassifierThresholds` defaults to match — AC: spec and code defaults are identical; `validate_docs.py` passes
- [ ] T055 [US3] {A}{win} Write the preliminary conclusions for RI-007 and RI-010 in `docs/adr/0005-lgpl-compliance.md` (relinking approach, upstream's App Store warning, vendored obligations) (FR-064) — AC: the conclusion section states go / no-go / conditional, with reasons — ⏳ draft analysis written in ADR-0005; preliminary conclusion awaits project-owner approval
- [ ] T056 [US3] {A}{win} The project owner records the Stage 2 go/no-go decision, approver, date, evidence, and claimable sources in the Stage Decision section of `docs/test-reports/compatibility-report.md` (FR-033) — AC: the decision is recorded; if "no external source works", the product description is updated to fallbacks only

**🚧 STAGE 1 GATE**: Nothing below this line may start until T056 records "go" and T055 is not
"no-go" (spec Stage 2 approval rule). This blocks all ProjectM engine, renderer, preset, and
visualizer work.

---

## Phase 6: Stage 2 Foundation — Plan Phase B (audio pipeline), then Plan Phase C (engine)

**Purpose**: Normalized audio pipeline, then the engine build and render proof (Gate 3). Blocks
US4–US7.

### Plan Phase B — Audio pipeline (starts after the Stage 1 gate)

- [ ] T057 [P] {B}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/NormalizerTests.swift`: mono → stereo duplication; 5.1 → stereo via the standard layout downmix; unknown layout → channels 1–2; int16/int32 → Float32; a 48 kHz 1 kHz sine resampled to 44.1 kHz keeps 1 kHz ± 1 Hz; a mid-stream format change does not stop the stream (FR-017); an unconvertible format → `error` — AC: tests fail against a stub
- [ ] T058 [P] {B}{mac} Write `Packages/AudioCore/Tests/AudioCoreTests/NormalizedReaderTests.swift`: capacity 22,050 stereo frames; freshness rule (backlog > 50 ms → skip to the newest 50 ms, counted as dropped); empty ring → `read` returns 0 (underrun policy) — AC: tests fail against a stub
- [ ] T059 {B}{win} Implement `Packages/AudioCore/Sources/AudioCore/Normalizer.swift` (AVAudioConverter on the work queue; output Float32 interleaved stereo at 44,100 Hz) — AC: T057 passes {mac}
- [ ] T060 {B}{win} Implement `Packages/AudioCore/Sources/AudioCore/NormalizedPCMReader.swift` (second SPSC ring plus the freshness rule) — AC: T058 passes {mac}
- [ ] T061 {B}{win} Wire the CaptureManager work queue → Normalizer → normalized ring, and expose `normalizedOutput` in `Packages/CaptureKit/Sources/CaptureKit/CaptureManager.swift` — AC: integration test with FakeAudioSource reads normalized frames {mac}
- [ ] T062 [P] {B}{win} Add latency signposts per stage (capture delivery, ring + conversion, normalized residency) in `Packages/Diagnostics/Sources/Diagnostics/Logging.swift` call sites — AC: an Instruments trace shows the three intervals {mac}
- [ ] T063 {B}{device} Run an allocation trace for 60 s per adapter on the reference device; record the results in `docs/test-reports/performance.md` — AC: zero heap allocations and zero lock acquisitions on the audio callback thread, and capture-plus-pipeline CPU (capture, classifier, normalizer) under 15% of one core during a 30-minute run (Plan Phase B exit)

**Checkpoint (Plan B exit)**: The project owner accepts Phase B evidence before Phase C starts.

### Plan Phase C — Engine build and render proof (Gate 3)

- [ ] T064 {C}{win} Verify the glm license text in `Vendor/projectM/vendor/glm` (or upstream at the pinned version) and update the ADR-0004 vendored table — AC: every vendored row says "Recorded"
- [ ] T065 {C}{mac} Implement `scripts/build_projectm_xcframework.py` (RI-011): CMake per slice (`CMAKE_SYSTEM_NAME=iOS`; iphoneos arm64; iphonesimulator arm64 + x86_64; `ENABLE_GLES=ON`; shared framework), `xcodebuild -create-xcframework` → `Build/ProjectM.xcframework`; record the final flags in ADR-0004 — AC: the script succeeds from a clean checkout
- [ ] T066 {C}{mac} Add the engine build to `.github/workflows/ios-ci.yml`, cached by submodule SHA — AC: CI produces the xcframework; a cache hit on rerun
- [ ] T067 {C}{win} Create `Packages/ProjectMBridge/Package.swift` (binary target `Build/ProjectM.xcframework`, ObjC++ target `ProjectMBridge`) — AC: package resolves {mac}
- [ ] T068 {C}{mac} Write `Packages/ProjectMBridge/Tests/ProjectMBridgeTests/PMEngineTests.swift`: a malformed preset returns `NSError` `presetLoadFailed` with no exception crossing; `maxSamplesPerFrame` > 0; create/destroy 100× without leaks — AC: tests fail against a stub
- [ ] T069 {C}{win} Implement `Packages/ProjectMBridge/Sources/ProjectMBridge/PMBridge.h` and `PMBridge.mm` per contracts/projectm-bridge.md (all C++ exceptions caught, render-thread assertion, destroy on the render thread, 1:1 C API mapping, no engine patches) — AC: T068 passes {mac}
- [ ] T070 [P] {C}{win} Create `Packages/Rendering/Package.swift` and `Sources/Rendering/VisualizerRenderer.swift` (protocol plus `RenderMetrics` per the contract; fps from presentation timestamps in 1 s windows) — AC: compiles {mac}
- [ ] T071 {C}{win} Implement `Packages/Rendering/Sources/Rendering/GLESRenderer.swift` (Option A: CAEAGLLayer ES 3.0 context; load_proc = static table of linked ES 3.0 functions, no `dlsym`; display link capped at 60 fps; drains the normalized reader up to `maxSamplesPerFrame` per frame) — AC: renders the upstream test preset in the simulator {mac}
- [ ] T072 {C}{device} RI-009: on a device, record whether the engine's `dlopen` path runs with a load_proc supplied and which names it tries; record this in ADR-0003; if needed, add a minimal iOS-only patch and log it in `docs/projectm-patches.md` — AC: the ADR-0003 RI-009 section is resolved
- [ ] T073 [P] {C}{win} Select ≥ 20 starter presets with verified redistribution rights into `Apps/ProjectMiOS/Resources/Presets/`, with `LICENSES.md` rows carrying all required fields (file path, display name, pack, author, license identifier, source URL, source version) — AC: no preset is bundled without every field (FR-047)
- [ ] T074 {C}{win} Implement `Packages/Rendering/Sources/Rendering/PresetRepository.swift` (enumerates bundled presets, joins them with LICENSES.md, excludes unlicensed files, sorts alphabetically by display name) — AC: unit test with fixture presets {mac}
- [ ] T075 {C}{device} Measure Option A against the ADR-0003 thresholds on every measurement device; record in `docs/test-reports/performance.md` — AC: all threshold rows filled with numbers
- [ ] T076 {C}{mac} Pin and build ANGLE (Metal backend) reproducibly into `Build/ANGLE.xcframework`; add its row to ADR-0004 with the license verified from the pinned source's LICENSE file (Constitution IX) — AC: CI builds it from the pinned source; the license row says "Recorded"
- [ ] T077 {C}{win} Implement `Packages/Rendering/Sources/Rendering/ANGLERenderer.swift` (Option B; EGL context; load_proc = `eglGetProcAddress`) — AC: renders the upstream test preset in the simulator {mac}
- [ ] T078 {C}{device} Measure Option B against the ADR-0003 thresholds on every measurement device; record in `docs/test-reports/performance.md` — AC: all threshold rows filled
- [ ] T079 {C}{win} Accept `docs/adr/0003-renderer.md`: choose the option, record the quality tiers (mesh size, render scale, device-to-tier rule), and select the engine tag or commit per RI-006 in ADR-0004 — AC: ADR-0003 status "Accepted"; **Gate 3 passed**

**Checkpoint (Gate 3)**: The engine renders on devices. US4–US7 may start.

---

## Phase 7: User Story 4 — Full-screen visualization (P2) — Plan Phase D

**Goal**: Full-screen visualization driven by the active source.

**Independent Test**: quickstart.md Scenario C rows SC-005, SC-006, FR-041 with In-App Playback.

- [ ] T080 [US4] {D}{win} Add target `ProjectMiOS` to `project.yml` (all packages including CaptureUI; embed `ProjectM.xcframework` and ANGLE if chosen; bundle `reference.wav` and `reference-clicks.json` from T044 for In-App Playback and SC-006; Info.plist keys from ui-states; no background modes or extra entitlements per R-16; empty `PrivacyInfo.xcprivacy` placeholder). The signing team and provisioning profiles are set by a human, never by automation (Constitution Security) — AC: app builds and launches {mac}
- [ ] T081 [US4] {D}{mac} Write `Apps/ProjectMiOS/UITests/VisualizerUITests.swift`: tap toggles controls; controls hide after 5 s while the compact indicator stays visible (FR-042); rotation re-layout ≤ 1 s with no capture restart; compact width shows the single-row layout (FR-087) — AC: tests fail before T084–T086
- [ ] T082 [US4] {D}{win} Implement `Apps/ProjectMiOS/ProjectMApp.swift` and `Coordinators/AppCoordinator.swift`: launch flow per FR-081 (notice on first launch → CaptureUI `SourceChooserView`, with `MicrophoneExplainerView` before the microphone prompt; no auto-start) — AC: UI test covers first and second launch and the explainer {mac}
- [ ] T083 [P] [US4] {D}{win} Implement `Apps/ProjectMiOS/Views/PhotosensitivityNoticeView.swift` (FR-071; acknowledgment persisted under `notice.photosensitivityAcknowledged`) — AC: shown once, before any visualization {mac}
- [ ] T084 [US4] {D}{win} Implement `Apps/ProjectMiOS/Views/VisualizerView.swift` (UIViewRepresentable hosting the renderer full-screen; portrait/landscape/split (FR-041); status bar and home indicator hidden with controls, unless that hides the capture/mic indicator per FR-086/FR-089) (FR-040) — AC: T081 rotation case passes {mac}; with the controls hidden during System/App Capture and Microphone, whether the screen-recording and microphone indicators stay visible is recorded on D1 and D2 (FR-089, quickstart Scenario C; moved here from the Stage 1 checks by the owner review 2026-11-08) {device}
- [ ] T085 [US4] {D}{win} Implement `Apps/ProjectMiOS/Views/ControlsOverlay.swift` (FR-082 contents, 5 s auto-hide, always-visible compact indicator (FR-042), compact layout with the preset browser as a sheet (FR-087)) — AC: T081 passes {mac}
- [ ] T086 [US4] {D}{win} Suppress device auto-lock while the visualization runs in the foreground and restore it on pause/stop/background (FR-084), in `Coordinators/AppCoordinator.swift` — AC: unit test of idle-timer state per visualization state {mac}
- [ ] T087 [US4] {D}{device} Run US4 acceptance 1–4 and SC-006 (240 fps camera, 20 clicks from `reference-clicks.json`, median < 150 ms) on the reference device; verify FR-084 by visualizing past the auto-lock interval — AC: all pass; results in performance.md

---

## Phase 8: User Story 5 — Presets and favorites (P2) — Plan Phase D

**Goal**: Browse, switch, randomize, and favorite presets.

**Independent Test**: quickstart.md Scenario C row SC-007 plus US5 scenarios.

- [ ] T088 [P] [US5] {D}{mac} Write `Apps/ProjectMiOS/Tests/PresetTests.swift`: favorites persist under `favorites` and `lastPresetID`; alphabetical order; random never returns the current preset (FR-088); empty-favorites text; a failed load keeps the previous preset (FR-045) — AC: tests fail against a stub
- [ ] T089 [US5] {D}{win} Implement `Apps/ProjectMiOS/Coordinators/FavoritesStore.swift` (only the FR-065 keys) — AC: T088 persistence cases pass {mac}
- [ ] T090 [US5] {D}{win} Implement `Apps/ProjectMiOS/Views/PresetBrowserView.swift` (FR-043/FR-044/FR-088; closes on selection; favorites filter and empty state) — AC: T088 UI cases pass {mac}
- [ ] T091 [US5] {D}{win} Wire Next/Previous/Random and the preset-failure banner ("Preset could not be loaded") in `Apps/ProjectMiOS/Coordinators/PresetCoordinator.swift`; blend ≤ 2 s — AC: T088 passes {mac}
- [ ] T092 [US5] {D}{device} Run US5 acceptance 1–4 and SC-007 (Next × 50: 95% of first frames within 1 s) on the reference device — AC: pass; recorded in `docs/test-reports/performance.md`

---

## Phase 9: User Story 6 — Source status and capture control (P2) — Plan Phase D

**Goal**: Truthful status, stop/pause/resume, and recovery.

**Independent Test**: quickstart.md Scenario C row SC-010 plus US6 scenarios.

- [ ] T093 [P] [US6] {D}{mac} Write `Apps/ProjectMiOS/UITests/StatusUITests.swift` with a fake source: every FR-010 state string and FR-015 message/action from ui-states; visualization pause does not change the audio state (FR-046); paused frame dimmed with "Paused" (FR-085); Ended by system → Restart re-presents the picker (FR-055) — AC: tests fail before T094–T096
- [ ] T094 [US6] {D}{win} Implement `Apps/ProjectMiOS/Views/SourceStatusIndicator.swift` (FR-013) and wire CaptureUI's `StatusBanner` for FR-015/FR-083 messages from the ui-states tables — AC: T093 string cases pass {mac}
- [ ] T095 [US6] {D}{win} Implement Stop / Pause / Resume and `VisualizationState` (running, paused, suspended) in `Apps/ProjectMiOS/Coordinators/AppCoordinator.swift` (FR-007, FR-046, FR-085) — AC: T093 passes {mac}
- [ ] T096 [US6] {D}{win} Implement one-tap restart per the data-model lifecycle matrix (System/App Capture re-presents the picker; mic/in-app restart directly) in `Coordinators/AppCoordinator.swift` (FR-055) — AC: T093 restart cases pass {mac}
- [ ] T097 [US6] {D}{device} Run US6 acceptance 1–4 on the reference device and an iPad, recorded in `docs/test-reports/release-report.md`; run SC-010 usability with ≥ 8 participants not involved in development (≥ 3 on iPad) — AC: all pass; ≥ 90% correct identification

---

## Phase 10: User Story 7 — Lifecycle and interruption resilience (P3) — Plan Phase D

**Goal**: Predictable behavior across background, lock, interruptions, route changes, and thermal pressure.

**Independent Test**: quickstart.md Scenario C row SC-009.

- [ ] T098 [P] [US7] {D}{mac} Write `Apps/ProjectMiOS/Tests/LifecycleCoordinatorTests.swift`: for each adapter, every row of the data-model lifecycle matrix (background/lock = FR-054, foreground auto-resume ≤ 2 s, interruption, route change) — AC: tests fail against a stub
- [ ] T099 [US7] {D}{win} Implement `Apps/ProjectMiOS/Coordinators/LifecycleCoordinator.swift` (suspend the visualization on background/lock; apply the per-adapter matrix; banners via ui-states) — AC: T098 passes {mac}
- [ ] T100 [US7] {D}{win} Implement thermal and low-power adaptation in `Packages/Rendering/Sources/Rendering/QualityGovernor.swift` (lower fps or render scale, never below 30 fps; labels and audio state unaffected, FR-049) — AC: unit test of each thermal state → settings {mac}
- [ ] T101 [US7] {D}{device} Run the US7 scripted sequence per source mode and SC-009 (50 cycles at 200 ms plus the lifecycle script) on the reference device (D1) and D3; record in `docs/test-reports/performance.md` — AC: zero crashes, correct final states
- [ ] T102 [US7] {D}{device} Gate 4: run SC-005, SC-008, SC-013, SC-014, and SC-015 on D1 (reference), D2, and D3; finalize the Stage 2 thresholds in `docs/test-reports/performance.md` and update the affected FR/SC lines — AC: all targets met or thresholds formally revised by the project owner; **Gate 4 passed**

---

## Phase 11: Polish & Cross-Cutting Concerns — Plan Phase E (release)

- [ ] T103 [P] {E}{win} Implement `Apps/ProjectMiOS/Views/SettingsView.swift`: performance overlay toggle (default off, FR-048), "Reduce flashing" (nil → follow Reduce Motion, FR-072), and the Licenses screen listing ADR-0004 components and LICENSES.md presets with license texts and the LGPL source/replacement note (FR-067) — AC: UI test covers all three {mac}
- [ ] T104 {E}{win} Implement the Reduce-flashing post-pass in the chosen renderer (`Packages/Rendering/Sources/Rendering/FlashLimiter.swift`) — AC: ≤ 2 ms per frame on the reference device {device}
- [ ] T105 [P] {E}{win} Add accessibility labels, state announcements, and Dynamic Type to all controls and the indicator in `Packages/CaptureUI/` and `Apps/ProjectMiOS/Views/` (FR-070) — AC: SC-012 screen-reader audit passes on iPhone and iPad {device}
- [ ] T106 [P] {E}{win} Fill `Apps/ProjectMiOS/PrivacyInfo.xcprivacy` with every required-reason API used and its approved reason (FR-066); draft the App Privacy answers as "Data Not Collected" in `docs/release/app-privacy.md` — AC: Xcode privacy report shows no undeclared APIs {mac}
- [ ] T107 [P] {E}{win} Write `docs/privacy-policy.md` covering every FR-063 point — AC: each FR-063 clause maps to a paragraph
- [ ] T108 {E}{device} SC-011 privacy review: inspect the app container after sessions (only FR-065 keys, no audio files) and run a proxy capture showing zero network connections (FR-068) (FR-060, FR-061) — AC: findings recorded in `docs/test-reports/privacy-review.md`, with zero violations
- [ ] T109 {E}{win} Write the final conclusion in `docs/adr/0005-lgpl-compliance.md` for RI-007 and RI-010 (FR-064) — AC: status "go"; otherwise the release is blocked
- [ ] T110 [P] {E}{win} Review the store listing and in-app help against the report's "Works" rows (FR-062: scoped by OS/device class/app version; no Partial claims; iPad only with an iPad "Works" row) in `docs/release/store-copy.md` — AC: every claim cites a report row
- [ ] T111 [P] {E}{win} Entitlements and Info.plist review against R-16 in `docs/release/entitlements-review.md` — AC: no capability beyond R-16
- [ ] T112 {E}{device} Full quickstart.md run (Scenarios A–D) on the release build; write `docs/test-reports/release-report.md`, including a check that only ProjectMiOS is submitted and CaptureLab is not (FR-090) — AC: every quickstart row passes or has an owner-approved waiver

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** → **Foundational (Phase 2)** → **US1 (3)** and **US2 (4)** → **US3 (5)** →
  **🚧 Stage 1 Gate (T056)** → **Plan B (T057–T063)** → **Plan C (T064–T079, Gate 3)** → **US4–US7
  (7–10)** → **Polish (11)**.
- Plan phases are strictly sequential (spec Delivery Gating): B starts only after T056; C only after
  the Plan B exit (T063 accepted); US4–US7 only after T079 (Gate 3).
- T035 (Gate 0) blocks T037; T010 blocks every `{mac}` build task; T017 (devices.md) blocks every `{device}` task; T014/T015 (compliance check) gate every merge.

### User Story Dependencies

- **US1, US2**: depend only on Foundational; they can proceed in parallel.
- **US3**: needs US1 and US2 working on devices (T040, T049), the Phase A real-time check (T050), the
  device checks (T113, required before Gate 1; owner review 2026-11-08), and the RI-003 lifecycle
  evidence (T041), which Gate 2 requires (owner ruling 2026-11-08).
- **US4**: needs Gate 3. **US5, US6**: need US4's app target (T080) and overlay (T085). **US7**:
  needs US4 and US6 (status banners).

### Within Each Story

Tests → model/types → source/coordinator → UI → device acceptance.

### Parallel Opportunities

- Setup: T002–T007 and T012–T013 in parallel.
- Foundational tests T018–T022 in parallel; implementations T023–T025 and T030, T032 in parallel.
- US1 and US2 in parallel after Phase 2 (different folders: `ScreenCapture/` vs `Microphone/`, `InAppPlayback/`).
- Plan B tests T057–T058 in parallel; T073 (presets) in parallel with T065–T071.
- US5 (T088–T091) and US6 (T093–T096) in parallel after T085.
- Polish: T103, T105–T107, T110, T111 in parallel.

## Parallel Example: User Story 2

```text
T042 MicrophoneSourceTests.swift      ‖  T043 InAppPlaybackSourceTests.swift  ‖  T044 generate_reference_audio.py
then: T045 MicrophoneSource.swift      ‖  T046 InAppPlaybackSource.swift
then: T047 LifecycleObserver.swift → T048 explainer UI → T049 {device} acceptance
```

## Implementation Strategy

### MVP First (User Story 1)

1. Phases 1–2, then Phase 3 (US1): CaptureLab proves or disproves external-app capture on a device.
2. **Stop and validate**: T040/T041 evidence answers the central product risk.

### Incremental Delivery

1. US2 adds the fallbacks, so the product is viable even if US1 fails.
2. US3 produces the report and the Stage 2 decision (**the gate**).
3. Plan B → Plan C (Gate 3) → US4 → US5/US6 → US7 (Gate 4) → Polish → release.

### Host Split

- Windows agents: all `{win}` tasks (docs, scripts, Swift/ObjC++ source authoring), reporting
  `{mac}` verification as pending.
- macOS: every `{mac}` task and the CI.
- Device owner: every `{device}` task, with exports and reports committed as evidence.
