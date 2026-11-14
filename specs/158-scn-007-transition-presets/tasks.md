# Tasks: SCN-007 Scene Transition Presets

**Input**: [spec.md](spec.md), [plan.md](plan.md), [contracts/show-cue-transition.md](contracts/show-cue-transition.md)

## Phase 1: Model (US1, US2)

- [ ] SCN-007-T01 Compositor: `SceneTransitionSpec.curve` and `SceneTransitionClock.curve` (MappingCurve), Codable only when set, `invalidCurve` error; Compositor target depends on ParameterGraph (SCN-007-R7)
- [ ] SCN-007-T02 Compositor tests: curve shapes eased progress on an injected frame clock; nil curve keeps CMP-014 encoding; invalid curve refused (SCN-007-S5)
- [ ] SCN-007-T03 Bus test: a curve spec drives `clock.easedProgress` and the mix at every frame (SCN-007-S5)
- [ ] SCN-007-T04 ShowControl: `ShowTransitionType`, `ShowCueTransition` (validation), `ShowCue.transition`, `setTransition`, insert with transition; ShowControl depends on ParameterGraph (SCN-007-R1, R8)
- [ ] SCN-007-T05 ShowControl: `show.json` per-cue `transition` encode/lenient decode, warnings (SCN-007-R2, R4)
- [ ] SCN-007-T06 ShowControl tests: round trip bit-identical, legacy bytes, unknown type kept, invalid dropped, bounds (SCN-007-S2, S3)
- [ ] SCN-007-T07 LibraryBackup test: backup round trip keeps transitions and bytes (SCN-007-R10, S4)

## Phase 2: App (US1, US3)

- [ ] SCN-007-T08 `CueTransitionResolver` and `CueTransitionDriving`; ShowCoordinator drives on apply, `setTransition`, Duplicate copies (SCN-007-R5, R6, R8)
- [ ] SCN-007-T09 AppCoordinator wiring: safety state and a recording driver (DEBUG probe) (SCN-007-R5)
- [ ] SCN-007-T10 Acceptance test: distinct transitions, save, reload with a new coordinator, exact equality, driver spy gets exact specs; safety resolution tests (SCN-007-S1)
- [ ] SCN-007-T11 `CueTransitionView` sheet and ShowEditorView row line and actions (SCN-007-R9)
- [ ] SCN-007-T12 UI test under 30 s: set a cue's transition, relaunch, values persist (SCN-007-S6)

## Phase 3: Polish

- [ ] SCN-007-T13 Repo checks, type-check budget, privacy manifest and network symbols on the built app
- [ ] SCN-007-T14 Spec status, PosterBoard counts

## Dependencies

T01 → T02, T03, T08. T04 → T05 → T06, T07, T08. T08 → T09, T10, T11 → T12. All → T13 → T14.
