# Tasks: MIDI-008 MIDI Transport Mapping

**Input**: `specs/157-midi-008-transport/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-008-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes. `{device}` tasks are the final device
stage and stay open until a person runs them.

## Phase 1: Setup

- [ ] MIDI-008-T01 Run `xcodegen generate`, initialize the preset submodules if missing (the `Build` symlink is in place), create the simulator "MIDI8 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run

## Phase 2: Foundational (blocks every story)

- [ ] MIDI-008-T02 [P] `MIDIPressFilter` (`rawEdge`, `accept`, `beginBatch`, `registerPress`; 30 ms window on message timestamps; momentary real-time) and `MIDIEvent.triggerKey` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIPressFilter.swift` (research MIDI-008-D2, D3; contract T1)
- [ ] MIDI-008-T03 [P] Transport actions and trigger keys in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteBinding.swift`: `transport.toggle|play|pause`, `ccbtn:` and `rt:start|stop` lines (real-time with hold unreadable, kept), `isTriggerLine`, list reads all three tags; `MIDILearnEligibility.isTriggerEligible` in `MIDILearnSession.swift` (research MIDI-008-D1, D4; contract T3)
- [ ] MIDI-008-T04 `MIDINoteRouter` over `MIDIPressFilter` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteRouter.swift` (unbound keys skipped first; panic unchanged; `registerPress` for learn) (contract T2)

## Phase 3: User Story 1 - One press, one action (P1) — MVP

**Independent test**: each source kind and repeat pattern fires once per press; a deliberate second press fires again.

- [ ] MIDI-008-T05 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDITransportTests.swift`: filter rules; CC hysteresis; acceptance for note, CC button and real-time × (doubled in one packet list, doubled across two batches 5 ms apart, CC 127 repeated with no 0) through `MIDIByteStreamParser`; deliberate second press; codec round-trip; mixed MIDI-003/004/006/007 lines unchanged; host and the Linux shape (S1, S3, S4, R8)
- [ ] MIDI-008-T06 [US1] App test `Apps/projectM-iOS/Tests/MIDITransportCoordinatorTests.swift`: fake MIDI source → `MIDIMappingCoordinator` → `MIDINoteActionPerformer` with logged actions; the three patterns for each source kind fire Next cue once per press (S1)

## Phase 4: User Story 2 - Play and pause (P1)

- [ ] MIDI-008-T07 [US2] Performer transport actions in `Apps/projectM-iOS/Coordinators/MIDINoteActionPerformer.swift`; `setPausedQuietly(_:)` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`; wiring in `Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift`; app tests: toggle twice pauses then resumes, Play and Pause idempotent, Start → Play / Stop → Pause (research MIDI-008-D5; S2)

## Phase 5: User Story 3 - Learn a transport source (P2)

- [ ] MIDI-008-T08 [US3] Trigger learn in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Notes.swift` (note, CC button, real-time; not real-time on the hold row; learned press registered; texts "CC 20 · Ch 1", "MIDI Start"; CC button ↔ parameter exclusivity) and the MIDI-003 side in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift`; app tests: learn a CC button (learning press fires nothing, duplicate copy fires nothing, two later presses fire twice), learn MIDI Start, moved from a glow parameter and back, Undo (research MIDI-008-D6, D7; R6, R7)
- [ ] MIDI-008-T09 [US3] View: "Transport" section header and footer in `Apps/projectM-iOS/Views/MIDIMappingsView.swift`; DEBUG "Send CC Button" in `Apps/projectM-iOS/Debug/UITestFakeMIDI.swift`
- [ ] MIDI-008-T10 [US3] UI test `Apps/projectM-iOS/UITests/MIDITransportUITests.swift` (under 30 s): seeded show, plug Fake Keys, MIDI Mappings → Learn on Next cue, Send CC Button, read the result, press twice, cue 3 is applied (S5)

## Phase 6: Polish

- [ ] MIDI-008-T11 Update the MIDI-006 assertions on the row list and the CC-in-note-learn fixture; type-check budget on touched files; repository checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols); PosterBoard count; delete the simulator and derived data (S6)
- [ ] MIDI-008-T12 {device} With a physical controller on D1, map a CC button and a pad to Next cue and Play/Pause; each press acts once

## Dependencies

T01 → T02, T03 (parallel) → T04 → US1 (T05, T06) → US2 (T07) → US3 (T08-T10) → T11 → T12.

## Parallel examples

- T02 and T03 touch different files.
- T05 (package tests) can be written while T07 is built.

## Implementation strategy

MVP is US1 (the row's acceptance). US2 adds the play/pause actions; US3 adds learn and the UI test.
