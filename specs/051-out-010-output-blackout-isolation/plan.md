# Implementation Plan: OUT-010 Output Blackout Isolation

**Branch**: `feature/out-010` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/051-out-010-output-blackout-isolation/spec.md`

## Summary

Every `VisualSlotView` (OUT-001) gets an opaque black cover layer above the visual, kept at
opacity 0 while live. `OutputBlackout`, a pure value in `PresentationLifecycle`, holds the state
machine (live, blacked out, restore waiting, fading in), the restore fade and the restore spacing,
driven only by frame times (research OUT-010-D2, D3). `ExternalDisplayCoordinator` owns it: Black
out sets every slot's cover to opacity 1 inside the tap's call with implicit animations disabled,
so the change is part of the current Core Animation transaction and the next composited frame is
black (OUT-010-D1). Restore runs a `CADisplayLink` only while the fade or the spacing needs frames,
advancing the model by the link's frame time and setting the cover's opacity so that a white
picture's luminance rises linearly. The visual stays in its slot and keeps running (spec
Clarifications), the audio source is never touched, and `place()` applies the cover before it
moves the visual, so a connect, disconnect or visual change never reveals the picture. The device
shows a persistent "Output blacked out" badge with Restore, a Black out control in the controls,
and the note "External display blacked out" while the visualization is external. ADR-0023 is
amended (decision 8).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI).

**Primary Dependencies**: UIKit (`CALayer`, `CATransaction`, `CADisplayLink`), SwiftUI, the
OUT-001 coordinator and slots; `FlashSafety` (test-only: `FlashAnalysis` measures the fade's
transitions). No new package dependency; `PresentationLifecycle` gains a test-only dependency on
`FlashSafety` (pure Swift, Linux-safe).

**Storage**: none (session state only; FR-065).

**Testing**: `swift test --package-path Packages/PresentationLifecycle` (state machine, one-frame
rule with a fake frame clock, fade and toggling measured with `FlashAnalysis` on a white picture);
app unit tests (`OutputBlackoutCoordinatorTests`: real slot views, cover opaque inside the call,
no animation keys, connect/disconnect/visual change/visualizer re-entry while blacked out, frame
advance, the compositing check of a half-opaque cover); one UI test with the DEBUG fake external
display (`OutputBlackoutUITests`); a headless `simctl io … screenConfig` + `screenshot --display
external` check recorded in quickstart.

**Target Platform**: iOS/iPadOS 26+.

**Project Type**: mobile app plus one package addition.

**Performance Goals**: blackout applied inside the tap's handling (O(slots) property sets); no
per-frame allocation in the fade; the display link runs only during a fade or the restore spacing
(at most 1 s + 4 s).

**Constraints**: public APIs only; explicit closure types; no main-actor mutation in
setUp/tearDown; no wall-clock assertions; owner rule 7 budgets; never the Simulator panel tool.

**Scale/Scope**: about 250 lines of source and 350 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | `CALayer`, `CATransaction`, `CADisplayLink`, SwiftUI | Pass |
| IV/V. Truthful labeling, no universal claims | No compatibility claim; physical displays are `{device}` tasks | Pass |
| VI. Modular boundaries | Rules in `PresentationLifecycle` (pure Swift); UIKit glue in the app | Pass |
| VII. Real-time audio safety | No audio-path change; the source is never touched | Pass |
| VIII. Upstream fidelity | projectM and ANGLE untouched | Pass |
| X. Evidence | Host, Linux, simulator tests; simulator never device evidence; S5 left to the owner | Pass |
| Privacy / local-first | Nothing stored, no network | Pass |
| Flash safety (ADR-0011) | Blackout only darkens; restore fade within the envelope's limits for a white picture; residual recorded in ADR-0023 decision 8 | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/051-out-010-output-blackout-isolation/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/output-blackout.md
└── checklists/requirements.md
docs/adr/0023-external-display-scene.md          # amended: decision 8 (blackout)
```

### Source Code (repository root)

```text
Packages/PresentationLifecycle/Package.swift                                         # test dependency on FlashSafety
Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputBlackout.swift    # NEW: state machine, fade, spacing
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputBlackoutTests.swift
Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift          # + cover layer
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift   # + blackout, covers, frame driver
Apps/projectM-iOS/Coordinators/AppCoordinator.swift             # Reduce flashing to the coordinator
Apps/projectM-iOS/Views/ControlsOverlay.swift                   # + Black out / Restore output
Apps/projectM-iOS/Views/VisualizerView.swift                    # badge, note, DEBUG probe
Apps/projectM-iOS/Tests/OutputBlackoutCoordinatorTests.swift
Apps/projectM-iOS/UITests/OutputBlackoutUITests.swift
```

**Structure Decision**: as OUT-001: rules in the package (testable on Linux), glue in the app.

## Complexity Tracking

None: no constitution violation.
