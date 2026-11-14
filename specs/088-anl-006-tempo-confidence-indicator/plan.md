# Implementation Plan: ANL-006 Tempo Confidence Indicator

**Branch**: `feature/anl-006` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/088-anl-006-tempo-confidence-indicator/spec.md`

## Summary

A small deterministic state machine (`TempoConfidenceIndicator`) next to SHOW-011's `TempoSource`
in `Packages/PerformanceControl`, fed the same analysis estimate plus a monotonic time on every poll.
It classifies the tempo as searching, uncertain or stable with hysteresis (enter 0.7 / exit 0.5)
and dwell times (2 s / 1 s). A pure `TempoReadout` value combines it with the manual tempo for the
UI. The app's `TempoCoordinator` owns one indicator, and `TempoControls` shows the state word, the
"≈" prefix and the accessibility value. `TempoSnapshot` and every consumer are unchanged.

1. **Package `Packages/PerformanceControl`**, target `PerformanceControl` (pure Swift, Linux):
   - `TempoConfidenceIndicator.swift`: `TempoConfidenceState`, `TempoConfidenceRules` (`.standard`),
     `TempoConfidenceIndicator` (`update(_:at:)`, `reset()`, `state`, `bpm`, `confidence`,
     `stateChanges`), `TempoReadout` (`manual`, `stable`, `uncertain`, `searching`, each with the
     BPM to show; built from a `TempoSnapshot` and an indicator). Contract C1.
   - Tests: `TempoConfidenceIndicatorTests.swift` (scripted estimates on an injected clock:
     dwell, hysteresis, dips, tempo change, drift, no flicker, invalid input, backwards time, the
     readout mapping) and `TempoConfidenceAcceptanceTests.swift` (synthetic PCM through the real
     ANL-016 pipeline with a step clock: white and pink noise and silence never stable; 120 and
     90 BPM pulses stable; 120 → 90 change).
2. **App** (`Apps/projectM-iOS`):
   - `TempoCoordinator`: owns `TempoConfidenceIndicator`; an injected `stateClock` (default the
     monotonic clock; separate from the tap clock, which the DEBUG tap fake steps per reading);
     `updateEstimate` updates both; `readout: TempoReadout` (observed); text functions take a
     `TempoReadout`: `readoutText`, `stateText`, `accessibilityValue`; `tapValue` and
     `resetAnnouncement` use them. Stopping the analysis resets the indicator. DEBUG
     `-uitestTempoEstimate <bpm>:<confidence>[:<polls>:<confidence2>]` replaces the reader's poll
     result with a fixed (or two-phase) estimate.
   - `TempoControls`: the readout's two lines and accessibility value from `TempoReadout`
     (strings built in typed steps, no ternary `+` chains in modifiers).
   - `AppCoordinator`: reads the DEBUG launch argument and hands it to the coordinator (a few
     lines next to `-uitestTapInterval`).
   - Tests: `TempoCoordinatorTests` updated for the new words and an injected state clock; new
     `TempoReadoutTextTests` cases inside it (text, word and value per state). UI test
     `TempoConfidenceUITests.swift`: the fake reaches "stable", then "uncertain".
   - `TapTempoUITests`: the post-reset expectation accepts the new words.
3. **Docs**: SHOW-011's contract gets a note that the readout words moved to ANL-006 (the snapshot
   is unchanged). ACC-004's audit filter for "—" stays valid (searching keeps the em dash).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency), Xcode 27.2; CI also builds with
Xcode 26 and Linux Swift.

**Primary Dependencies**: existing PerformanceControl, PerformanceControlAnalysis, AnalysisFeatures,
AudioCore (tests: `ToneGenerator` pulses, `NormalizedPCMRing`, `AnalysisPipeline.step()`); SwiftUI
in the app. No new dependency.

**Storage**: none (FR-065 unchanged).

**Testing**: XCTest; `swift test --package-path Packages/PerformanceControl` on the host and in the
Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE`; PerformanceControl has no flag of its own and
compiles OSCTransport out only where Network is missing); app unit and UI tests on a dedicated
iOS 27.2 simulator "ANL6 iPhone 17" (created and deleted for this row).

**Target Platform**: iOS/iPadOS 26.0+; packages also macOS 15 and Linux.

**Performance Goals**: a handful of comparisons per 250 ms poll on the main actor; no allocation.

**Constraints**: owner rule 7 budgets (unit ≈1–2 s, suite < 1 min, UI test < 30 s); explicit
closure types and typed arithmetic steps; no C stdio globals; no main-actor mutation in
setUp/tearDown; no wall-clock assertions (times injected); no Simulator panel tool (rule 8).

**Scale/Scope**: one indicator per app; five noise/silence inputs and three pulse inputs of ≤ 24 s
of audio in tests (the existing 6 s end-to-end test runs in ≈ 0.3 s, so ≈ 2–3 s in total).

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: Swift and SwiftUI only. |
| VI. Modular boundaries | Pass: the indicator lives with the tempo source in PerformanceControl; the app only shows it. |
| VII. Real-time audio safety | Pass: nothing runs on the audio callback; updates happen on the 250 ms main-actor poll. |
| VIII. Upstream projectM fidelity | Pass: nothing reaches projectM; no new analysis (it reads ANL-005's confidence). |
| X. Evidence-based quality | Pass: acceptance by deterministic tests with synthetic PCM through the real pipeline and an injected clock; simulator UI test for the readout only. |
| Privacy (FR-065) | Unchanged: no stored data. |
| ACC-001 MotionPolicy | No animation added (`check_motion_policy.py` must still pass). |

Post-design re-check: unchanged, all pass. No ADR needed: no constitution default is overridden;
the decisions are recorded in the spec's Clarifications and in research.md.

## Project Structure

```text
specs/088-anl-006-tempo-confidence-indicator/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/tempo-confidence.md
└── checklists/requirements.md
Packages/PerformanceControl/Sources/PerformanceControl/TempoConfidenceIndicator.swift
Packages/PerformanceControl/Tests/PerformanceControlTests/TempoConfidenceIndicatorTests.swift
Packages/PerformanceControl/Tests/PerformanceControlTests/TempoConfidenceAcceptanceTests.swift
Apps/projectM-iOS/Coordinators/TempoCoordinator.swift, AppCoordinator.swift (DEBUG argument)
Apps/projectM-iOS/Views/TempoControls.swift
Apps/projectM-iOS/Tests/TempoCoordinatorTests.swift
Apps/projectM-iOS/UITests/TempoConfidenceUITests.swift, TapTempoUITests.swift
specs/027-show-011-tap-tempo/contracts/tempo-source.md (note)
```

**Structure Decision**: existing package and app; no new target; `ControlsOverlay.swift` and
`VisualizerView.swift` are not touched (the readout lives in `TempoControls`).

## Complexity Tracking

None.
