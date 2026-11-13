# Tasks: SHOW-014 Emergency Blackout

**Input**: `specs/061-show-014-emergency-blackout/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row (deterministic tests + simulator). Budgets (owner rule 7):
unit ~1-2 s, at most 10 s; UI test under 30 s. Never the Simulator panel tool (owner rule 8).

Format: `- [ ] SHOW-014-Tnn [P?] [Story?] Description with file path`

## Phase 1: Setup

- [ ] SHOW-014-T01 Audit OUT-010 against the row and record the mapping of the acceptance onto existing tests in the Baseline of `specs/061-show-014-emergency-blackout/spec.md`

## Phase 2: Foundational

- [ ] SHOW-014-T02 Add `offersEmergencyBlackout` (live or fading in) and `offersRestore` (blacked out) to `OutputBlackout.Phase` in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/OutputBlackout.swift` (data-model table; "the two rules are never both true")
- [ ] SHOW-014-T03 [P] Package test of both rules for all four phases and their disjointness in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/OutputBlackoutTests.swift`

## Phase 3: User Story 1 - Black out with one tap while the controls are hidden (P1)

**Goal**: a persistent corner button blacks out with one tap. **Independent test**: controls hidden → one tap → `outputBlackout` = `black`, controls still hidden, `sourceStarts` = 1; with and without the fake external display.

- [ ] SHOW-014-T04 [US1] Create `EmergencyBlackoutButton` (44 × 44 pt, `eye.slash`, `.regularMaterial` circle, label "Emergency black out", hint, identifier `emergencyBlackout`, action `setBlackout(true)` only) in `Apps/projectM-iOS/Views/EmergencyBlackoutButton.swift`
- [ ] SHOW-014-T05 [US1] Place it in `Apps/projectM-iOS/Views/VisualizerView.swift`: bottom trailing, directly above the controls or the source indicator, shown while `blackoutPhase.offersEmergencyBlackout`
- [ ] SHOW-014-T06 [US1] UI tests in `Apps/projectM-iOS/UITests/EmergencyBlackoutUITests.swift`: device only and with `-uitestExternalDisplay`; controls hidden, one tap, black, controls still hidden, button gone, badge shown, `visualRunning` = yes while black, `sourceStarts` = 1

## Phase 4: User Story 2 - Restore resumes the previous scene (P1)

**Goal**: proof that restore shows the same scene. **Independent test**: same view, same slot, no new placement, running, settings unchanged; same preset name in the UI.

- [ ] SHOW-014-T07 [P] [US2] Unit test in `Apps/projectM-iOS/Tests/EmergencyBlackoutTests.swift`: a real `NativeSpectrumHost` (skip without Metal) under the coordinator; black out through the button's action, restore, advance 1.1 s of fake frames: same view instance in the same slot, `placements` unchanged, host running throughout, glow parameters unchanged; also on an external slot
- [ ] SHOW-014-T08 [US2] In `EmergencyBlackoutUITests`: read `currentPreset` before, restore from the badge, wait `live`, read `currentPreset` after: equal; `sourceStarts` = 1

## Phase 5: User Story 3 - Keyboard shortcut (P2)

**Goal**: B blacks out and restores. **Independent test**: `typeKey("b")` → black; again → live.

- [ ] SHOW-014-T09 [US3] `.keyboardShortcut("b", modifiers: [])` on `EmergencyBlackoutButton` and on the badge's Restore (`OutputBlackoutBadge` in `Apps/projectM-iOS/Views/VisualizerView.swift`)
- [ ] SHOW-014-T10 [US3] In `EmergencyBlackoutUITests`: B → `black`, B → `live`, `sourceStarts` = 1

## Phase 6: Polish

- [ ] SHOW-014-T11 Run the quickstart's test set on `SHOW14 iPhone 17` (iOS 27.2): `projectM-iOSTests`, `EmergencyBlackoutUITests`, `OutputBlackoutUITests`, `ExternalDisplayUITests`, `NativeVisualUITests`; the package tests; `check_compliance.py`, `validate_docs.py`; count PosterBoard reports before and after; delete the simulator
- [ ] SHOW-014-T12 {device} On D1 with HDMI or AirPlay and D2 with an external display and a hardware keyboard: quickstart "Device" steps 1-5 (owner's hands)
- [ ] SHOW-014-T13 Record recording and Save Frame behavior (REC-003 stops, REC-001 refuses; same gate) in the spec's Clarifications (SHOW-014-R8) and close the spec status

## Dependencies

T01 → T02 → T03; T02 → T04 → T05 → T06, T08; T04 → T09 → T10; T07 needs T02 only; T11 after all
code tasks; T12 after T11. US1 is the MVP; US2 adds proof only; US3 is independent of US2.

## Parallel examples

- T03 and T07 (different files, both need only T02).
- T09 can be written with T05 (same file `VisualizerView.swift`: do them in one edit to keep the
  shared file's diff small).
