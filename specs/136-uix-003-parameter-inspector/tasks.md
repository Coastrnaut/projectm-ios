# Tasks: UIX-003 Context Parameter Inspector

**Input**: `specs/136-uix-003-parameter-inspector/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row (acceptance: "Reset restores declared registry default";
verification: SwiftUI UI tests and the simulator). Budgets (owner rule 7): unit tests ≤ 10 s each,
the UI test < 30 s.

## Phase 1: Setup

- [ ] UIX-003-T01 Create a simulator "UIX3 iPhone 17" (iOS 27.2), symlink `Build` if the xcframeworks are missing, run `xcodegen generate` in the worktree

## Phase 2: Foundational

- [ ] UIX-003-T02 Add `ParameterValueText` (display and spoken text per unit; decimals from the step hint, research UIX-003-D2) and `ParameterInspectorSummary` (name, ID, group, unit, range, step, default; enum range = case names joined by ", ", boolean range = "On or Off") in `Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift`

## Phase 3: User Story 1 — Reset to the registry default (P1) 🎯 MVP

**Independent test**: change a value, reset, compare with `descriptor.defaultValue`.

- [ ] UIX-003-T03 [US1] Add `ParameterInspectorTarget` (get/set of a `ParameterValue`, optional `choices`; "values of the wrong kind are ignored by `set`") and `ParameterInspectorTargets.target(for:settings:)` for the seven inspectable IDs (nil = read-only) in `Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift`
- [ ] UIX-003-T04 [US1] Add `ParameterInspectorReset.reset(_:target:)` (writes `descriptor.defaultValue`, returns "<name> reset to <spoken default>") in `Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift`
- [ ] UIX-003-T05 [US1] Unit tests: for intensity (0…1), radius (fraction of the output), Glow (boolean) and Bars (enum): change the value through the target, reset, assert the `AppSettings` value equals the registry default exactly; knee has no target (read-only); the announcement text; an unknown or unregistered launch-argument ID opens nothing; Reset after a change is one undo step in an `AppCoordinator`'s scene history (US1 scenario 3) — in `Apps/projectM-iOS/Tests/ParameterInspectorTests.swift`
- [ ] UIX-003-T06 [US1] Add the sheet (`ParameterInspectorView`: About, Details, Value with the kind's edit control and Reset, Done), `.parameterInspectorEntry(_:open:)` (context menu "Inspect" + VoiceOver action) and `.parameterInspectorSheet(...)` (DEBUG `-uitestInspectParameter <id>`); Reset ends history coalescing before and after and announces on `.parameter`, in `Apps/projectM-iOS/Views/ParameterInspectorView.swift`
- [ ] UIX-003-T07 [US1] Wire the entry modifier on the seven registry rows and the sheet modifier in `Apps/projectM-iOS/Views/SettingsView.swift` (small edits; other agents edit this file)
- [ ] UIX-003-T08 [US1] UI test (< 30 s): open the inspector for `effect.bloom.intensity`, read unit and range, move the slider, Reset, the value label shows "50%"; VoiceOver label and value of the unit, range and value rows carry the unit (UIX-003-R9); a second test at the AX5 text size reaches Reset and Done (ACC-006 rules) — in `Apps/projectM-iOS/UITests/ParameterInspectorUITests.swift`

## Phase 4: User Story 2 — Understand a parameter (P1)

- [ ] UIX-003-T09 [US2] Unit tests for formatting: intensity "0%…100%", step "1%", default "50%"; radius "0.5%…6.0%", default "2.0%"; Bars range "16, 32, 64, 128"; Glow "On or Off"; spoken "50 percent"; seconds and per-second units — in `Apps/projectM-iOS/Tests/ParameterInspectorTests.swift`

## Phase 5: User Story 3 — Current modulation (P2)

- [ ] UIX-003-T10 [US3] Add `ParameterModulationReading`, `ParameterModulationReader.reading(...)` and `AudioFeatureSource.inspectorName` in `Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift`; `modulatorValue(for:manual:)` in `Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift`; `AppCoordinator.parameterModulationReading(for:)` in `Apps/projectM-iOS/Coordinators/AppCoordinator+ParameterInspector.swift`
- [ ] UIX-003-T11 [US3] Modulation section in the sheet: `TimelineView(.periodic(by: 0.1))` only while a reader is set; text always, a Gauge only when Reduce Motion is off — in `Apps/projectM-iOS/Views/ParameterInspectorView.swift`
- [ ] UIX-003-T12 [US3] Unit tests: no binding → nil; a stub Kick binding → source "Kick → 0%…40% (replace)" and the effective value; a MIDI value → "MIDI control"; a real `NativeSpectrumHost`-free path through `ParameterModulationReader` with the safety-limited flag; the refresh interval constant is 0.1 s (UIX-003-R8) — in `Apps/projectM-iOS/Tests/ParameterInspectorTests.swift`

## Phase 6: Polish

- [ ] UIX-003-T13 Type-check budget build (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`), repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; confirm `-uitestInspectParameter` is compiled only under `#if DEBUG` (UIX-003-R10) and no UserDefaults key was added (UIX-003-R11)
- [ ] UIX-003-T14 Spec status, verified ticks, PosterBoard counts; delete the simulator, derived data and the `Build` symlink

## Dependencies

T01 → T02 → US1 (T03 → T04 → T05; T06 → T07 → T08) → US2 (T09, needs T02) → US3 (T10 → T11, T12) → T13 → T14.
T05, T09 and T12 share one test file, so they run one after another; T10's model part and T06 are in different files [P].

## Implementation strategy

MVP = US1 (the acceptance). US2's display is part of the same sheet; US3 adds the live section.

## Analysis (speckit-analyze, 2026-11-14)

Applied fixes: UIX-003-R9 (VoiceOver units, AX5) had no test → added to T08; R8 (≤ 10 Hz) had no
check → refresh-interval constant tested in T12; R10 and R11 had no verification → added to T13;
US1 scenario 3 (one undo step) and the unknown launch-argument edge case → added to T05. No
constitution conflicts; every requirement R1-R11 now maps to at least one task.
