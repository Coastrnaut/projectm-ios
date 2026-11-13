# Tasks: PERF-010 Crash-Safe Session Recovery

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/session-recovery.md](contracts/session-recovery.md)

Budgets (owner rule 7): unit tests about 1-2 s each, UI tests under 30 s each. `{device}` tasks need
the owner's device and stay open until run.

## Phase 1: Foundation

- [ ] PERF-010-T01 Pure policy `Apps/projectM-iOS/Coordinators/SessionRecoveryPolicy.swift`: record,
  `LaunchDecision`, `launch(record:)`, reopen/fresh transitions, N = 2, the DEBUG suppression rule
  (PERF-010-R1, R9, R12; data-model).
- [ ] PERF-010-T02 Unit tests `Apps/projectM-iOS/Tests/SessionRecoveryTests.swift` for T01: clean exit,
  kill, foreground/background cycle, crash loop within 2 sessions, counter cleared after 2,
  suppression arguments.

## Phase 2: US1 + US2 — no listener or camera without consent; the offer (P1)

- [ ] PERF-010-T03 `SessionRecoveryCoordinator.swift`: UserDefaults store of the record, lifecycle
  observers (background/terminate clear, foreground set), launch decision, offer state, held
  visual, diagnostics event, DEBUG probe (PERF-010-R1, R4, R8, R11, R12; contract C1, C4).
- [ ] PERF-010-T04 SCN-002 hook: `SceneAutosaveCoordinator.holdCommittedScene` (load without adopting)
  and `reopen(_:)` (adopt and return values) (research D3).
- [ ] PERF-010-T05 `AppCoordinator` launch order (contract C1): decide before the OSC coordinator is
  created; abnormal → OSC toggle off, scene defaults, held scene; `reopenLastScene()`,
  `startFresh()`; `-uitestResetNotice` clears the record (PERF-010-R2, R3, R5, R6, R7, R10).
- [ ] PERF-010-T06 `SessionRecoveryOfferCard.swift` on the chooser and the visualizer, VoiceOver
  announcement; DEBUG probe in VisualizerView; DEBUG "Crash now" button in Settings (contract C2).
- [ ] PERF-010-T07 Unit tests for the launch policy in `SessionRecoveryTests`: after an abnormal exit
  the OSC receiver is never started and the stored toggle is off; normal exit keeps OSC on; the offer
  is pending with/without Reopen; Start fresh leaves scene settings at defaults; Reopen applies the
  held visual and values; camera visual never chosen.
- [ ] PERF-010-T08 Acceptance UI test `Apps/projectM-iOS/UITests/SessionRecoveryUITests.swift`: OSC on
  and Camera (stub) → `terminate()` → relaunch: offer, no OSC badge, probe `osc=off`, no camera badge
  or frames; the controls and Settings work with the offer shown (S5); Reopen → Circular Spectrum
  16 bars, still no OSC or camera (PERF-010-S1-S3, S5).
- [ ] PERF-010-T09 Clean-exit UI test: Home then terminate → no offer, OSC listening again (then
  stopped to leave no state) (PERF-010-R10, S2).

## Phase 3: US3 — crash loop (P2)

- [ ] PERF-010-T10 UI test: Reopen, terminate, relaunch → offer without Reopen (PERF-010-R9, S4).

## Phase 4: Polish

- [ ] PERF-010-T11 ADR (next free number) for the OSC toggle after an abnormal exit (OSC-001-R15
  override, ADR-0032); privacy policy lists the three stored values (PERF-010-R13).
- [ ] PERF-010-T12 Regression: projectM-iOSTests, SceneAutosaveUITests, OSCReceiverUITests,
  CameraUITests, NativeVisualUITests pass with the suppression.
- [ ] PERF-010-T13 `check_compliance.py`, `validate_docs.py`, `check_privacy_manifest.py` on the Debug
  app; PosterBoard count before and after.
- [ ] PERF-010-T14 Roadmap/status notes: spec Status, tasks verified.
- [ ] PERF-010-T15 `{device}` D1: real crash with the DEBUG "Crash now" button, relaunch from the home
  screen (quickstart, Device).

## Analysis (speckit-analyze, 2026-11-13)

Coverage: R1 T01-T03; R2 T05, T07, T08; R3 T07, T08; R4 T06, T08; R5 T05, T07; R6 T05, T07, T08;
R7 T05, T07; R8 T03, T07; R9 T01, T02, T10; R10 T05, T09; R11 T03; R12 T01, T03, T06, T12; R13 T11; R14 (added at implementation) T02, T07.
S1 T08; S2 T08, T09; S3 T08; S4 T02, T10; S5 T08 (fixed: S5 had no task). No constitution conflict;
terminology aligned ("abnormal exit", "offer", "held scene"). No other findings.

## Dependencies

T01 → T02; T01 → T03 → T05; T04 → T05; T05 → T06 → T07, T08 → T09, T10; T11-T14 last; T15 after merge.
