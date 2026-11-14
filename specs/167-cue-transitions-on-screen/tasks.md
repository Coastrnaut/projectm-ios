# Tasks: XFADE Cue Transitions On Screen

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Phase 1: Compositor

- [ ] XFADE-T01 `FrozenOutputFrame`, `OutputTransitionPass` and the `Compositor` freeze, begin, end and output hook (XFADE-R2, R3, R4, R5, R6, R7)
- [ ] XFADE-T02 GPU acceptance: red/blue 1 s linear crossfade at 0, 0.5 and 1 s; easeIn; dip to black (XFADE-S1)
- [ ] XFADE-T03 GPU tests: cut byte-identical, Reduce Motion, restart from the blended frame, 20 transitions without leaks, flash guard on strobing transitions, capture and recording output see the blend, freeze across compositors (XFADE-S2, S3, S4)

## Phase 2: App

- [ ] XFADE-T04 `CompositorVisualHost` on the four compositor hosts; `CueTransitionStage` replaces the recorder; AppCoordinator wiring (XFADE-R1, R8)
- [ ] XFADE-T05 App test: a cue with a stored 1 s crossfade through ShowCoordinator drives the incoming compositor for 59 blended frames at 60 Hz; cut and unsupported outcomes (XFADE-S5)
- [ ] XFADE-T06 DEBUG seed and probe; UI test under 30 s (XFADE-R9, S6)

## Phase 3: Polish

- [ ] XFADE-T07 Repo checks, type-check budget, privacy manifest and network symbols
- [ ] XFADE-T08 Spec status, SCN-007 follow-up note, PosterBoard counts

## Dependencies

T01 → T02, T03, T04. T04 → T05, T06. All → T07 → T08.
