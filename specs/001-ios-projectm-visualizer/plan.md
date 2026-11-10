# Implementation Plan: ProjectM-iOS Visualizer

**Branch**: `001-ios-projectm-visualizer` | **Date**: 2026-11-07 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-ios-projectm-visualizer/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

ProjectM-iOS is an iPhone and iPad app that visualizes audio with the ProjectM engine. Audio
comes from three explicitly labeled sources: System/App Capture (ScreenCaptureKit, only on OS
versions that provide it), Microphone, and In-App Playback. Delivery is gated. Phase A builds a
standalone **CaptureLab** feasibility app and the physical-device compatibility report. Phases B–E
(audio pipeline → ProjectM render proof → integrated visualizer → hardening) start only after the
Stage 2 approval rule in the spec is met.

Key technical findings from inspecting the pinned engine (`Vendor/projectM` @ `eae22de`):

- The engine's shaders target GLSL `#version 300 es` (OpenGL ES 3.0). Its build docs list ES 3.2,
  but the shader code does not appear to need it. On iOS, ES 3.0 is available (deprecated)
  through Apple's OpenGL ES, or through ANGLE's Metal backend.
- The C API `projectm_create_with_opengl_load_proc` lets the host supply GL function pointers.
  The iOS app can therefore provide its own GL ES context (Apple EAGL or ANGLE/EGL) without
  patching the engine's desktop-oriented GL resolver.
- PCM input is `projectm_pcm_add_float(handle, samples, count, channels)` with interleaved LR
  float in [-1, 1]. It takes no sample-rate parameter, so the pipeline resamples to 44.1 kHz.
- The license is LGPL-2.1, so the App Store compliance review (FR-064, RI-007) shapes the
  build: the engine ships as a separately replaceable dynamic framework (ADR-0004).

## Technical Context

**Language/Version**: Swift 6 (strict concurrency) for app, UI, and platform code. C++17 for the
engine and portable DSP. Objective-C++ only in the bridge. The exact Xcode/SDK version is pinned at
Gate 0 (R-01).

**Primary Dependencies**: Apple frameworks: SwiftUI, ScreenCaptureKit (System/App Capture, iOS
27.0+, device SDK only: the Simulator SDK has no ScreenCaptureKit), AVFAudio/AVAudioEngine (Microphone, In-App Playback), Accelerate/vDSP (conversion,
levels), Synchronization (atomics). Third-party: libprojectM (LGPL-2.1, pinned submodule) and the
renderer GL ES provider chosen in ADR-0003 (Apple OpenGL ES 3.0 for the Stage A prototype; ANGLE
Metal backend evaluated for production). Build tools: CMake (engine), XcodeGen (project
generation from text, version pinned).

**Storage**: On-device `UserDefaults` only: favorites, last preset, settings, and the
photosensitivity notice acknowledgment (FR-065). No audio storage anywhere.

**Testing**: XCTest/Swift Testing. Pure-logic packages run with `swift test` on a macOS host;
app targets are tested with `xcodebuild test` on the iOS Simulator. Physical-device test matrix per
FR-032 and the [quickstart](quickstart.md). Capture, lifecycle, and rendering acceptance happen on
devices only (Constitution X).

**Target Platform**: iOS/iPadOS 26.0+ (iPhone and iPad device family). System/App Capture is availability-gated to the
first OS that provides it: iOS 27.0 (RI-004, confirmed 2026-11-08 from the iOS 27.2 SDK annotations).

**Project Type**: Mobile app: two app targets (CaptureLab, projectM-iOS) sharing local Swift
packages.

**Performance Goals**: ≥55 fps on the reference device for 95% of a 10-minute session, capped at
60 fps on 120 Hz displays (SC-005). Audio-to-visual delay under 150 ms (SC-006). Preset first frame
within 1 s (SC-007). Peak memory under 300 MB (SC-008). Battery at most 20% per hour (SC-014). Cold
launch under 2 s / 4 s (SC-015). State classification latency of 2 s or less (SC-003).

**Constraints**: Real-time callbacks are allocation-free and lock-free (Constitution VII). Two
bounded ring buffers with drop-oldest overflow (R-06). No audio leaves memory (FR-060). Public APIs
only. Memory drift at most 10% between minutes 5 and 30 (SC-008).

**Latency budget** (sums to the SC-006 150 ms target; research R-06): capture delivery ≤ 30 ms →
source ring and conversion ≤ 20 ms → normalized ring residency ≤ 50 ms → engine frame and display ≤
50 ms (about 3 frames at 60 Hz).

**Entitlements**: Minimal, per research R-16: none (the Screen Recording entitlement of ADR-0001
Decision 6 was removed on 2026-11-09, ruling 16); no App Groups, network, push, or iCloud; the only background
mode is `screen-capture` (ADR-0001 ruling 17).

**Scale/Scope**: Single user, on device. About 8 screens/sheets (source chooser, visualizer,
controls overlay, preset browser, settings, diagnostics, photosensitivity notice, error states).
Starter preset set size depends on licensing (R-09).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | How this plan complies |
|-----------|--------|------------------------|
| I. Public Apple APIs only | PASS | ScreenCaptureKit, AVFAudio, SwiftUI, Accelerate; no private frameworks or `dlsym` of private symbols. The GL load_proc resolves only public GL ES / EGL entry points. |
| II. Capture feasibility first | PASS | Phase A (CaptureLab plus report) is a hard dependency. Phases B–E are blocked by the spec's Stage 2 approval rule. |
| III. ScreenCaptureKit preferred | PASS | ADR-0001: ScreenCaptureKit is the only System/App Capture adapter. No ReplayKit, and no broadcast extension (FR-009). In-process stream. |
| IV. Truthful labeling | PASS | `AudioStateClassifier` contract (contracts/audio-source.md) implements FR-010/FR-011. The UI reads only classifier states. |
| V. No universal-capture claims | PASS | Claims come only from report "Works" rows (FR-062). Store copy is reviewed in Phase E. |
| VI. Modular boundaries | PASS | Packages: AudioCore ← CaptureKit ← CaptureUI, ProjectMBridge ← Rendering, App. Enforced in CI by `scripts/check_compliance.py`. The engine sees only normalized PCM frames. |
| VII. Real-time safety | PASS | Preallocated SPSC ring buffer with atomics, no allocation or locks in callbacks, conversion on a dedicated audio work queue (research R-06). |
| VIII. Upstream fidelity | PASS | Submodule pinned to the owner's fork, branch `ios`: upstream `eae22de` plus four logged patches (iOS framework bundles, T065; EAGL context accepted by the GL resolver, T069; the app's load proc authoritative on iOS, RI-009/T072; the owner's include and playlist-header fixes), to be proposed upstream (Constitution v1.1.0, 2026-11-09). Every patch is in `docs/projectm-patches.md`. |
| IX. Pinned deps and licenses | CONDITIONAL | Pins and vendored-component licenses are recorded in ADR-0004. The LGPL and App Store conclusions (RI-007, RI-010; ADR-0005) are pending; the preliminary conclusions are Stage 2 entry conditions. Preset and audio licensing is pending (R-09). |
| X. Evidence-based quality | PASS | ADR-0001 and ADR-0002 accepted (owner review 2026-11-08); ADR-0003 to ADR-0005 status in `docs/adr/README.md`. Device matrix, performance, and privacy reviews are scheduled per phase. |
| Platform: macOS required | PASS | Windows/macOS split below. Agents on Windows report builds as "pending macOS". |

**Result**: Gate passes. Principle IX is conditional: it does not block Phase A, but it blocks
Stage 2 entry until RI-007 has a preliminary conclusion.

*Post-design re-check (after Phase 1 artifacts)*: No new violations. The contracts keep capture
types out of the bridge, and the diagnostics export schema excludes identifiers (FR-021). IX
remains conditional. **PASS.**

## Delivery Phases

| Plan phase | Spec stage / constitution phase | Exit gate | Hard dependency |
|------------|---------------------------------|-----------|-----------------|
| **A. Platform research and capture POC** | Stage 1 / Phase 0 | Gates 0–2; compatibility report; Stage 2 decision | none |
| **B. Audio pipeline** | Stage 2 / Phase 1 | Unit tests for FR-011, FR-016, FR-017, ring buffers; zero heap allocations on the audio thread in a 60 s allocation-trace run | A approved, RI-007 and RI-010 preliminary |
| **C. ProjectM build and render proof** | Stage 2 / Phase 2 | Gate 3: ADR-0003 thresholds met; ADR-0003 accepted; RI-009 and RI-011 closed | B accepted |
| **D. Integrated visualizer** | Stage 2 / Phase 3 | Gate 4: end-to-end per source; SC-005–SC-010, SC-013 | C accepted |
| **E. Production hardening** | Release / Phase 4 | FR-064 final, FR-066, FR-067, SC-011, SC-012, store review | D accepted |

Phases run strictly in sequence, A → B → C → D → E. Each phase starts only after the previous
phase's exit evidence is reviewed and approved by the project owner (constitution workflow; spec
Gate criteria table). Gate 3 (render proof) is therefore reached in Phase C, after Phase B's audio
pipeline is accepted.

**Phase A scope (CaptureLab)**: source chooser (US1/US2), ScreenCaptureKit adapter, Microphone
adapter, In-App Playback adapter, live diagnostics (FR-020), audio-state classifier, export
(FR-021), lifecycle observation (to collect RI-003 evidence), the report template in
`docs/test-reports/`, and the platform research notes in `docs/platform-research/`.

## Windows / macOS Division of Responsibilities

| Work | Windows 11 workstation | macOS (Mac or GitHub Actions `macos-*`) | Physical device |
|------|------------------------|-----------------------------------------|-----------------|
| Specs, ADRs, docs, Python scripts | ✅ | ✅ | — |
| Swift/C++ source editing | ✅ (no compile) | ✅ | — |
| `project.yml` (XcodeGen) edits | ✅ | ✅ generates `.xcodeproj` | — |
| Build engine dynamic xcframework (CMake) | ❌ | ✅ | — |
| `swift test` on packages | ❌ (not claimed) | ✅ | — |
| Simulator build and test | ❌ | ✅ | — |
| Signing, provisioning | ❌ | ✅ human only | — |
| Capture, lifecycle, render, performance acceptance | ❌ | — | ✅ |

The `.xcodeproj` is generated, not committed, so Windows edits never conflict with Xcode project
files.

## Project Structure

### Documentation (this feature)

```text
specs/001-ios-projectm-visualizer/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── audio-source.md
│   ├── projectm-bridge.md
│   ├── ui-states.md
│   └── diagnostics-export.schema.json
├── checklists/
└── tasks.md             # Phase 2 output (/speckit-tasks)

docs/
├── adr/                 # ADR-0001 … ADR-0004 (this plan), later ADRs
├── platform-research/   # RI-001/RI-003/RI-004 inventories
├── test-reports/        # compatibility report + device runs
└── projectm-patches.md  # engine patch log (fork branch `ios`; Constitution VIII)
```

### Source Code (repository root)

```text
project.yml                     # XcodeGen spec → ProjectM-iOS.xcodeproj (generated, gitignored)
Apps/
├── CaptureLab/                 # Phase A feasibility app (Stage 1)
│   ├── CaptureLabApp.swift
│   ├── Views/                  # SourceChooser, DiagnosticsView, ExportView
│   └── Resources/              # Info.plist keys, reference audio
└── projectM-iOS/                # Stage 2 app
    ├── ProjectMApp.swift
    ├── Coordinators/           # AppCoordinator, LifecycleCoordinator
    ├── Views/                  # Visualizer, Controls, PresetBrowser, Settings, Notice
    └── Resources/              # presets (licensed), reference audio
Packages/
├── AudioCore/                  # pure Swift, no UIKit: PCMFormat, AudioFrame, RingBuffer,
│   │                           # Normalizer (downmix/resample), LevelMeter, AudioStateClassifier
│   └── Tests/AudioCoreTests/
├── CaptureKit/                 # AudioSource protocol, CaptureManager, adapters:
│   │                           # ScreenCaptureSource, MicrophoneSource, InAppPlaybackSource
│   └── Tests/CaptureKitTests/  # with fake sources
├── CaptureUI/                  # SwiftUI views shared by both apps: SourceChooserView,
│   │                           # MicrophoneExplainerView, StatusBanner (ui-states strings)
├── Diagnostics/                # DiagnosticsSnapshot, exporter (schema-validated), signposts
│   └── Tests/
├── ProjectMBridge/             # ObjC++ target: PMBridge.h/.mm; links ProjectM.xcframework
│   └── Tests/
└── Rendering/                  # VisualizerRenderer protocol, GLESRenderer (Stage A backend),
    └── Tests/                  # MetalRenderer spike lives on a branch until ADR-0003 decides
Vendor/
└── projectM/                   # pinned submodule (unmodified)
scripts/
├── build_projectm_xcframework.py   # CMake → dynamic ProjectM.xcframework (device + simulator)
├── verify_environment.py
└── validate_docs.py
Build/                          # generated xcframeworks (gitignored)
.github/workflows/ios-ci.yml    # macOS runner: swift test, engine build, simulator build/test
```

**Mapping to the README architecture (§4)**:

| README component | Plan location |
|------------------|---------------|
| App: ProjectMApp, AppCoordinator, ContentView, VisualizerScreen, CaptureControls, SourceStatusView | `Apps/projectM-iOS` (Coordinators/, Views/); the shared chooser, explainer, and banner are in `Packages/CaptureUI` |
| Capture: AudioSourceProtocol, AudioCaptureManager, adapters | `Packages/CaptureKit` (`AudioSource`, `CaptureManager`, three adapters) |
| Capture: ReplayKitAudioSource | Excluded (FR-009, ADR-0001) |
| Audio: PCMFormat, PCMBuffer, AudioNormalizer, AudioRingBuffer | `Packages/AudioCore` |
| Audio: AudioAnalyzer, FFTProcessor, FrequencyBandAnalyzer, BeatDetector | Excluded: the engine does its own spectrum and beat analysis (README §5.1). AudioCore keeps only peak/RMS for the classifier. Revisit only with a measured need. |
| ProjectM: ProjectMBridge.h/.mm, ProjectMEngine | `Packages/ProjectMBridge` (`PMEngine`) |
| ProjectM: PresetRepository, PresetMetadata | `Packages/Rendering` (`PresetRepository`: enumerates bundled presets and joins them with `Presets/LICENSES.md`) |
| Rendering: VisualizerRenderer, OpenGLESPrototypeRenderer, MetalRenderer, Shaders | `Packages/Rendering` (`VisualizerRenderer`, `GLESRenderer`, `ANGLERenderer` per ADR-0003) |
| Shared: Diagnostics, Logging | `Packages/Diagnostics` (snapshots, exporter, `os_signpost`/`Logger` wrappers) |
| Shared: AppConfiguration, Permissions | `Packages/CaptureKit` (permission requests live with the adapter that needs them) and `Apps/*/` (settings) |
| Tests | Each package's `Tests/` plus app UI tests |

**Why not the README's `Sources/` layout**: the README lets the plan choose the layout and asks for
the reason. Local Swift packages make the module boundaries (Constitution VI) compiler-enforced,
let pure-logic packages run `swift test` without a simulator, and let CaptureLab exclude the engine
entirely.

**Structure Decision**: Two app targets share six local Swift packages. This keeps the
constitution's module boundaries enforceable by the compiler. CaptureLab depends only on AudioCore,
CaptureKit, CaptureUI, and Diagnostics, so Phase A cannot accidentally depend on the engine.
projectM-iOS adds ProjectMBridge and Rendering. CaptureUI holds the source chooser, microphone
explainer, and status banner so both apps show identical, contract-defined UI.
`scripts/check_compliance.py` enforces the constitution's API and boundary rules on every merge.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Two app targets (CaptureLab + projectM-iOS) | Phase A must ship and be tested before the visualizer exists; it also stays useful as the diagnostics tool for the report. | One app with a debug screen would couple Stage 1 evidence to Stage 2 code and the engine. |
| Engine as a dynamic framework | LGPL-2.1 relinking obligations (RI-007) are easier to meet with a separately replaceable library. | Static linking requires shipping relinkable object files; it is still an option if ADR-0004/RI-007 conclude it is acceptable. |
