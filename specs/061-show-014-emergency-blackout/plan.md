# Implementation Plan: SHOW-014 Emergency Blackout

**Branch**: `feature/show-014` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/061-show-014-emergency-blackout/spec.md`

## Summary

OUT-010 already makes the output black inside the tap's handling and restores the same running
visual with a flash-safe fade. SHOW-014 adds the emergency entry point and the proof:

1. `OutputBlackout.Phase` (PresentationLifecycle, pure Swift) gains two rules:
   `offersEmergencyBlackout` (live or fading in) and `offersRestore` (blacked out). They decide
   when the corner button and the badge's Restore are shown, and so which of them carries the B key
   (research SHOW-014-D1, D3).
2. A new `EmergencyBlackoutButton` (SwiftUI, app) is a 44 × 44 pt icon button with the label
   "Emergency black out", on the same material as the other badges, placed in the visualizer's
   bottom stack at the trailing edge, above the controls or the source indicator, with or without
   the controls. Its action is `ExternalDisplayCoordinator.setBlackout(true)` (never a toggle, never
   `showControls()`), and it carries `.keyboardShortcut("b", modifiers: [])`.
3. OUT-010's badge Restore also carries `.keyboardShortcut("b", modifiers: [])`, so B toggles.
4. Tests: package tests for the two rules; an app unit test that black-out then restore keeps the
   same visual view in the same slot, running, with no new placement and unchanged glow settings
   (a real `NativeSpectrumHost`, skipped without Metal); a UI test with the controls hidden, with
   and without the DEBUG fake external display, that compares the preset name before and after and
   sends the B key.
5. ADR-0023 decision 8 gets a SHOW-014 paragraph (no default overridden, so no new ADR).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI).

**Primary Dependencies**: SwiftUI (`Button`, `keyboardShortcut`), the OUT-010 coordinator and
model. No new dependency.

**Storage**: none (FR-065).

**Testing**: `swift test --package-path Packages/PresentationLifecycle --filter OutputBlackoutTests`;
app unit tests `projectM-iOSTests` (new `EmergencyBlackoutTests`); UI tests
`EmergencyBlackoutUITests` plus the regression set `OutputBlackoutUITests`, `ExternalDisplayUITests`,
`NativeVisualUITests` on an iOS 27.2 simulator created for this feature (`SHOW14 iPhone 17`).

**Target Platform**: iOS/iPadOS 26+.

**Project Type**: mobile app plus a small package addition.

**Performance Goals**: no per-frame work; the button is a static view.

**Constraints**: public APIs only; explicit closure types; no main-actor mutation in
setUp/tearDown; no wall-clock assertions; owner rule 7 budgets (unit ~1-2 s, UI test < 30 s);
never the Simulator panel tool (owner rule 8).

**Scale/Scope**: about 80 lines of source and 200 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | SwiftUI `Button`, `keyboardShortcut` | Pass |
| IV/V. Truthful labeling, no universal claims | No compatibility claim; device checks are `{device}` tasks | Pass |
| VI. Modular boundaries | Visibility rules in `PresentationLifecycle`; view in the app | Pass |
| VII. Real-time audio safety | No audio-path change | Pass |
| VIII. Upstream fidelity | projectM and ANGLE untouched | Pass |
| X. Evidence | Host and simulator tests; simulator never device evidence | Pass |
| Privacy / local-first | Nothing stored, no network, no new logging | Pass |
| Flash safety (ADR-0011) | Same blackout and fade as OUT-010; the button only darkens | Pass |
| Accessibility (FR-070) | Visible labeled button, reachable without the controls; no hidden gesture | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/061-show-014-emergency-blackout/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/emergency-blackout.md
└── checklists/requirements.md
docs/adr/0023-external-display-scene.md          # amended: decision 8, SHOW-014 paragraph
```

### Source Code (repository root)

```text
Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputBlackout.swift    # + offersEmergencyBlackout, offersRestore
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputBlackoutTests.swift
Apps/projectM-iOS/Views/EmergencyBlackoutButton.swift          # NEW
Apps/projectM-iOS/Views/VisualizerView.swift                   # place the button; B on the badge's Restore
Apps/projectM-iOS/Tests/EmergencyBlackoutTests.swift           # NEW
Apps/projectM-iOS/UITests/EmergencyBlackoutUITests.swift       # NEW
```

**Structure Decision**: as OUT-010: rules in the package (testable on Linux), view in the app. A new
view file keeps edits to the shared `VisualizerView.swift` small (REC-012 and SCN-001 run in
parallel).

## Complexity Tracking

None: no constitution violation.
