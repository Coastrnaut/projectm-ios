# Implementation Plan: QA-007 Audio source contract suite

**Branch**: `feature/qa-007` | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/013-qa-007-audio-source-contract-suite/spec.md`

## Summary

1. **Contract**: [contracts/source-contract.md](contracts/source-contract.md) writes down the
   invariants QA-007-R1 to R14 that every audio source keeps, the allowed transition graph (from
   spec 001's data model) and the per-source parameters with their citations. It extends, and does
   not replace, `specs/001-ios-projectm-visualizer/contracts/audio-source.md`.
2. **Conformance fakes** (test target only): one scripted fake per platform seam —
   `StreamDriver` (System/App Capture), `MicrophoneBackend`, `InAppPlaybackBackend` — that records
   every call in a shared order log, keeps the sink only while its session is live, writes silent
   or non-silent samples on request, emits events through the live session's callback, can emit a
   late event through a callback kept after stop, and can deny or fail the next start.
3. **Conformance harness**: a value describing one source configuration (5 of them: System/App
   Capture, Microphone, In-App Playback with the reference track, an imported file and a test
   signal), its fake, its real adapter and its per-source parameters; plus a rig with the real
   `CaptureManager` (manual analysis, `ManualClock`) over all three sources.
4. **Suite**: `AudioSourceContractTests` (XCTest, `@MainActor`): one test per invariant; each test
   loops over every configuration (and, for the switch invariant, over every ordered pair of
   modes) and names the configuration in every failure message.
5. **Fixes**: any violation found is fixed in `Packages/CaptureKit/Sources/CaptureKit/` with the
   smallest change, recorded in the spec's "Defects found by the suite".

## Technical Context

**Language/Version**: Swift 6.4.2 (strict concurrency, Swift 6 language mode), Xcode 27.2

**Primary Dependencies**: CaptureKit and AudioCore only. No new dependency, no AVFAudio in the suite.

**Storage**: none. The suite persists nothing; nothing in the app changes what it stores.

**Testing**: XCTest. `swift test --package-path Packages/CaptureKit` on the macOS host (5
consecutive runs at the end); `xcodebuild test` of the CaptureKit package on the iOS 27.2
simulator; CaptureUI package tests and, if production code changes, the app's unit tests and the
`InterruptionUITests`, `TransportUITests`, `StatusUITests` UI tests. CI also runs the suite on
Linux (it uses no AVFAudio).

**Target Platform**: iOS/iPadOS 26.0 and later (ADR-0002); macOS and Linux hosts for package tests

**Project Type**: mobile app with SwiftPM packages (test infrastructure in `CaptureKit`)

**Performance Goals**: the whole suite under 10 s on the Mac host (QA-007-S3)

**Constraints**: deterministic — main actor only, injected clock, manual analysis steps, waits on
conditions (never fixed sleeps for synchronization), marker events as barriers; no thread
scheduling assumptions; no physical device before the final stage.

**Scale/Scope**: 14 invariants × 5 configurations, plus 6 ordered switch pairs and 3 self-restarts.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Tests and any fix use CaptureKit types only; `check_compliance.py` runs | Pass |
| III/IV Truthful labeling | R6 and R13 check "Active audio" only after verified non-silent samples of the current session and the mode label per source | Pass (this feature strengthens it) |
| VI Modular boundaries | Fakes replace only the existing seams; no platform type crosses the boundary | Pass |
| VII Real-time safety | R2, R3, R4, R14 check idempotent start/stop and no callbacks into released objects; no real-time path changes unless a defect requires it | Pass |
| X Evidence-based quality | Unit tests for deterministic logic; device behavior of the real backends stays a `{device}` check (QA-011); simulator results are not device evidence | Pass |
| Tests not weakened | No existing test is changed, disabled or skipped; per-source differences are parameters, never skips | Pass |
| Privacy | Nothing stored, no network, no new entitlement | Pass |

Post-design re-check (after Phase 1): unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/013-qa-007-audio-source-contract-suite/
├── spec.md
├── plan.md
├── research.md          # audit matrix and decisions
├── data-model.md        # harness, parameters, transition graph
├── quickstart.md        # how to run and read the suite
├── contracts/
│   └── source-contract.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/CaptureKit/
├── Sources/CaptureKit/                       # production; changed only to fix defects found
│   ├── Microphone/MicrophoneSource.swift
│   ├── ScreenCapture/ScreenCaptureSource.swift
│   └── InAppPlayback/InAppPlaybackSource.swift
└── Tests/CaptureKitTests/
    ├── ContractFakes.swift                   # new: conformance fakes for the three seams
    ├── SourceConformance.swift               # new: configurations, parameters, rig, waits
    └── AudioSourceContractTests.swift        # new: the parameterized suite (R1 to R14)
```

**Structure Decision**: Everything lives in the existing CaptureKit test target, next to the
existing source tests; no new package, target, scheme, `project.yml` or CI change is needed
(`swift test` and the existing CI jobs pick the new files up). The existing fakes in
`SourceAdapterTests.swift` are left unchanged, because other suites depend on their exact
behavior; the conformance fakes are new types with a common harness interface.

### Rollback

The feature adds three test files and, at most, small guarded changes in three adapters. Reverting
the feature's commits restores the previous state completely; nothing is persisted or migrated.

## Complexity Tracking

No constitution violations to justify.
